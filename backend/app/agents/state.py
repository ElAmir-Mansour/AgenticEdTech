from typing import TypedDict, List, Annotated, Dict, Any
from operator import add

class AgentState(TypedDict):
    """Shared state schema for curriculum agent debate."""
    project_id: str
    session_id: str
    user_id: str
    topic: str
    instruction: str
    context_chunks: List[str]
    outline: str
    draft_content: str
    previous_outline: str
    previous_draft_content: str
    critique_notes: List[str]
    revision_count: int
    quiz_questions: List[Dict[str, Any]]
    heatmap_data: Dict[str, Any]
    messages: Annotated[List[Dict[str, Any]], add]
    current_agent: str
    hitl_status: str  # "pending", "approved", "rejected"
    generation_mode: str  # "full" or "quiz"
    pedagogical_framework: str


