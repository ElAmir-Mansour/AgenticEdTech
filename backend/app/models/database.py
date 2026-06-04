import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Float, BigInteger, Boolean, ForeignKey, Text, DateTime, JSON
from sqlalchemy.orm import relationship
from app.database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    email = Column(String(255), unique=True, nullable=False, index=True)
    display_name = Column(String(100), nullable=False)
    apple_id = Column(String(255), unique=True, nullable=True)
    hashed_password = Column(String(255), nullable=True)  # Mock/local login fallback
    avatar_url = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    projects = relationship("Project", back_populates="owner", cascade="all, delete-orphan")

class Project(Base):
    __tablename__ = "projects"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    owner_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    status = Column(String(20), default="draft", nullable=False)  # draft, active, exported, archived
    settings = Column(JSON, default=dict, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    owner = relationship("User", back_populates="projects")
    documents = relationship("Document", back_populates="project", cascade="all, delete-orphan")
    agent_sessions = relationship("AgentSession", back_populates="project", cascade="all, delete-orphan")
    curriculum_modules = relationship("CurriculumModule", back_populates="project", cascade="all, delete-orphan")
    concepts = relationship("Concept", back_populates="project", cascade="all, delete-orphan")
    simulation_runs = relationship("SimulationRun", back_populates="project", cascade="all, delete-orphan")

class Document(Base):
    __tablename__ = "documents"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id = Column(String(36), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    filename = Column(String(500), nullable=False)
    mime_type = Column(String(100), nullable=False)
    file_size_bytes = Column(BigInteger, nullable=False)
    storage_path = Column(Text, nullable=False)
    processing_status = Column(String(20), default="pending", nullable=False)  # pending, processing, completed, failed
    chunk_count = Column(Integer, default=0, nullable=False)
    meta = Column(JSON, default=dict, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    project = relationship("Project", back_populates="documents")

class AgentSession(Base):
    __tablename__ = "agent_sessions"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id = Column(String(36), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    session_type = Column(String(50), nullable=False)  # curriculum_draft, revision, simulation
    status = Column(String(20), default="active", nullable=False)  # active, paused_hitl, completed, failed
    langgraph_thread_id = Column(String(255), nullable=True)
    checkpoint_data = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    completed_at = Column(DateTime, nullable=True)

    project = relationship("Project", back_populates="agent_sessions")
    messages = relationship("AgentMessage", back_populates="session", cascade="all, delete-orphan")

class AgentMessage(Base):
    __tablename__ = "agent_messages"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = Column(String(36), ForeignKey("agent_sessions.id", ondelete="CASCADE"), nullable=False)
    agent_role = Column(String(50), nullable=False)  # planning, content, assessment, critique, supervisor
    message_type = Column(String(30), nullable=False)  # thinking, draft, critique, revision, approval_request
    content = Column(Text, nullable=False)
    meta = Column(JSON, default=dict, nullable=False)
    sequence_num = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    session = relationship("AgentSession", back_populates="messages")

class CurriculumModule(Base):
    __tablename__ = "curriculum_modules"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id = Column(String(36), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    session_id = Column(String(36), ForeignKey("agent_sessions.id", ondelete="SET NULL"), nullable=True)
    title = Column(String(500), nullable=False)
    content = Column(Text, nullable=False)
    blooms_level = Column(String(20), nullable=True)
    sequence_order = Column(Integer, nullable=False)
    heatmap_data = Column(JSON, nullable=True)
    parent_module_id = Column(String(36), ForeignKey("curriculum_modules.id", ondelete="SET NULL"), nullable=True)
    version = Column(Integer, default=1, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    project = relationship("Project", back_populates="curriculum_modules")
    quiz_questions = relationship("QuizQuestion", back_populates="module", cascade="all, delete-orphan")

class QuizQuestion(Base):
    __tablename__ = "quiz_questions"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    module_id = Column(String(36), ForeignKey("curriculum_modules.id", ondelete="CASCADE"), nullable=False)
    question_text = Column(Text, nullable=False)
    question_type = Column(String(20), nullable=False)  # multiple_choice, true_false, short_answer, essay
    options = Column(JSON, nullable=True)
    correct_answer = Column(Text, nullable=False)
    blooms_level = Column(String(20), nullable=True)
    difficulty = Column(Float, nullable=True)
    explanation = Column(Text, nullable=True)
    source_info = Column(Text, nullable=True)
    sequence_order = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


    module = relationship("CurriculumModule", back_populates="quiz_questions")

class Concept(Base):
    __tablename__ = "concepts"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id = Column(String(36), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    blooms_level = Column(String(20), nullable=True)
    source_document_id = Column(String(36), ForeignKey("documents.id", ondelete="SET NULL"), nullable=True)
    source_page = Column(Integer, nullable=True)
    embedding_id = Column(String(255), nullable=True)
    meta = Column(JSON, default=dict, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    project = relationship("Project", back_populates="concepts")

class ConceptPrerequisite(Base):
    __tablename__ = "concept_prerequisites"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    concept_id = Column(String(36), ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False)
    prerequisite_id = Column(String(36), ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False)
    confidence = Column(Float, default=0.8, nullable=False)
    relationship = Column(String(50), default="requires", nullable=False)  # requires, builds_on, enhances
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

class SimulationRun(Base):
    __tablename__ = "simulation_runs"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    project_id = Column(String(36), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    session_id = Column(String(36), ForeignKey("agent_sessions.id", ondelete="SET NULL"), nullable=True)
    status = Column(String(20), default="running", nullable=False)  # running, completed, failed
    persona_count = Column(Integer, nullable=False)
    total_questions = Column(Integer, nullable=False)
    started_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    completed_at = Column(DateTime, nullable=True)
    meta = Column(JSON, default=dict, nullable=True)

    project = relationship("Project", back_populates="simulation_runs")
    persona_results = relationship("PersonaResult", back_populates="run", cascade="all, delete-orphan")

class PersonaResult(Base):
    __tablename__ = "persona_results"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    run_id = Column(String(36), ForeignKey("simulation_runs.id", ondelete="CASCADE"), nullable=False)
    persona_profile = Column(JSON, nullable=False)
    module_id = Column(String(36), ForeignKey("curriculum_modules.id", ondelete="CASCADE"), nullable=False)
    question_id = Column(String(36), ForeignKey("quiz_questions.id", ondelete="SET NULL"), nullable=True)
    passed = Column(Boolean, nullable=False)
    response_text = Column(Text, nullable=True)
    confusion_signal = Column(Text, nullable=True)
    time_estimate_seconds = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    run = relationship("SimulationRun", back_populates="persona_results")
