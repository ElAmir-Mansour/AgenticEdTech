import json
import logging
import asyncio
from uuid import UUID
from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.ws.manager import ws_manager
from app.auth.jwt_handler import verify_access_token
from app.database import async_session_maker
from app.models.database import AgentSession, AgentMessage, Project, CurriculumModule, QuizQuestion
from app.agents.graph import build_curriculum_graph

logger = logging.getLogger(__name__)

# Cache active LangGraph compiling saver instances
checkpointer = None

def get_checkpointer():
    global checkpointer
    if checkpointer is None:
        from langgraph.checkpoint.memory import MemorySaver
        checkpointer = MemorySaver()
    return checkpointer


async def websocket_endpoint(websocket: WebSocket):
    """Handles WebSocket upgrading, authentication, and routing message packets."""
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4001, reason="Missing authentication token")
        return
        
    payload = verify_access_token(token)
    if not payload:
        await websocket.close(code=4002, reason="Invalid authentication token")
        return
        
    user_id_str = payload.get("user_id")
    if not user_id_str:
        await websocket.close(code=4003, reason="Token payload missing user ID")
        return
        
    user_id = UUID(user_id_str)
    await ws_manager.connect(user_id, websocket)
    logger.info(f"WebSocket client connected: user_id={user_id}")
    
    try:
        # Send connection established message
        await websocket.send_json({
            "type": "connection_established",
            "workspace": "dashboard",
            "payload": {"message": "Successfully connected to WebSocket server"},
        })
        
        while True:
            data = await websocket.receive_text()
            try:
                message = json.loads(data)
                msg_type = message.get("type")
                workspace = message.get("workspace", "dashboard")
                payload_data = message.get("payload", {})
                
                logger.info(f"WebSocket message received: type={msg_type} from user_id={user_id}")
                
                if msg_type == "ping":
                    await websocket.send_json({
                        "type": "pong",
                        "workspace": workspace,
                        "payload": {"message": "pong"},
                    })
                    
                elif msg_type == "start_agent_debate":
                    # Start async debate sequence
                    topic = payload_data.get("topic", "")
                    project_id = payload_data.get("project_id", "")
                    session_id = payload_data.get("session_id")
                    document_ids = payload_data.get("document_ids")
                    pedagogical_framework = payload_data.get("pedagogical_framework", "traditional")
                    if topic and project_id:
                        asyncio.create_task(run_debate_graph(user_id, project_id, topic, session_id, document_ids, pedagogical_framework))
                    else:
                        await websocket.send_json({
                            "type": "error",
                            "workspace": "canvas",
                            "payload": {"message": "Missing topic or project_id"}
                        })
                        
                elif msg_type == "submit_hitl_approval":
                    # Resume from outline checkpoint
                    session_id = payload_data.get("session_id", "")
                    approved = payload_data.get("approved", True)
                    feedback = payload_data.get("feedback", "")
                    edited_outline = payload_data.get("edited_outline", "")
                    
                    if session_id:
                        asyncio.create_task(resume_debate_graph(user_id, session_id, approved, feedback, edited_outline))
                    else:
                        await websocket.send_json({
                            "type": "error",
                            "workspace": "canvas",
                            "payload": {"message": "Missing session_id"}
                        })
                elif msg_type == "request_socratic_hint":
                    project_id = payload_data.get("project_id", "")
                    question_id = payload_data.get("question_id", "")
                    question_text = payload_data.get("question_text", "")
                    options = payload_data.get("options", [])
                    selected_option = payload_data.get("selected_option", "")
                    
                    if project_id and question_id and question_text:
                        asyncio.create_task(run_socratic_hint(websocket, user_id, project_id, question_id, question_text, options, selected_option, workspace))
                    else:
                        await websocket.send_json({
                            "type": "error",
                            "workspace": workspace,
                            "payload": {"message": "Missing project_id, question_id, or question_text"}
                        })
                else:
                    # Echo fallback
                    await websocket.send_json({
                        "type": f"echo_{msg_type}",
                        "workspace": workspace,
                        "payload": payload_data,
                    })
            except json.JSONDecodeError:
                await websocket.send_json({
                    "type": "error",
                    "workspace": "dashboard",
                    "payload": {"message": "Invalid JSON format"},
                })
    except WebSocketDisconnect:
        ws_manager.disconnect(user_id)
        logger.info(f"WebSocket client disconnected: user_id={user_id}")
    except Exception as e:
        logger.error(f"WebSocket error: {str(e)}", exc_info=True)
        ws_manager.disconnect(user_id)


# --- BACKGROUND DEBATE EXECUTION ---

async def run_debate_graph(user_id: UUID, project_id: str, topic: str, previous_session_id: str = None, document_ids: list = None, pedagogical_framework: str = "traditional"):
    """Spins up a new LangGraph thread execution loop in the background."""
    logger.info(f"Launching debate background loop: user_id={user_id}, topic={topic}, previous_session_id={previous_session_id}, document_ids={document_ids}, pedagogical_framework={pedagogical_framework}")
    
    async with async_session_maker() as db:
        # Fetch project details to get actual topic title/description
        project_q = await db.execute(select(Project).where(Project.id == project_id))
        project = project_q.scalars().first()
        project_title = project.title if project else "Learning Module"
        project_desc = project.description if project else ""

        # Create session in DB
        session = AgentSession(
            project_id=project_id,
            session_type="curriculum_draft",
            status="active"
        )
        db.add(session)
        await db.commit()
        await db.refresh(session)
        session_id = session.id
        
    # Tell user about session creation
    await ws_manager.send_to_user(user_id, {
        "type": "agent_session_created",
        "workspace": "canvas",
        "payload": {
            "sessionId": session_id,
            "topic": topic
        }
    })
    
    # Configure LangGraph
    graph = build_curriculum_graph(get_checkpointer())
    config = {"configurable": {"thread_id": session_id}}
    
    # Retrieve previous values from checkpointer if provided
    previous_outline = ""
    previous_draft = ""
    resolved_topic = topic
    
    if previous_session_id:
        try:
            prev_config = {"configurable": {"thread_id": previous_session_id}}
            prev_state = graph.get_state(prev_config)
            if prev_state and prev_state.values:
                previous_outline = prev_state.values.get("outline", "")
                previous_draft = prev_state.values.get("draft_content", "")
                # Inherit original topic if the user prompt is a generic chip
                orig_topic = prev_state.values.get("topic", "")
                is_refinement_instruction = topic.lower() in [
                    "make it simpler",
                    "increase difficulty",
                    "add practical examples",
                    "add more quiz questions",
                    "regenerate"
                ]
                if is_refinement_instruction and orig_topic:
                    resolved_topic = orig_topic
        except Exception as e:
            logger.warning(f"Failed to retrieve previous state for session {previous_session_id}: {e}")

    # Resolve topic name if first run prompt is a generic action chip/phrase
    p_clean = topic.lower().strip().rstrip(".!?")
    
    # Check for prefix style quiz requests
    prefixes = [
        "make a quiz on ", "create a quiz on ", "generate a quiz on ", "generate quiz on ",
        "make a quiz about ", "create a quiz about ", "generate a quiz about ", "generate quiz about ",
        "quiz me on ", "test me on ", "quiz on "
    ]
    
    generation_mode = "full"
    resolved_topic = topic
    
    quiz_indicators = {
        "quick quiz on a topic", "make a quiz", "create a quiz", "generate quiz", "quiz", "quiz me", "test me", "generate a quiz", "make quiz"
    }
    is_quiz_intent = (
        p_clean in quiz_indicators or
        any(p_clean.startswith(prefix) for prefix in prefixes) or
        "quiz" in p_clean or
        "test me" in p_clean
    )
    if is_quiz_intent:
        generation_mode = "quiz"
        for prefix in prefixes:
            if p_clean.startswith(prefix):
                resolved_topic = topic[len(prefix):].strip().title()
                break
                
    action_prompts = {
        "create a curriculum outline",
        "generate from uploaded docs",
        "quick quiz on a topic",
        "create an outline",
        "make a quiz",
        "create a quiz",
        "generate quiz",
        "quiz",
        "quiz me",
        "test me",
        "generate a quiz",
        "make quiz",
        "create outline",
        "generate outline",
        "curriculum",
        "generate curriculum"
    }
    is_generic_action = p_clean in action_prompts
    if is_generic_action or not resolved_topic:
        resolved_topic = project_title
        
    # If the resolved topic is a generic project title, enrich it using uploaded documents
    generic_names = {"test", "default", "my project", "learning module", "new project", "untitled project", "learningblock"}
    if resolved_topic.lower().strip() in generic_names:
        async with async_session_maker() as db_session:
            from app.models.database import Document
            doc_q = await db_session.execute(
                select(Document).where(Document.project_id == project_id).limit(1)
            )
            doc = doc_q.scalars().first()
            if doc and doc.filename:
                import os
                base_name = os.path.splitext(doc.filename)[0]
                resolved_topic = base_name.replace("_", " ").replace("-", " ").title()

    # Retrieve RAG context chunks from Qdrant if available, using the resolved topic and document filter
    context_chunks = await _fetch_rag_chunks(project_id, resolved_topic, document_ids)

    # Prepare inputs
    inputs = {
        "project_id": project_id,
        "session_id": session_id,
        "user_id": str(user_id),
        "topic": resolved_topic,
        "instruction": topic, # The user's input/chip action
        "context_chunks": context_chunks,
        "outline": "",
        "draft_content": "",
        "previous_outline": previous_outline,
        "previous_draft_content": previous_draft,
        "critique_notes": [],
        "revision_count": 0,
        "quiz_questions": [],
        "heatmap_data": {},
        "messages": [],
        "current_agent": "",
        "hitl_status": "pending",
        "generation_mode": generation_mode,
        "pedagogical_framework": pedagogical_framework
    }
    
    try:
        # Run graph — it will halt BEFORE hitl_outline (interrupt_before)
        last_state = None
        async for event in graph.astream(inputs, config, stream_mode="values"):
            last_state = event
            
        # Graph paused at HITL checkpoint. The hitl_outline node has NOT run yet.
        # We must manually send the approval request to the client.
        logger.info(f"Debate graph suspended at outline checkpoint: session_id={session_id}")
        
        outline = ""
        if last_state:
            outline = last_state.get("outline", "")
        
        # Send the approval request that the hitl_checkpoint_node would have sent
        await ws_manager.send_to_user(user_id, {
            "type": "agent_stream",
            "workspace": "canvas",
            "payload": {
                "agent": "Planning Agent",
                "messageType": "approval_request",
                "content": outline
            }
        })
        logger.info(f"Sent approval_request to user for session_id={session_id}")
        
    except Exception as e:
        logger.error(f"Error executing LangGraph: {e}", exc_info=True)
        await ws_manager.send_to_user(user_id, {
            "type": "error",
            "workspace": "canvas",
            "payload": {"message": f"Graph execution error: {str(e)}"}
        })


async def resume_debate_graph(user_id: UUID, session_id: str, approved: bool, feedback: str, edited_outline: str = ""):
    """Resumes the suspended LangGraph execution after receiving user approval."""
    logger.info(f"Resuming debate thread: session_id={session_id}, approved={approved}, edited_outline={bool(edited_outline)}")
    
    graph = build_curriculum_graph(get_checkpointer())
    config = {"configurable": {"thread_id": session_id}}
    
    try:
        # Get current state
        state = graph.get_state(config)
        current_values = state.values
        
        if not current_values:
            raise ValueError("No active running session thread found matching ID.")
            
        if approved:
            # Update state to approve outline and resume from hitl_outline node
            state_updates = {"hitl_status": "approved"}
            if edited_outline:
                state_updates["outline"] = edited_outline
            graph.update_state(config, state_updates, as_node="hitl_outline")
            
            # Resume stream — this runs content → critique → revision → assessment → heatmap → END
            async for event in graph.astream(None, config, stream_mode="values"):
                current_values = event # Track final completed state
                
            # Compile citations to clickable markdown links before saving and broadcasting
            draft = current_values.get("draft_content", "")
            current_values["draft_content"] = compile_citation_links(draft)
            
            # Completed! Save course curriculum module to SQLite
            await save_completed_curriculum(session_id, current_values)
            
            # Broadcast final completion
            await ws_manager.send_to_user(user_id, {
                "type": "agent_complete",
                "workspace": "canvas",
                "payload": {
                    "sessionId": session_id,
                    "title": current_values.get("topic", "Generated Module"),
                    "content": current_values.get("draft_content", ""),
                    "quizQuestions": current_values.get("quiz_questions", []),
                    "heatmapData": current_values.get("heatmap_data", {})
                }
            })
            logger.info(f"Resumed debate successfully completed and saved: session_id={session_id}")
        else:
            # Loop planning agent back with user feedback adjustments
            logger.info("Outline rejected by user. Looping back...")
            graph.update_state(
                config, 
                {"hitl_status": "rejected", "topic": f"{current_values.get('topic')} (Revision: {feedback})"}, 
                as_node="hitl_outline"
            )
            
            # Run again until next outline checkpoint
            last_state = None
            async for event in graph.astream(None, config, stream_mode="values"):
                last_state = event
            
            # Again send approval_request after the graph pauses
            outline = last_state.get("outline", "") if last_state else ""
            await ws_manager.send_to_user(user_id, {
                "type": "agent_stream",
                "workspace": "canvas",
                "payload": {
                    "agent": "Planning Agent",
                    "messageType": "approval_request",
                    "content": outline
                }
            })
                
    except Exception as e:
        logger.error(f"Error resuming LangGraph thread: {e}", exc_info=True)
        await ws_manager.send_to_user(user_id, {
            "type": "error",
            "workspace": "canvas",
            "payload": {"message": f"Graph resume error: {str(e)}"}
        })


def compile_citation_links(text: str) -> str:
    """Regex-replaces standard flat citations with custom tappable citation:// scheme links."""
    if not text:
        return text
    import re
    import urllib.parse
    
    # Matches [Source: filename, Page: X] or [Source: filename, Page X]
    pattern = r"\[[Ss]ource:\s*(.*?),\s*[Pp]age\s*:?\s*(\d+)\]"
    
    def replacer(match):
        filename = match.group(1).strip()
        page = match.group(2).strip()
        encoded_filename = urllib.parse.quote(filename)
        return f"[🔍 Source: {filename} (p. {page})](citation://{encoded_filename}/{page})"
        
    return re.sub(pattern, replacer, text)


async def save_completed_curriculum(session_id: str, state_values: dict):
    """Saves completed curriculum details to core database modules tables."""
    async with async_session_maker() as db:
        try:
            # Update session status
            session_q = await db.execute(select(AgentSession).where(AgentSession.id == session_id))
            session = session_q.scalars().first()
            if session:
                session.status = "completed"
            
            project_id = state_values.get("project_id")
            
            # Auto-increment sequence_order
            from sqlalchemy import func
            count_q = await db.execute(
                select(func.count(CurriculumModule.id)).where(CurriculumModule.project_id == project_id)
            )
            existing_count = count_q.scalar() or 0
            next_order = existing_count + 1
            
            generation_mode = state_values.get("generation_mode", "full")
            draft_content = state_values.get("draft_content", "")
            module_title = state_values.get("topic", "New Learning Block")
            
            if generation_mode == "quiz":
                draft_content = f"**Quiz Module**: {module_title}\n\n*This block contains a standalone knowledge check assessment designed to test understanding of the material.*"
                if "quiz" not in module_title.lower() and "test" not in module_title.lower():
                    module_title += " (Quiz)"
                    
            # Extract Bloom's level from content/outline
            blooms_level = _extract_blooms_level(
                draft_content,
                state_values.get("outline", "")
            )
                
            # Create CurriculumModule record
            new_module = CurriculumModule(
                project_id=project_id,
                session_id=session_id,
                title=module_title,
                content=draft_content,
                blooms_level=blooms_level,
                sequence_order=next_order,
                heatmap_data=state_values.get("heatmap_data", {})
            )
            db.add(new_module)
            await db.commit()  # Save to generate new_module.id
            await db.refresh(new_module)
            
            # Save Quiz questions
            quizzes = state_values.get("quiz_questions", [])
            for idx, q in enumerate(quizzes):
                new_quiz = QuizQuestion(
                    module_id=new_module.id,
                    question_text=q.get("question_text", ""),
                    question_type="multiple_choice",
                    options=q.get("options", []),
                    correct_answer=q.get("correct_answer", ""),
                    blooms_level=q.get("blooms_level", "understand"),
                    difficulty=q.get("difficulty", 0.5),
                    explanation=q.get("explanation", ""),
                    source_info=q.get("source_info", ""),
                    sequence_order=idx + 1
                )
                db.add(new_quiz)
                
            await db.commit()
            logger.info(f"Saved curriculum module #{next_order} for session {session_id}: {new_module.title} (Bloom's: {blooms_level})")
        except Exception as e:
            logger.error(f"Failed to save curriculum: {e}", exc_info=True)
            await db.rollback()


def _extract_blooms_level(content: str, outline: str) -> str:
    """Extracts the most prominent Bloom's taxonomy level from content by keyword analysis."""
    text = (content + " " + outline).lower()
    
    # Score each level by keyword frequency (higher levels score higher)
    blooms_keywords = {
        "create": ["create", "design", "construct", "develop", "formulate", "compose", "produce", "invent"],
        "evaluate": ["evaluate", "judge", "assess", "critique", "justify", "defend", "argue", "recommend"],
        "analyze": ["analyze", "compare", "contrast", "examine", "differentiate", "distinguish", "investigate"],
        "apply": ["apply", "implement", "execute", "solve", "demonstrate", "use", "practice", "calculate"],
        "understand": ["understand", "explain", "describe", "summarize", "interpret", "classify", "discuss"],
        "remember": ["remember", "recall", "list", "define", "identify", "recognize", "name", "state"]
    }
    
    scores = {}
    for level, keywords in blooms_keywords.items():
        scores[level] = sum(text.count(kw) for kw in keywords)
    
    # Return highest scoring level, defaulting to "understand"
    best = max(scores, key=scores.get, default="understand")
    return best if scores.get(best, 0) > 0 else "understand"


async def _fetch_rag_chunks(project_id: str, topic: str, document_ids: list = None) -> list:
    """Fetches RAG context chunks from Qdrant for grounding the curriculum."""
    context_chunks = []
    try:
        from app.utils.qdrant_client import get_qdrant_client
        qdrant = get_qdrant_client()
        collections = qdrant.get_collections().collections
        if any(c.name == "document_chunks" for c in collections):
            encoder = _get_encoder()
            if encoder is None:
                return []
            query_vector = encoder.encode(topic).tolist()
            
            from qdrant_client.models import Filter, FieldCondition, MatchValue
            
            # Build filters
            must_filters = [FieldCondition(key="project_id", match=MatchValue(value=project_id))]
            if document_ids:
                from qdrant_client.models import MatchAny
                must_filters.append(FieldCondition(key="document_id", match=MatchAny(any=document_ids)))
                
            search_filter = Filter(must=must_filters)
            
            # Use query_points for newer Qdrant client versions, fallback to search
            try:
                results = qdrant.query_points(
                    collection_name="document_chunks",
                    query=query_vector,
                    query_filter=search_filter,
                    limit=8
                ).points
            except (AttributeError, TypeError):
                try:
                    results = qdrant.search(
                        collection_name="document_chunks",
                        query_vector=query_vector,
                        query_filter=search_filter,
                        limit=8
                    )
                except Exception:
                    results = []
            
            context_chunks = []
            for r in results:
                payload = r.payload or {}
                if "content" in payload:
                    context_chunks.append({
                        "content": payload["content"],
                        "filename": payload.get("filename", "Unknown"),
                        "page_number": payload.get("page_number", 1)
                    })
            logger.info(f"Retrieved {len(context_chunks)} RAG chunks for topic: {topic}")
    except Exception as e:
        logger.warning(f"Failed to query Qdrant grounding chunks: {e}")
    
    return context_chunks


_encoder_instance = None

def _get_encoder():
    """Returns cached SentenceTransformer encoder."""
    global _encoder_instance
    if _encoder_instance is not None:
        return _encoder_instance
    try:
        from sentence_transformers import SentenceTransformer
        _encoder_instance = SentenceTransformer("all-MiniLM-L6-v2")
        return _encoder_instance
    except Exception:
        return None


async def run_socratic_hint(websocket: WebSocket, user_id: UUID, project_id: str, question_id: str, question_text: str, options: list, selected_option: str = "", workspace: str = "lms"):
    """Fetches context, queries the LLM under a Socratic persona, and responds with a hint."""
    logger.info(f"Generating Socratic Hint for question_id={question_id} (user_id={user_id})")
    
    # 1. Fetch RAG chunks
    context_chunks = await _fetch_rag_chunks(project_id, question_text)
    context_str = ""
    if context_chunks:
        context_str = "\n\n".join([
            f"Reference [Source: {c.get('filename', 'Unknown')}, Page: {c.get('page_number', 1)}]:\n{c['content']}"
            for c in context_chunks
        ])
    else:
        context_str = "No specific reference documents found. Use general pedagogical knowledge on the topic."

    # 2. Build Socratic prompt instructions
    system_prompt = (
        "You are an expert Socratic Tutor. Your job is to help a student answer a multiple-choice question "
        "by guiding them with hints and conceptual questions. You must NOT directly reveal the correct answer "
        "or mention the correct option letter/text.\n\n"
        f"Question to Solve:\n\"{question_text}\"\n\n"
        f"Available Options:\n" + "\n".join([f"- {opt}" for opt in options]) + "\n\n"
        f"Student's Incorrect Attempt/Help Request:\n" + (f"The student chose the wrong answer: \"{selected_option}\"." if selected_option else "The student is stuck and requested a hint.") + "\n\n"
        f"Pedagogical Reference Material:\n{context_str}\n\n"
        "Guidelines:\n"
        "1. Write a short, highly-supportive hint (max 2-3 sentences) addressed directly to the student.\n"
        "2. Do NOT tell them the correct option or choice (e.g., do not say 'choose option B' or 'the answer is...').\n"
        "3. Focus on the core concept from the reference material and ask them a guiding question that helps them self-correct."
    )
    
    hint = "Failed to generate hint. Please try again."
    try:
        from app.database import async_session_maker
        async with async_session_maker() as db:
            from app.agents.graph import get_llm
            llm = await get_llm(project_id, db=db)
            
            if llm:
                # Invoke LLM
                from langchain_core.prompts import ChatPromptTemplate
                prompt = ChatPromptTemplate.from_messages([
                    ("system", system_prompt),
                    ("user", "Please generate the Socratic hint.")
                ])
                chain = prompt | llm
                res = await chain.ainvoke({})
                hint = res.content.strip()
            else:
                hint = "Socratic Tutor model configuration not found. Check your API settings."
    except Exception as e:
        logger.error(f"Socratic Hint generation failed: {e}", exc_info=True)
        hint = f"Tutor Error: {str(e)[:100]}"
        
    # Send response back via WebSocket
    try:
        await websocket.send_json({
            "type": "socratic_hint_response",
            "workspace": workspace,
            "payload": {
                "question_id": question_id,
                "hint": hint
            }
        })
    except Exception as ws_err:
        logger.error(f"Failed to send Socratic hint response: {ws_err}")
