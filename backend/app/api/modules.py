from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models.database import Project, CurriculumModule
from app.models.schemas import CurriculumModuleResponse, CurriculumModuleUpdate, CurriculumModuleReorder, CurriculumModuleRefineRequest
from app.auth.dependencies import get_current_user_id

router = APIRouter()

@router.get("/{project_id}/modules", response_model=list[CurriculumModuleResponse])
async def list_modules(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Retrieves all generated curriculum modules for a specific project, including quizzes."""
    # 1. Verify project exists and belongs to the user
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )

    # 2. Fetch modules with selectinload for quiz questions
    modules_result = await db.execute(
        select(CurriculumModule)
        .where(CurriculumModule.project_id == project_id)
        .options(selectinload(CurriculumModule.quiz_questions))
        .order_by(CurriculumModule.sequence_order.asc())
    )
    modules = modules_result.scalars().all()
    return modules


@router.put("/{project_id}/modules/{module_id}", response_model=CurriculumModuleResponse)
async def update_module(
    project_id: str,
    module_id: str,
    module_data: CurriculumModuleUpdate,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Updates a specific curriculum module's metadata."""
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )
    
    module_result = await db.execute(
        select(CurriculumModule)
        .where(CurriculumModule.id == module_id, CurriculumModule.project_id == project_id)
        .options(selectinload(CurriculumModule.quiz_questions))
    )
    module = module_result.scalars().first()
    if not module:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Curriculum module not found"
        )
        
    if module_data.title is not None:
        module.title = module_data.title
    if module_data.content is not None:
        module.content = module_data.content
    if module_data.blooms_level is not None:
        module.blooms_level = module_data.blooms_level
        
    await db.commit()
    await db.refresh(module)
    return module


@router.delete("/{project_id}/modules/{module_id}", status_code=status.HTTP_200_OK)
async def delete_module(
    project_id: str,
    module_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Deletes a specific curriculum module and adjusts sequence order for others."""
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )
        
    module_result = await db.execute(
        select(CurriculumModule)
        .where(CurriculumModule.id == module_id, CurriculumModule.project_id == project_id)
    )
    module = module_result.scalars().first()
    if not module:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Curriculum module not found"
        )
        
    deleted_seq = module.sequence_order
    
    await db.delete(module)
    await db.commit()
    
    subsequent_result = await db.execute(
        select(CurriculumModule)
        .where(CurriculumModule.project_id == project_id, CurriculumModule.sequence_order > deleted_seq)
        .order_by(CurriculumModule.sequence_order.asc())
    )
    subsequent = subsequent_result.scalars().all()
    for m in subsequent:
        m.sequence_order -= 1
        
    await db.commit()
    return {"status": "success"}


@router.post("/{project_id}/modules/reorder", status_code=status.HTTP_200_OK)
async def reorder_modules(
    project_id: str,
    reorder_data: CurriculumModuleReorder,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Updates sequence order of modules in the project."""
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )
        
    for index, m_id in enumerate(reorder_data.module_ids):
        module_result = await db.execute(
            select(CurriculumModule)
            .where(CurriculumModule.id == m_id, CurriculumModule.project_id == project_id)
        )
        module = module_result.scalars().first()
        if module:
            module.sequence_order = index + 1
            
    await db.commit()
    return {"status": "success"}


@router.post("/{project_id}/modules/{module_id}/refine", response_model=CurriculumModuleResponse)
async def refine_module(
    project_id: str,
    module_id: str,
    refine_data: CurriculumModuleRefineRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Refines a curriculum module (content and quiz questions) using LLM based on user feedback/prompt."""
    import logging
    import json
    import re
    from sqlalchemy.orm import selectinload
    
    logger = logging.getLogger(__name__)

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
        
    # 2. Fetch module with quizzes
    module_result = await db.execute(
        select(CurriculumModule)
        .where(CurriculumModule.id == module_id, CurriculumModule.project_id == project_id)
        .options(selectinload(CurriculumModule.quiz_questions))
    )
    module = module_result.scalars().first()
    if not module:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Curriculum module not found"
        )

    # 3. Call LLM for refinement
    from app.agents.graph import get_llm
    from langchain_core.prompts import ChatPromptTemplate
    
    llm = await get_llm(project_id, db=db)
    if not llm:
        # Use a simple mock fallback if Groq API key is not configured or mock_key
        # This keeps the application functional during mock-key local executions
        mock_content = f"{module.content}\n\n*Updated with prompt: {refine_data.prompt}*"
        module.content = mock_content
        module.title = f"{module.title} (Refined)"
        module.version += 1
        await db.commit()
        return module
        
    # Format existing quiz questions for the prompt
    quiz_data = []
    for q in module.quiz_questions:
        quiz_data.append({
            "question_text": q.question_text,
            "options": q.options,
            "correct_answer": q.correct_answer,
            "explanation": q.explanation,
            "blooms_level": q.blooms_level
        })
        
    system_prompt = (
        "You are an expert Instructional Designer. Refine the given curriculum module's title, content, "
        "and quiz questions based on the user's instructions. "
        "You must return a valid JSON object ONLY. Do not include markdown code block formatting like ```json, "
        "do not include introductory text, and do not include trailing text. Just the JSON object itself.\n\n"
        "Your JSON response must match this schema exactly:\n"
        "{{\n"
        '  "title": "Refined title",\n'
        '  "content": "Refined lesson content text...",\n'
        '  "quiz_questions": [\n'
        "    {{\n"
        '      "question_text": "Question content?",\n'
        '      "options": ["Option A", "Option B", "Option C", "Option D"],\n'
        '      "correct_answer": "Option A (must exactly match one option)",\n'
        '      "explanation": "Explanation text...",\n'
        '      "blooms_level": "bloom level (e.g. remember, understand, apply, analyze, evaluate, create)"\n'
        "    }}\n"
        "  ]\n"
        "}}\n\n"
        "Ensure the quiz questions are pedagogy-aligned with the target cognitive depth of the content."
    )
    
    user_content = (
        f"--- CURRENT MODULE ---\n"
        f"Title: {module.title}\n"
        f"Bloom's Level: {module.blooms_level}\n"
        f"Content:\n{module.content}\n\n"
        f"Quiz Questions:\n{json.dumps(quiz_data, indent=2)}\n\n"
        f"--- USER REFINEMENT REQUEST ---\n"
        f"Prompt: {refine_data.prompt}"
    )
    
    try:
        prompt_tmpl = ChatPromptTemplate.from_messages([
            ("system", system_prompt),
            ("user", "{user_content}")
        ])
        chain = prompt_tmpl | llm
        response = await chain.ainvoke({"user_content": user_content})
        
        # Parse JSON from response content
        resp_text = response.content.strip()
        
        # If wrapped in markdown blocks, extract content
        if resp_text.startswith("```"):
            resp_text = re.sub(r"^```[a-zA-Z0-9]*\n", "", resp_text)
            resp_text = re.sub(r"\n```$", "", resp_text)
            resp_text = resp_text.strip()
            
        parsed = json.loads(resp_text)
        
        # 4. Update the DB values
        module.title = parsed.get("title", module.title)
        module.content = parsed.get("content", module.content)
        module.version += 1
        
        # Recalculate Bloom's level based on updated content keywords if title/content changed
        from app.ws.handler import _extract_blooms_level
        module.blooms_level = _extract_blooms_level(module.content, module.title)
        
        # Delete old quiz questions
        from app.models.database import QuizQuestion
        for q in list(module.quiz_questions):
            await db.delete(q)
        await db.commit()
        
        # Insert new quiz questions
        new_quizzes = parsed.get("quiz_questions", [])
        for idx, q_data in enumerate(new_quizzes):
            new_q = QuizQuestion(
                module_id=module.id,
                question_text=q_data.get("question_text", ""),
                question_type="multiple_choice",
                options=q_data.get("options", []),
                correct_answer=q_data.get("correct_answer", ""),
                blooms_level=q_data.get("blooms_level", module.blooms_level),
                difficulty=0.5,
                explanation=q_data.get("explanation", ""),
                sequence_order=idx + 1
            )
            db.add(new_q)
            
        await db.commit()
        
        # Reload updated module to return it
        reload_q = await db.execute(
            select(CurriculumModule)
            .where(CurriculumModule.id == module_id)
            .options(selectinload(CurriculumModule.quiz_questions))
        )
        module = reload_q.scalars().first()
        return module
        
    except Exception as e:
        logger.error(f"Refinement processing failed: {e}", exc_info=True)
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Refinement failed: {str(e)}"
        )

