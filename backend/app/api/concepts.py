from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.database import get_db
from app.models.database import Concept, ConceptPrerequisite, Project
from app.models.schemas import ConceptGraphResponse, ConceptResponse, ConceptPrerequisiteResponse
from app.auth.dependencies import get_current_user_id

router = APIRouter()

@router.get("/{project_id}/concepts", response_model=ConceptGraphResponse)
async def get_concept_graph(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Retrieves all concepts and prerequisite relationships forming the project knowledge graph."""
    # 1. Verify project ownership
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    if not proj_result.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )
        
    # 2. Query all concepts in this project
    concepts_result = await db.execute(
        select(Concept).where(Concept.project_id == project_id)
    )
    concepts = concepts_result.scalars().all()
    concept_ids = [c.id for c in concepts]
    
    # 3. Query all prerequisite links that relate to these concepts
    prereqs = []
    if concept_ids:
        prereq_result = await db.execute(
            select(ConceptPrerequisite).where(ConceptPrerequisite.concept_id.in_(concept_ids))
        )
        prereqs = prereq_result.scalars().all()
        
    return ConceptGraphResponse(
        concepts=concepts,
        prerequisites=prereqs
    )
