from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy import func
from app.database import get_db
from app.models.database import Project, Document, CurriculumModule, SimulationRun, PersonaResult, Concept
from app.models.schemas import ProjectCreate, ProjectUpdate, ProjectResponse, LLMTestConfigRequest
from app.auth.dependencies import get_current_user_id

router = APIRouter()

@router.get("/", response_model=list[ProjectResponse])
async def list_projects(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Lists all projects owned by the authenticated user."""
    result = await db.execute(select(Project).where(Project.owner_id == user_id))
    return result.scalars().all()

@router.post("/", response_model=ProjectResponse, status_code=status.HTTP_201_CREATED)
async def create_project(
    project_data: ProjectCreate,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Creates a new project for the authenticated user."""
    new_project = Project(
        owner_id=user_id,
        title=project_data.title,
        description=project_data.description,
        settings=project_data.settings,
    )
    db.add(new_project)
    await db.commit()
    await db.refresh(new_project)
    return new_project

@router.get("/{project_id}", response_model=ProjectResponse)
async def get_project(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Retrieves details of a specific project owned by the user."""
    result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or not authorized to view"
        )
    return project

@router.put("/{project_id}", response_model=ProjectResponse)
async def update_project(
    project_id: str,
    project_data: ProjectUpdate,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Updates fields of a user's project."""
    result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or not authorized to update"
        )
    
    if project_data.title is not None:
        project.title = project_data.title
    if project_data.description is not None:
        project.description = project_data.description
    if project_data.status is not None:
        project.status = project_data.status
    if project_data.settings is not None:
        project.settings = project_data.settings
        
    await db.commit()
    await db.refresh(project)
    return project

@router.delete("/{project_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_project(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Deletes a project owned by the user."""
    result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or not authorized to delete"
        )
    
    await db.delete(project)
    await db.commit()
    return

@router.get("/{project_id}/metrics")
async def get_project_metrics(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Returns aggregated metrics for the project Dashboard.
    
    Includes document counts, concept graph stats, module stats,
    simulation results, and Bloom's taxonomy distribution.
    """
    # Verify ownership
    result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found"
        )
    
    # Document stats
    doc_count_q = await db.execute(
        select(func.count(Document.id)).where(Document.project_id == project_id)
    )
    document_count = doc_count_q.scalar() or 0
    
    doc_completed_q = await db.execute(
        select(func.count(Document.id)).where(
            Document.project_id == project_id,
            Document.processing_status == "completed"
        )
    )
    documents_completed = doc_completed_q.scalar() or 0
    
    total_chunks_q = await db.execute(
        select(func.sum(Document.chunk_count)).where(
            Document.project_id == project_id,
            Document.processing_status == "completed"
        )
    )
    total_chunks = total_chunks_q.scalar() or 0
    
    # Concept graph stats
    concept_count_q = await db.execute(
        select(func.count(Concept.id)).where(Concept.project_id == project_id)
    )
    concept_count = concept_count_q.scalar() or 0
    
    # Bloom distribution from concepts
    bloom_dist_q = await db.execute(
        select(Concept.blooms_level, func.count(Concept.id))
        .where(Concept.project_id == project_id, Concept.blooms_level.isnot(None))
        .group_by(Concept.blooms_level)
    )
    bloom_distribution = {row[0]: row[1] for row in bloom_dist_q.all()}
    
    # Module stats
    module_count_q = await db.execute(
        select(func.count(CurriculumModule.id)).where(CurriculumModule.project_id == project_id)
    )
    module_count = module_count_q.scalar() or 0
    
    # Simulation stats
    sim_count_q = await db.execute(
        select(func.count(SimulationRun.id)).where(SimulationRun.project_id == project_id)
    )
    simulation_count = sim_count_q.scalar() or 0
    
    # Overall pass rate from persona results
    sim_ids_q = await db.execute(
        select(SimulationRun.id).where(SimulationRun.project_id == project_id)
    )
    sim_ids = [row[0] for row in sim_ids_q.all()]
    
    total_answers = 0
    total_passed = 0
    persona_scores = []
    
    if sim_ids:
        total_q = await db.execute(
            select(func.count(PersonaResult.id)).where(PersonaResult.run_id.in_(sim_ids))
        )
        total_answers = total_q.scalar() or 0
        
        passed_q = await db.execute(
            select(func.count(PersonaResult.id)).where(
                PersonaResult.run_id.in_(sim_ids),
                PersonaResult.passed == True
            )
        )
        total_passed = passed_q.scalar() or 0
        
        # Per-persona pass rates (group by persona name from JSON profile)
        persona_q = await db.execute(
            select(PersonaResult.persona_profile, PersonaResult.passed)
            .where(PersonaResult.run_id.in_(sim_ids))
        )
        persona_map = {}
        for row in persona_q.all():
            profile = row[0] if isinstance(row[0], dict) else {}
            name = profile.get("name", "Unknown")
            if name not in persona_map:
                persona_map[name] = {"total": 0, "passed": 0}
            persona_map[name]["total"] += 1
            if row[1]:
                persona_map[name]["passed"] += 1
        
        persona_scores = [
            {
                "name": name,
                "total": data["total"],
                "passed": data["passed"],
                "passRate": round(data["passed"] / max(data["total"], 1) * 100, 1)
            }
            for name, data in persona_map.items()
        ]
    
    overall_pass_rate = round(total_passed / max(total_answers, 1) * 100, 1) if total_answers else 0.0
    
    return {
        "projectId": project_id,
        "projectTitle": project.title,
        "documents": {
            "total": document_count,
            "completed": documents_completed,
            "totalChunks": total_chunks,
        },
        "concepts": {
            "total": concept_count,
            "bloomDistribution": bloom_distribution,
        },
        "modules": {
            "total": module_count,
        },
        "simulations": {
            "total": simulation_count,
            "totalAnswers": total_answers,
            "totalPassed": total_passed,
            "overallPassRate": overall_pass_rate,
            "personaScores": persona_scores,
        },
    }


@router.post("/{project_id}/llm-config/test")
async def test_llm_config(
    project_id: str,
    config: LLMTestConfigRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Test connection to an LLM provider using the given configurations."""
    # Ensure user has access to the project
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized"
        )

    import time
    import httpx
    from app.config import settings
    
    provider = config.provider.lower()
    model = config.model
    url = config.url or ""
    api_key = config.api_key or ""
    
    start_time = time.time()
    
    try:
        if provider == "groq":
            groq_key = api_key or settings.GROQ_API_KEY
            if not groq_key or groq_key == "mock_key":
                return {"status": "error", "message": "Groq API key not configured"}
            from langchain_groq import ChatGroq
            llm = ChatGroq(model=model, groq_api_key=groq_key, temperature=0.0)
            await llm.ainvoke([("user", "ping")], config={"timeout": 5.0})
            
        elif provider == "gemini":
            gemini_key = api_key or settings.GOOGLE_API_KEY
            if not gemini_key or gemini_key == "mock_key":
                return {"status": "error", "message": "Gemini API key not configured"}
            from langchain_google_genai import ChatGoogleGenerativeAI
            llm = ChatGoogleGenerativeAI(model=model, google_api_key=gemini_key, temperature=0.0)
            await llm.ainvoke([("user", "ping")], config={"timeout": 5.0})
            
        elif provider in ("local_ollama", "local_openai"):
            base_url = url or ("http://127.0.0.1:11434/v1" if provider == "local_ollama" else "http://127.0.0.1:1234/v1")
            
            # Normalize trailing slashes and ensure /v1 suffix is present
            base_url = base_url.strip().rstrip("/")
            if provider == "local_openai" and not base_url.endswith("/v1"):
                base_url += "/v1"

            # Define connection testing helper that handles localhost vs 127.0.0.1 fallback
            async def test_connection(target_url: str):
                from urllib.parse import urlparse
                parsed = urlparse(target_url)
                base_check = f"{parsed.scheme}://{parsed.netloc}"
                check_path = "/v1/models" if provider == "local_openai" else "/"
                
                async with httpx.AsyncClient(timeout=2.0) as client:
                    resp = await client.get(f"{base_check}{check_path}")
                    return resp

            # 1. Quick HTTP connection test to the base URL
            try:
                await test_connection(base_url)
            except Exception as conn_err:
                # If localhost failed, try fallback to 127.0.0.1 (or vice versa)
                fallback_url = None
                if "localhost" in base_url:
                    fallback_url = base_url.replace("localhost", "127.0.0.1")
                elif "127.0.0.1" in base_url:
                    fallback_url = base_url.replace("127.0.0.1", "localhost")
                
                if fallback_url:
                    try:
                        await test_connection(fallback_url)
                        base_url = fallback_url  # Use the working fallback URL
                    except Exception:
                        return {
                            "status": "error",
                            "message": f"Could not connect to local server at {base_url} (or fallback {fallback_url}). "
                                       f"Ensure your local model server (Ollama/LM Studio) is running. "
                                       f"Details: {conn_err}"
                        }
                else:
                    return {
                        "status": "error",
                        "message": f"Could not connect to local server at {base_url}. Ensure your local model server is running. Details: {conn_err}"
                    }
            
            # 2. Try LangChain OpenAI completion
            from langchain_openai import ChatOpenAI
            llm = ChatOpenAI(
                model=model,
                base_url=base_url,
                api_key=api_key or "local",
                temperature=0.0,
                max_tokens=5
            )
            import asyncio
            try:
                await asyncio.wait_for(llm.ainvoke([("user", "ping")]), timeout=15.0)
            except asyncio.TimeoutError:
                return {
                    "status": "error",
                    "message": f"Connection succeeded but request timed out (15s limit). Check if the model '{model}' is loaded in Ollama/LM Studio and that your hardware is not overloaded."
                }
            except Exception as e:
                err_msg = str(e)
                if "404" in err_msg or "Model not found" in err_msg or "not loaded" in err_msg:
                    return {
                        "status": "error",
                        "message": f"The server is running, but model '{model}' was not found or is not loaded. "
                                   f"Please open LM Studio and verify that a model with this exact name/identifier is loaded."
                    }
                raise e
        else:
            return {"status": "error", "message": f"Unknown LLM provider: {provider}"}
            
        latency = int((time.time() - start_time) * 1000)
        return {
            "status": "success",
            "message": f"Successfully connected to {provider} ({model})",
            "latency_ms": latency
        }
    except Exception as e:
        return {
            "status": "error",
            "message": f"Connection test failed: {str(e)}"
        }


