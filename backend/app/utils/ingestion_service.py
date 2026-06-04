import os
import logging
import uuid
import random
from typing import List, Dict, Any, Tuple, Optional
import fitz  # PyMuPDF
import spacy
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.utils.qdrant_client import get_qdrant_client
from app.models.database import Document, Concept, ConceptPrerequisite
from app.config import settings

# Setup logging
logger = logging.getLogger(__name__)

# Initialize spaCy model
try:
    nlp = spacy.load("en_core_web_sm")
except Exception as e:
    logger.warning(f"Could not load spaCy en_core_web_sm, trying to download/load fallback: {e}")
    # Fallback to a simple rule-based or empty model if load fails
    nlp = spacy.blank("en")

# Lazy-loaded SentenceTransformer model to save memory/startup time
_encoder = None

def get_encoder():
    global _encoder
    if _encoder is not None:
        return _encoder
    try:
        from sentence_transformers import SentenceTransformer
        logger.info("Initializing SentenceTransformer all-MiniLM-L6-v2...")
        _encoder = SentenceTransformer("all-MiniLM-L6-v2")
    except Exception as e:
        logger.error(f"Failed to load SentenceTransformer: {e}. Using mock encoder.")
        class MockEncoder:
            def encode(self, texts):
                # Return random vector of size 384 for each text
                if isinstance(texts, str):
                    return [random.uniform(-1, 1) for _ in range(384)]
                return [[random.uniform(-1, 1) for _ in range(384)] for _ in texts]
        _encoder = MockEncoder()
    return _encoder


async def process_document_ingestion(document_id: str, db: AsyncSession = None):
    """Processes document ingestion in the background.
    
    1. Reads & parses document text.
    2. Performs heading-based semantic chunking.
    3. Indexes chunks into Qdrant.
    4. Extracts Concepts & Prerequisite Graphs using Gemini (or spaCy fallback).
    5. Updates SQLite status.
    """
    logger.info(f"Starting background ingestion for Document ID: {document_id}")
    
    # Use context manager if session not provided
    db_provided = db is not None
    if not db_provided:
        from app.database import async_session_maker
        db = async_session_maker()
        
    try:
        try:
            # 1. Fetch document from DB
            result = await db.execute(select(Document).where(Document.id == document_id))
            document = result.scalars().first()
            if not document:
                logger.error(f"Document {document_id} not found in DB")
                return
                
            document.processing_status = "processing"
            document.meta = {"stage": "parsing", "progress": 0.15, "message": "Parsing document syntax..."}
            await db.commit()
        except Exception as e:
            logger.error(f"Failed to start ingestion database handshake: {e}")
            return
            
        try:
            file_path = document.storage_path
            if not os.path.exists(file_path):
                raise FileNotFoundError(f"File not found at {file_path}")
                
            # Extract text based on file format
            chunks = []
            if document.mime_type == "application/pdf":
                chunks = parse_pdf_semantic_chunks(file_path)
            else:
                chunks = parse_text_semantic_chunks(file_path)
                
            logger.info(f"Extracted {len(chunks)} chunks from {document.filename}")
            
            document.meta = {"stage": "chunking", "progress": 0.4, "message": "Generating cognitive text chunks..."}
            await db.commit()
            
            # 2. Vector Indexing into Qdrant
            if chunks:
                document.meta = {"stage": "indexing", "progress": 0.65, "message": "Indexing chunks in Qdrant Vector Cloud..."}
                await db.commit()
                await index_chunks_in_qdrant(document.project_id, document.id, chunks, document.filename)
                document.chunk_count = len(chunks)
                
            # 3. Extract Concepts and Prerequisites
            document.meta = {"stage": "extracting", "progress": 0.85, "message": "Assembling concept dependency graph..."}
            await db.commit()
            concepts, relationships = await extract_concepts_and_prerequisites(
                project_id=document.project_id,
                document_id=document.id,
                chunks=chunks
            )
            
            # Save concepts and prerequisites to DB
            # Map concept names to DB objects so we can create prerequisite references
            concept_db_map = {}
            for c_data in concepts:
                # Check if concept already exists in this project
                exist_q = await db.execute(
                    select(Concept).where(Concept.project_id == document.project_id, Concept.name == c_data["name"])
                )
                concept_obj = exist_q.scalars().first()
                if not concept_obj:
                    concept_obj = Concept(
                        project_id=document.project_id,
                        name=c_data["name"],
                        description=c_data["description"],
                        blooms_level=c_data.get("blooms_level", "understand"),
                        source_document_id=document.id,
                        source_page=c_data.get("source_page", 1)
                    )
                    db.add(concept_obj)
                concept_db_map[c_data["name"]] = concept_obj
                
            await db.commit() # Save concepts first to get IDs
            
            # Save prerequisites
            for r_data in relationships:
                parent_name = r_data["prerequisite"]
                child_name = r_data["concept"]
                
                if parent_name in concept_db_map and child_name in concept_db_map:
                    parent_id = concept_db_map[parent_name].id
                    child_id = concept_db_map[child_name].id
                    
                    # Check for existing duplicate link
                    link_q = await db.execute(
                        select(ConceptPrerequisite).where(
                            ConceptPrerequisite.concept_id == child_id,
                            ConceptPrerequisite.prerequisite_id == parent_id
                        )
                    )
                    link_obj = link_q.scalars().first()
                    if not link_obj:
                        new_link = ConceptPrerequisite(
                            concept_id=child_id,
                            prerequisite_id=parent_id,
                            confidence=r_data.get("confidence", 0.8),
                            relationship="requires"
                        )
                        db.add(new_link)
                        
            document.processing_status = "completed"
            document.meta = {"stage": "completed", "progress": 1.0, "message": "Ready"}
            await db.commit()
            logger.info(f"Ingestion successful for Document ID: {document_id}")
            
        except Exception as e:
            logger.error(f"Failed to ingest document {document_id}: {str(e)}", exc_info=True)
            try:
                await db.rollback()
            except Exception:
                pass
            
            try:
                # Re-fetch document to see if it still exists before updating status
                result = await db.execute(select(Document).where(Document.id == document_id))
                doc = result.scalars().first()
                if doc:
                    doc.processing_status = "failed"
                    doc.meta = {"stage": "failed", "progress": 1.0, "error": str(e), "message": f"Failed: {str(e)}"}
                    await db.commit()
            except Exception as db_err:
                logger.error(f"Failed to update document status to failed in database: {db_err}")
    finally:
        if not db_provided:
            await db.close()


def parse_pdf_semantic_chunks(file_path: str) -> List[Dict[str, Any]]:
    """Parses a PDF using PyMuPDF, identifying sections and splitting semantically."""
    doc = fitz.open(file_path)
    chunks = []
    
    current_section = "Introduction"
    current_content = []
    current_page = 1
    
    for page_num in range(len(doc)):
        page = doc[page_num]
        text_blocks = page.get_text("blocks")
        
        for block in text_blocks:
            text = block[4].strip()
            if not text:
                continue
                
            # Basic rule: if a line is short, capitalized, or looks like a heading
            is_heading = False
            lines = text.split("\n")
            if len(lines) == 1 and len(text) < 100:
                # Check if it starts with numbering or is title cased
                if (text[0].isdigit() and "." in text) or text.isupper() or len(text.split()) < 6:
                    is_heading = True
            
            if is_heading:
                # Save previous chunk if it has content
                if current_content:
                    chunks.append({
                        "section_title": current_section,
                        "content": "\n".join(current_content),
                        "page_number": current_page
                    })
                    current_content = []
                current_section = text
                current_page = page_num + 1
            else:
                current_content.append(text)
                
            # Split if current chunk size exceeds 1000 characters to keep search precise
            total_len = sum(len(t) for t in current_content)
            if total_len > 1000:
                chunks.append({
                    "section_title": current_section,
                    "content": "\n".join(current_content),
                    "page_number": page_num + 1
                })
                current_content = []
                
    if current_content:
        chunks.append({
            "section_title": current_section,
            "content": "\n".join(current_content),
            "page_number": current_page
        })
        
    doc.close()
    return chunks


def parse_text_semantic_chunks(file_path: str) -> List[Dict[str, Any]]:
    """Parses a plain text file, splitting by paragraphs."""
    with open(file_path, "r", encoding="utf-8") as f:
        text = f.read()
        
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    chunks = []
    current_section = "Main Content"
    current_content = []
    
    for i, para in enumerate(paragraphs):
        current_content.append(para)
        total_len = sum(len(t) for t in current_content)
        if total_len > 800:
            chunks.append({
                "section_title": current_section,
                "content": "\n\n".join(current_content),
                "page_number": 1
            })
            current_content = []
            
    if current_content:
        chunks.append({
            "section_title": current_section,
            "content": "\n\n".join(current_content),
            "page_number": 1
        })
        
    return chunks


async def index_chunks_in_qdrant(project_id: str, document_id: str, chunks: List[Dict[str, Any]], filename: str = "Unknown"):
    """Encodes chunks using SentenceTransformers and indexes them in Qdrant."""
    client = get_qdrant_client()
    collection_name = "document_chunks"
    
    # 1. Ensure collection exists
    from qdrant_client.models import Distance, VectorParams
    
    # Check if collection exists
    collections = client.get_collections().collections
    exists = any(c.name == collection_name for c in collections)
    
    # Get vector size dynamically
    encoder = get_encoder()
    sample_vector = encoder.encode("test string")
    vector_size = len(sample_vector)
    
    if not exists:
        logger.info(f"Creating Qdrant collection: {collection_name} with dimension {vector_size}")
        client.create_collection(
            collection_name=collection_name,
            vectors_config=VectorParams(size=vector_size, distance=Distance.COSINE)
        )
        
    # Ensure payload index exists for filtering (required by some Qdrant configurations)
    from qdrant_client.models import PayloadSchemaType
    for field in ["project_id", "document_id"]:
        try:
            client.create_payload_index(
                collection_name=collection_name,
                field_name=field,
                field_schema=PayloadSchemaType.KEYWORD
            )
        except Exception as e:
            logger.debug(f"Payload index for {field} may already exist or failed: {e}")
        
    # 2. Encode and upload points
    points = []
    for idx, chunk in enumerate(chunks):
        vector = encoder.encode(chunk["content"]).tolist()
        point_id = str(uuid.uuid4())
        payload = {
            "project_id": project_id,
            "document_id": document_id,
            "filename": filename,
            "chunk_index": idx,
            "section_title": chunk["section_title"],
            "page_number": chunk["page_number"],
            "content": chunk["content"]
        }
        points.append({
            "id": point_id,
            "vector": vector,
            "payload": payload
        })
        
    # Upsert points
    client.upsert(
        collection_name=collection_name,
        points=points
    )
    logger.info(f"Successfully upserted {len(points)} vectors to Qdrant collection {collection_name}")


async def extract_concepts_and_prerequisites(
    project_id: str,
    document_id: str,
    chunks: List[Dict[str, Any]]
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Extracts educational concepts and dependency prerequisite links.
    
    Uses dynamic project-configured LLM if available, falling back to local spaCy NLP.
    """
    try:
        logger.info(f"Using project-specific LLM to extract concept graph for project {project_id}...")
        return await extract_concepts_via_gemini(chunks, project_id)
    except Exception as e:
        logger.error(f"LLM concept extraction failed: {e}. Falling back to spaCy local NLP extraction.")
        
    # Local fallback
    logger.info("Using local spaCy NLP concept extraction...")
    return extract_concepts_via_spacy(chunks)


async def extract_concepts_via_gemini(chunks: List[Dict[str, Any]], project_id: Optional[str] = None) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Calls project-configured LLM (or fallback) to extract structural concepts & dependencies."""
    from app.agents.graph import get_llm
    import json
    
    llm = await get_llm(project_id)
    if not llm:
        raise ValueError("No LLM configured or available for concept extraction")
    
    # We sample a few chunks if the document is large to respect rate limits
    sampled_chunks = chunks[:15]
    text_content = "\n\n".join([
        f"Section: {c['section_title']} (Page {c['page_number']})\n{c['content']}"
        for c in sampled_chunks
    ])
    
    prompt = ChatPromptTemplate.from_messages([
        ("system", """You are an expert instructional designer and curriculum engineer.
Your task is to analyze the provided textbook content and extract:
1. Core academic/educational concepts introduced.
2. Direct prerequisite dependencies between these concepts (i.e. Concept A must be understood before Concept B).

Return ONLY a valid JSON object matching the schema below:
{{
  "concepts": [
    {{
      "name": "Concept Name",
      "description": "Short definition/description",
      "blooms_level": "one of: remember, understand, apply, analyze, evaluate, create",
      "source_page": 1
    }}
  ],
  "relationships": [
    {{
      "prerequisite": "Concept A Name",
      "concept": "Concept B Name",
      "confidence": 0.85
    }}
  ]
}}

Ensure that all prerequisite and concept names in 'relationships' match EXACTLY with names declared in the 'concepts' list.
"""),
        ("user", "Here is the content to analyze:\n\n{text}")
    ])
    
    chain = prompt | llm
    response = await chain.ainvoke({"text": text_content})
    raw_content = response.content.strip()
    
    # Clean up response text if wrapped in markdown code blocks
    if raw_content.startswith("```json"):
        raw_content = raw_content[7:]
    if raw_content.endswith("```"):
        raw_content = raw_content[:-3]
    raw_content = raw_content.strip()
    
    data = json.loads(raw_content)
    return data.get("concepts", []), data.get("relationships", [])


def extract_concepts_via_spacy(chunks: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Uses a rule-based approach on noun chunks and frequencies to build a mock concept graph."""
    text = " ".join([c["content"] for c in chunks[:10]])
    doc = nlp(text)
    
    # Extract noun chunks, filter by length and stop words
    noun_counts = {}
    for chunk in doc.noun_chunks:
        clean_text = chunk.root.lemma_.lower()
        if len(clean_text) > 3 and not chunk.root.is_stop and chunk.root.is_alpha:
            title_text = chunk.text.title()
            noun_counts[title_text] = noun_counts.get(title_text, 0) + 1
            
    # Select top 5-8 noun chunks as concepts
    sorted_nouns = sorted(noun_counts.items(), key=lambda x: x[1], reverse=True)
    top_concepts = [name for name, count in sorted_nouns[:8]]
    
    concepts_list = []
    relationships_list = []
    
    blooms_pool = ["remember", "understand", "apply", "analyze"]
    
    for idx, name in enumerate(top_concepts):
        # Find a sentence containing this concept for description
        desc = f"Core educational block relating to the topic of {name}."
        for sent in doc.sents:
            if name.lower() in sent.text.lower():
                desc = sent.text.strip()
                if len(desc) > 150:
                    desc = desc[:147] + "..."
                break
                
        concepts_list.append({
            "name": name,
            "description": desc,
            "blooms_level": blooms_pool[idx % len(blooms_pool)],
            "source_page": idx + 1
        })
        
        # Link to subsequent concept to simulate a linear dependency chain
        if idx > 0:
            relationships_list.append({
                "prerequisite": top_concepts[idx - 1],
                "concept": name,
                "confidence": round(0.7 + (idx * 0.03), 2)
            })
            
    return concepts_list, relationships_list
