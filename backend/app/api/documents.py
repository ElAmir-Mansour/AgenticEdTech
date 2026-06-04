import os
import logging
import shutil
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.database import get_db
from app.models.database import Document, Project, Concept
from app.models.schemas import DocumentResponse
from app.auth.dependencies import get_current_user_id
from app.workers.pool import worker_pool
from app.utils.ingestion_service import process_document_ingestion, get_encoder
from app.utils.qdrant_client import get_qdrant_client
from app.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()

# Directory to store uploaded files
STORAGE_DIR = os.path.abspath(os.path.join(os.getcwd(), "storage", "documents"))
os.makedirs(STORAGE_DIR, exist_ok=True)

@router.post("/{project_id}/documents", response_model=DocumentResponse, status_code=status.HTTP_201_CREATED)
async def upload_document(
    project_id: str,
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Uploads a PDF or text document and queues it for background semantic indexing."""
    # 1. Verify project ownership
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )
        
    # Validate MIME type
    if file.content_type not in ["application/pdf", "text/plain"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only application/pdf and text/plain files are supported"
        )
        
    # 2. Save file to disk
    file_id = str(uuid_generator())
    file_ext = ".pdf" if file.content_type == "application/pdf" else ".txt"
    storage_path = os.path.join(STORAGE_DIR, f"{file_id}{file_ext}")
    
    try:
        with open(storage_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save uploaded file: {str(e)}"
        )
        
    # Get file size
    file_size = os.path.getsize(storage_path)
    
    # 3. Create Document Record
    new_doc = Document(
        id=file_id,
        project_id=project_id,
        filename=file.filename,
        mime_type=file.content_type,
        file_size_bytes=file_size,
        storage_path=storage_path,
        processing_status="pending"
    )
    
    db.add(new_doc)
    await db.commit()
    await db.refresh(new_doc)
    
    # 4. Dispatch background ingestion processing
    await worker_pool.submit(process_document_ingestion, new_doc.id)
    
    return new_doc


@router.get("/{project_id}/documents", response_model=list[DocumentResponse])
async def list_documents(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Lists all uploaded documents in the project context."""
    # Verify project ownership
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    if not proj_result.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )
        
    doc_result = await db.execute(
        select(Document).where(Document.project_id == project_id)
    )
    return doc_result.scalars().all()


@router.delete("/{project_id}/documents/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_document(
    project_id: str,
    document_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Deletes a document from SQL, discards the vector chunks in Qdrant, and deletes the local file."""
    # Verify project ownership
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    if not proj_result.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )
        
    doc_result = await db.execute(
        select(Document).where(Document.id == document_id, Document.project_id == project_id)
    )
    document = doc_result.scalars().first()
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found in this project context"
        )
        
    # 1. Remove file from storage
    if os.path.exists(document.storage_path):
        try:
            os.remove(document.storage_path)
        except Exception as e:
            # Log and proceed, do not block database cleanup
            print(f"Failed to delete file from disk: {e}")
            
    # 2. Delete points from Qdrant vector database
    try:
        qdrant = get_qdrant_client()
        from qdrant_client.models import Filter, FieldCondition, MatchValue
        qdrant.delete(
            collection_name="document_chunks",
            points_selector=Filter(
                must=[
                    FieldCondition(
                        key="document_id",
                        match=MatchValue(value=document_id)
                    )
                ]
            )
        )
    except Exception as e:
        print(f"Failed to delete points from Qdrant collection: {e}")
        
    # 3. SQL cleanups (cascades automatically delete dependencies or handles set null)
    # Concepts created by this document are set to NULL for source_document_id.
    # Alternatively we can delete them if desired, let's keep them and clear references or delete them.
    # We will delete them if they have no other sources
    await db.delete(document)
    await db.commit()
    
    return


@router.post("/{project_id}/query")
async def rag_query(
    project_id: str,
    query_data: dict,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Searches uploaded documents using RAG and returns grounded answers.
    
    Performs semantic vector search in Qdrant, retrieves relevant chunks,
    and optionally uses Gemini to synthesize a grounded answer.
    
    Request body:
        {"question": "What is Scrum?", "topK": 5, "generateAnswer": true}
    """
    # Verify project ownership
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found"
        )
    
    question = query_data.get("question", "").strip()
    if not question:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Question is required"
        )
    
    top_k = query_data.get("topK", 5)
    generate_answer = query_data.get("generateAnswer", True)
    
    # Step 1: Encode query and search Qdrant
    chunks = []
    doc_filename_cache = {}  # Cache document_id -> filename lookups
    try:
        qdrant = get_qdrant_client()
        
        # Reuse the shared encoder from ingestion_service
        encoder = get_encoder()
        query_vector = encoder.encode(question).tolist()
        
        from qdrant_client.models import Filter, FieldCondition, MatchValue
        
        search_filter = Filter(
            must=[FieldCondition(key="project_id", match=MatchValue(value=project_id))]
        )
        
        # Qdrant client 1.18+ uses query_points, older versions use search
        try:
            results = qdrant.query_points(
                collection_name="document_chunks",
                query=query_vector,
                query_filter=search_filter,
                limit=top_k,
                with_payload=True,
            ).points
        except (AttributeError, TypeError):
            results = qdrant.search(
                collection_name="document_chunks",
                query_vector=query_vector,
                query_filter=search_filter,
                limit=top_k,
                with_payload=True,
            )
        
        for r in results:
            payload = r.payload or {}
            doc_id = payload.get("document_id", "")
            
            # Resolve filename from payload or DB cache
            filename = payload.get("filename", None)
            if not filename and doc_id:
                if doc_id not in doc_filename_cache:
                    doc_q = await db.execute(select(Document.filename).where(Document.id == doc_id))
                    row = doc_q.first()
                    doc_filename_cache[doc_id] = row[0] if row else "Unknown"
                filename = doc_filename_cache[doc_id]
            
            score = getattr(r, 'score', 0.0)
            chunks.append({
                "content": payload.get("content", ""),
                "documentId": doc_id,
                "filename": filename or "Unknown",
                "page": payload.get("page_number", None),
                "chunkIndex": payload.get("chunk_index", None),
                "score": round(score, 4),
            })
            
    except Exception as e:
        logger.error(f"RAG vector search failed: {e}", exc_info=True)
        return {
            "question": question,
            "answer": None,
            "chunks": [],
            "error": f"Vector search unavailable: {str(e)}"
        }
    
    # Step 2: Optionally generate grounded answer with Gemini
    answer = None
    if generate_answer and chunks:
        context = "\n\n---\n\n".join([
            f"[Source: {c['filename']}, Page {c.get('page', '?')}]\n{c['content']}"
            for c in chunks[:3]  # Use top 3 chunks for context
        ])
        from app.agents.graph import get_llm
        llm = await get_llm(project_id, db=db)
        if llm:
            try:
                from langchain_core.prompts import ChatPromptTemplate
                
                prompt = ChatPromptTemplate.from_messages([
                    ("system", "You are a curriculum design assistant. Answer the question "
                     "using ONLY the provided source material. If the answer cannot be found "
                     "in the sources, say 'This information is not available in the uploaded documents.' "
                     "Cite the source document and page when possible."),
                    ("user", "SOURCES:\n{context}\n\nQUESTION: {question}")
                ])
                
                chain = prompt | llm
                response = await chain.ainvoke({"context": context, "question": question})
                answer = response.content
            except Exception as e:
                logger.error(f"RAG answer generation failed: {e}", exc_info=True)
                answer = f"Answer generation unavailable: {str(e)}"
        else:
            answer = "AI answer generation requires a configured LLM provider. Please check project settings."
    
    return {
        "question": question,
        "answer": answer,
        "chunks": chunks,
    }


def uuid_generator() -> str:
    import uuid
    return str(uuid.uuid4())


@router.get("/{project_id}/documents/chunk-query")
async def get_document_chunk_source(
    project_id: str,
    filename: str,
    page: int,
    db: AsyncSession = Depends(get_db)
):
    """Retrieves the matching text chunk from Qdrant by filename and page number for verification preview."""
    try:
        qdrant = get_qdrant_client()
        from qdrant_client.models import Filter, FieldCondition, MatchValue
        
        search_filter = Filter(
            must=[
                FieldCondition(key="project_id", match=MatchValue(value=project_id)),
                FieldCondition(key="filename", match=MatchValue(value=filename)),
                FieldCondition(key="page_number", match=MatchValue(value=page))
            ]
        )
        
        # We search with a dummy query vector since we are just doing exact payload filtering
        zero_vector = [0.0] * 384
        
        try:
            results = qdrant.query_points(
                collection_name="document_chunks",
                query=zero_vector,
                query_filter=search_filter,
                limit=1,
                with_payload=True
            ).points
        except (AttributeError, TypeError):
            results = qdrant.search(
                collection_name="document_chunks",
                query_vector=zero_vector,
                query_filter=search_filter,
                limit=1,
                with_payload=True
            )
            
        if results:
            payload = results[0].payload or {}
            return {
                "found": True,
                "content": payload.get("content", ""),
                "filename": filename,
                "page": page,
                "section_title": payload.get("section_title", "")
            }
            
        return {
            "found": False,
            "message": f"No matching indexed chunk found for {filename} page {page}"
        }
    except Exception as e:
        logger.error(f"Failed to query source chunk: {e}", exc_info=True)
        return {
            "found": False,
            "message": f"Source chunk query failed: {str(e)}"
        }


