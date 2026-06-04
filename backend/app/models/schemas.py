from pydantic import BaseModel, EmailStr, Field
from typing import Optional, Any, Literal
from datetime import datetime


# Token Schemas
class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    user_id: Optional[str] = None
    email: Optional[str] = None

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

# User Schemas
class UserBase(BaseModel):
    email: EmailStr
    display_name: str
    avatar_url: Optional[str] = None

class UserCreate(UserBase):
    password: str

class UserResponse(UserBase):
    id: str
    apple_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

# Project Schemas
class ProjectBase(BaseModel):
    title: str
    description: Optional[str] = None
    settings: Optional[dict[str, Any]] = Field(default_factory=dict)

class ProjectCreate(ProjectBase):
    pass

class ProjectUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    settings: Optional[dict[str, Any]] = None

class ProjectResponse(ProjectBase):
    id: str
    owner_id: str
    status: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

# Document Schemas
class DocumentResponse(BaseModel):
    id: str
    project_id: str
    filename: str
    mime_type: str
    file_size_bytes: int
    processing_status: str
    chunk_count: int
    meta: dict = {}
    created_at: datetime

    class Config:
        from_attributes = True

# Concept Graph Schemas
class ConceptResponse(BaseModel):
    id: str
    project_id: str
    name: str
    description: Optional[str] = None
    blooms_level: Optional[str] = None
    source_document_id: Optional[str] = None
    source_page: Optional[int] = None
    created_at: datetime

    class Config:
        from_attributes = True

class ConceptPrerequisiteResponse(BaseModel):
    concept_id: str
    prerequisite_id: str
    confidence: float
    relationship: str

    class Config:
        from_attributes = True

class ConceptGraphResponse(BaseModel):
    concepts: list[ConceptResponse]
    prerequisites: list[ConceptPrerequisiteResponse]

# Quiz Question and Curriculum Module responses
class QuizQuestionResponse(BaseModel):
    id: str
    module_id: str
    question_text: str
    question_type: str
    options: Optional[list[str]] = None
    correct_answer: str
    blooms_level: Optional[str] = None
    difficulty: Optional[float] = None
    explanation: Optional[str] = None
    source_info: Optional[str] = None
    sequence_order: int
    created_at: datetime


    class Config:
        from_attributes = True

class CurriculumModuleResponse(BaseModel):
    id: str
    project_id: str
    session_id: Optional[str] = None
    title: str
    content: str
    blooms_level: Optional[str] = None
    sequence_order: int
    heatmap_data: Optional[dict[str, Any]] = None
    parent_module_id: Optional[str] = None
    version: int
    created_at: datetime
    updated_at: datetime
    quiz_questions: list[QuizQuestionResponse] = []

    class Config:
        from_attributes = True

class CurriculumModuleUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    blooms_level: Optional[str] = None

class CurriculumModuleReorder(BaseModel):
    module_ids: list[str]

class CurriculumModuleRefineRequest(BaseModel):
    prompt: str



# Persona Schemas
class PersonaProfile(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    experience: Literal["Beginner", "Intermediate", "Expert"]
    background: str = Field(..., min_length=1, max_length=255)
    attention_span: Literal["Low", "Medium", "High"]
    error_rate: float = Field(..., ge=0.0, le=1.0, description="Probability of answering incorrectly (0.0-1.0)")

class RunSimulationRequest(BaseModel):
    module_id: Optional[str] = None
    personas: Optional[list[PersonaProfile]] = None
    cohort_size: Optional[int] = 3
    hourly_wage: Optional[float] = 45.0

class SimulationRunResponse(BaseModel):
    id: str
    project_id: str
    session_id: Optional[str] = None
    status: str
    persona_count: int
    total_questions: int
    started_at: datetime
    completed_at: Optional[datetime] = None
    meta: Optional[dict[str, Any]] = None

    class Config:
        from_attributes = True


class PersonaResultResponse(BaseModel):
    id: str
    run_id: str
    persona_profile: dict[str, Any]
    module_id: str
    question_id: Optional[str] = None
    passed: bool
    response_text: Optional[str] = None
    confusion_signal: Optional[str] = None
    time_estimate_seconds: Optional[float] = None
    created_at: datetime

    class Config:
        from_attributes = True


class SimulationRunDetailResponse(BaseModel):
    id: str
    project_id: str
    session_id: Optional[str] = None
    status: str
    persona_count: int
    total_questions: int
    started_at: datetime
    completed_at: Optional[datetime] = None
    meta: Optional[dict[str, Any]] = None
    persona_results: list[PersonaResultResponse] = []

    class Config:
        from_attributes = True


class LLMTestConfigRequest(BaseModel):
    provider: str
    url: Optional[str] = None
    model: str
    api_key: Optional[str] = None


