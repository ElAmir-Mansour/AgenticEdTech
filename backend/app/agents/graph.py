import json
import logging
import re
from typing import Dict, Any, List
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
from langchain_groq import ChatGroq
from langchain_core.prompts import ChatPromptTemplate

from app.agents.state import AgentState
from app.config import settings
from app.ws.manager import ws_manager

logger = logging.getLogger(__name__)

def parse_and_strip_suggestions(content: str) -> tuple[str, list]:
    """Extracts dynamic suggestion chips from the content and strips the tag."""
    if not content:
        return content, []
    pattern = r"<!-- SUGGESTIONS:\s*(\[.*?\])\s*-->"
    match = re.search(pattern, content, re.DOTALL)
    suggestions = []
    if match:
        try:
            suggestions = json.loads(match.group(1))
            content = re.sub(pattern, "", content).strip()
        except Exception as e:
            logger.warning(f"Failed to parse suggestions JSON: {e}")
    return content, suggestions

def parse_question_count(instruction: str) -> int:
    """Parses the requested number of questions from the user instruction, defaulting to 5."""
    if not instruction:
        return 5
    instruction_lower = instruction.lower()
    
    # 1. Match patterns like: "20 questions", "20 q", "twenty questions", "quiz of 20", etc.
    matches = re.findall(r'\b(\d+)\s*(?:questions|question|q|quiz|mcq|mcqs|items|item)\b', instruction_lower)
    if matches:
        try:
            val = int(matches[0])
            if 1 <= val <= 30:
                return val
        except ValueError:
            pass
            
    # 2. Check for text numbers
    word_to_num = {
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "fifteen": 15, "twenty": 20, "thirty": 30
    }
    for word, num in word_to_num.items():
        if re.search(r'\b' + word + r'\s*(?:questions|question|q|quiz|mcq|mcqs|items|item)\b', instruction_lower):
            return num
            
    # 3. Look for a standalone number of questions request like: "quiz with 20", "test of 20"
    matches_of = re.findall(r'\b(?:quiz|test|mcqs|questions)\s*(?:of|with|having)?\s*(\d+)\b', instruction_lower)
    if matches_of:
        try:
            val = int(matches_of[0])
            if 1 <= val <= 30:
                return val
        except ValueError:
            pass
            
    # 4. Look for a simple standalone number at the end or start of a short prompt
    if len(instruction_lower.split()) <= 6:
        lonely_matches = re.findall(r'\b(\d+)\b', instruction_lower)
        if lonely_matches:
            try:
                val = int(lonely_matches[0])
                if 1 <= val <= 30:
                    return val
            except ValueError:
                pass
                
    return 5

def parse_syllabus_duration(instruction: str) -> str:
    """Parses the requested syllabus duration/structure from the instruction, defaulting to '3-week'."""
    if not instruction:
        return "3-week"
    instruction_lower = instruction.lower()
    
    # Match patterns like: "6-week", "6 weeks", "2-day", "4 days", "2-month", "5 modules", "6 chapters"
    pattern = r'\b(\d+)\s*(?:-| )?(weeks|week|days|day|months|month|modules|module|chapters|chapter|units|unit)\b'
    match = re.search(pattern, instruction_lower)
    if match:
        val = match.group(1)
        unit = match.group(2)
        if "day" in unit:
            unit_str = "day"
        elif "week" in unit:
            unit_str = "week"
        elif "month" in unit:
            unit_str = "month"
        elif "module" in unit:
            unit_str = "module"
        elif "chapter" in unit:
            unit_str = "chapter"
        elif "unit" in unit:
            unit_str = "unit"
        else:
            unit_str = "week"
            
        return f"{val}-{unit_str}"
        
    # Check for text numbers
    word_to_num = {
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10
    }
    for word, num in word_to_num.items():
        pattern_word = r'\b' + word + r'\s*(?:-| )?(weeks|week|days|day|months|month|modules|module|chapters|chapter|units|unit)\b'
        match = re.search(pattern_word, instruction_lower)
        if match:
            unit = match.group(1)
            if "day" in unit:
                unit_str = "day"
            elif "week" in unit:
                unit_str = "week"
            elif "month" in unit:
                unit_str = "month"
            elif "module" in unit:
                unit_str = "module"
            elif "chapter" in unit:
                unit_str = "chapter"
            elif "unit" in unit:
                unit_str = "unit"
            else:
                unit_str = "week"
            return f"{num}-{unit_str}"
            
    return "3-week"

def format_context_chunks(chunks: list) -> str:
    """Formats rich context dictionaries with source/page metadata headers for the LLM."""
    if not chunks:
        return ""
    context_str = ""
    for idx, c in enumerate(chunks):
        if isinstance(c, dict):
            fn = c.get("filename", "Unknown")
            page = c.get("page_number", 1)
            content = c.get("content", "")
            context_str += f"--- REFERENCE CHUNK {idx+1} [Document: {fn}, Page: {page}] ---\n{content}\n\n"
        else:
            context_str += f"{c}\n\n"
    return context_str.strip()


# Utility to send real-time streams to WebSocket client
async def stream_agent_update(user_id: str, agent_name: str, message_type: str, content: str):
    """Utility to stream real-time agent output to the user's WebSocket client."""
    try:
        from uuid import UUID
        user_uuid = UUID(user_id)
        
        # Intercept and extract dynamic suggestions if present
        clean_content, suggestions = parse_and_strip_suggestions(content)
        
        payload = {
            "agent": agent_name,
            "messageType": message_type,
            "content": clean_content
        }
        if suggestions:
            payload["suggestions"] = suggestions
            
        await ws_manager.send_to_user(user_uuid, {
            "type": "agent_stream",
            "workspace": "canvas",
            "payload": payload
        })
    except Exception as e:
        logger.error(f"Failed to stream agent update to WebSocket: {e}")

# Helper to retrieve configured LLM (cloud or local) dynamically
async def get_llm(project_id: str = None, db = None):
    project_settings = {}
    if project_id:
        try:
            if db:
                from app.models.database import Project
                from sqlalchemy import select
                proj = await db.scalar(select(Project).where(Project.id == project_id))
                if proj and proj.settings:
                    project_settings = proj.settings
            else:
                from app.database import async_session_maker
                from app.models.database import Project
                from sqlalchemy import select
                async with async_session_maker() as session:
                    proj = await session.scalar(select(Project).where(Project.id == project_id))
                    if proj and proj.settings:
                        project_settings = proj.settings
        except Exception as e:
            logger.error(f"Error fetching project settings for dynamic LLM route: {e}")

    provider = project_settings.get("llm_provider", "groq")
    model = project_settings.get("llm_model", "llama-3.3-70b-versatile")
    url = project_settings.get("llm_url", "")
    api_key = project_settings.get("llm_api_key", "")

    if not provider:
        provider = "groq"

    if provider == "groq":
        groq_key = api_key or settings.GROQ_API_KEY
        if groq_key and groq_key != "mock_key":
            try:
                from langchain_groq import ChatGroq
                logger.info(f"Initializing ChatGroq model {model} (project_id={project_id})")
                return ChatGroq(
                    model=model,
                    groq_api_key=groq_key,
                    temperature=0.7
                )
            except Exception as e:
                logger.error(f"Failed to load Groq LLM: {e}")
        return None

    elif provider == "gemini":
        gemini_key = api_key or settings.GOOGLE_API_KEY
        if gemini_key and gemini_key != "mock_key":
            try:
                from langchain_google_genai import ChatGoogleGenerativeAI
                logger.info(f"Initializing ChatGoogleGenerativeAI model {model} (project_id={project_id})")
                return ChatGoogleGenerativeAI(
                    model=model,
                    google_api_key=gemini_key,
                    temperature=0.7
                )
            except Exception as e:
                logger.error(f"Failed to load Gemini LLM: {e}")
        return None

    elif provider in ("local_ollama", "local_openai"):
        try:
            from langchain_openai import ChatOpenAI
            base_url = url or ("http://localhost:11434/v1" if provider == "local_ollama" else "http://localhost:1234/v1")
            actual_key = api_key or "local"
            logger.info(f"Initializing Local LLM via ChatOpenAI: {model} at {base_url} (project_id={project_id})")
            return ChatOpenAI(
                model=model,
                base_url=base_url,
                api_key=actual_key,
                temperature=0.7
            )
        except Exception as e:
            logger.error(f"Failed to load Local LLM via ChatOpenAI: {e}")
            return None

    return None



# --- PEDAGOGICAL FRAMEWORK GUIDANCE DICTIONARIES ---
# These guide the prompts for Planning, Content, Critique, and Assessment agents.
# Supporting Scenario-Based, Socratic Inquiry, Bloom's Progression, and Traditional/Compliance models.

FRAMEWORK_PLANNING_GUIDANCE = {
    "traditional": (
        "Focus on traditional instructional design structure. Divide the syllabus into standard logical modules, "
        "covering learning objectives, core definitions, and structured review chapters."
    ),
    "scenario_based": (
        "Focus strictly on Scenario-Based Learning (SBL). Every module in the syllabus must revolve around a specific, "
        "real-world decision-making case study or scenario. Structure each module to define: "
        "1) The Context/Role, 2) The Critical Dilemma/Challenge, 3) The Decision Choices, 4) The Consequences."
    ),
    "socratic": (
        "Focus on Socratic Inquiry. Structure the outline as a dialogic sequence of discovery. "
        "Each module title should be framed as a central questioning topic (e.g. 'Why do we need interfaces?' rather than 'Interfaces Overview'). "
        "Outline the conceptual steps where questions guide learners to deduce principles."
    ),
    "blooms": (
        "Focus strictly on Bloom's Taxonomy Cognitive Progression. Structure the syllabus strictly to transition "
        "from basic cognition to advanced application: "
        "Module 1: Remember & Understand (Core terminology, definitions, concepts) "
        "Module 2: Apply & Analyze (Executing processes, debugging, analyzing patterns) "
        "Module 3: Evaluate & Create (Critiquing designs, architecting new solutions, synthesis)"
    )
}

FRAMEWORK_CONTENT_GUIDANCE = {
    "traditional": (
        "Structure the written instructional module with standard corporate compliance formatting. "
        "Ensure clear section headings, bulleted lists for rules, and a summary at the end. "
        "Divide it into: 1. Objectives, 2. Core Concepts, 3. Guidelines & Process, 4. Standard Quiz Prep Summary."
    ),
    "scenario_based": (
        "Apply Scenario-Based Learning (SBL). The module content must be written as a narrative case study or dilemma. "
        "Do NOT just list abstract theories. Start with a concrete story setting up a character, a situation, and a critical "
        "decision. Then, explain the choices they face and the consequences. Interweave the theoretical concepts "
        "implicitly into the feedback and aftermath of those decisions."
    ),
    "socratic": (
        "Apply Socratic Inquiry. Write the module as a guided dialogue between a teacher and a student, or a sequence "
        "of questioning prompts and logical derivations. Ask a question, guide the reader's reasoning, address common misconceptions, "
        "and help the reader arrive at the conclusion themselves. Use a reflective, philosophical, yet clear tone."
    ),
    "blooms": (
        "Ensure the written content strictly respects the target cognitive levels defined in the approved outline. "
        "Focus on defining/explaining terms in introductory sections, demonstrating execution in intermediate sections, "
        "and providing synthesis/architecture exercises in advanced sections. Label the cognitive target of each section."
    )
}

FRAMEWORK_CRITIQUE_GUIDANCE = {
    "traditional": "Evaluate if the content is clear, well-structured, and suitable for compliance training.",
    "scenario_based": "Critique if the content is sufficiently scenario-driven. Ensure there is a compelling narrative, a clear dilemma, and feedback on choices. If it is too theoretical, demand more story integration.",
    "socratic": "Critique if the content utilizes Socratic questioning. Ensure it guides the learner to deduce principles. If it just lists facts or is too didactic, demand more inquiry-based framing.",
    "blooms": "Critique if the content strictly matches the target Bloom's cognitive taxonomy level. If introductory content is too complex or advanced content is too trivial, flag the mismatch."
}

FRAMEWORK_ASSESSMENT_GUIDANCE = {
    "traditional": (
        "Generate traditional multiple-choice questions that test knowledge retention, definitions, and standard procedures."
    ),
    "scenario_based": (
        "All questions MUST be scenario-based. Frame each question as a mini-scenario (e.g., 'An engineer is faced with X... What should they do?'). "
        "The choices must represent realistic actions, and the explanation must clarify the consequences of the choices."
    ),
    "socratic": (
        "All questions should focus on conceptual debugging, identifying errors in reasoning, or choosing the logical premise that supports an argument."
    ),
    "blooms": (
        "Ensure questions map strictly to the respective Bloom's Taxonomy level (e.g., if target level is 'Apply', test application; if 'Remember', test recall)."
    )
}


# --- AGENT NODES WITH STREAMING ---

async def planning_node(state: AgentState) -> Dict[str, Any]:
    """Proposes curriculum course outline based on user topic."""
    logger.info("Planning Agent active")
    topic = state.get("topic", "General Topic")
    instruction = state.get("instruction", "")
    user_id = state.get("user_id", "")
    previous_outline = state.get("previous_outline", "")
    generation_mode = state.get("generation_mode", "full")
    pedagogical_framework = state.get("pedagogical_framework", "traditional")
    duration = parse_syllabus_duration(instruction)
    
    await stream_agent_update(user_id, "Planning Agent", "thinking", "Analyzing curriculum requirements and drafting outline plan...")
    
    prompt_instruction = instruction if instruction else topic
    
    llm = await get_llm(state.get("project_id"))
    if llm:
        try:
            if generation_mode == "quiz":
                q_count = parse_question_count(instruction)
                if previous_outline:
                    system_prompt = (
                        f"You are an expert Planning Agent. Propose a structured quiz plan outline "
                        f"for the topic '{topic}' by modifying and refining the previous outline based on the user's instructions. "
                        f"Propose exactly {q_count} sub-topics/objectives (corresponding to one quiz question each) to be tested, their difficulty levels, and target Bloom's Taxonomy levels.\n\n"
                        f"Previous Outline:\n{previous_outline}\n\n"
                        f"At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts (e.g. 'Make it harder', 'Focus on Scrum concepts', 'Test practical terms') in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                    )
                else:
                    context_chunks = state.get("context_chunks", [])
                    context_str = format_context_chunks(context_chunks)
                    if context_str:
                        system_prompt = (
                            f"You are an expert Planning Agent. Propose a structured quiz plan outline "
                            f"for the topic '{topic}', strictly grounded in the provided reference materials/uploaded documents. "
                            f"Propose exactly {q_count} sub-topics/objectives (corresponding to one quiz question each) to be tested, their difficulty levels, and target Bloom's Taxonomy levels.\n\n"
                            f"Reference Materials:\n{context_str}\n\n"
                            f"At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts (e.g. 'Focus on core definitions', 'Increase technical complexity', 'Test application level') in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                        )
                    else:
                        system_prompt = (
                            f"You are an expert Planning Agent. Propose a structured quiz plan outline "
                            f"for the topic '{topic}'. Propose exactly {q_count} sub-topics/objectives (corresponding to one quiz question each) to be tested, their difficulty levels, and target Bloom's Taxonomy levels.\n\n"
                            f"At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                        )
            else:
                if previous_outline:
                    system_prompt = (
                        f"You are an expert Planning Agent. Propose a structured {duration} course syllabus outline "
                        f"for the topic '{topic}' by modifying and refining the previous outline based on the user's instructions. "
                        f"Maintain consistency with the course subject but execute the requested modification.\n\n"
                        f"Previous Outline:\n{previous_outline}\n\n"
                        f"At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                    )
                else:
                    context_chunks = state.get("context_chunks", [])
                    context_str = format_context_chunks(context_chunks)
                    if context_str:
                        system_prompt = (
                            f"You are an expert Planning Agent. Propose a structured {duration} course syllabus outline "
                            f"for the topic '{topic}', strictly grounded in the provided reference materials/uploaded documents.\n\n"
                            f"Reference Materials:\n{context_str}\n\n"
                            f"At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                        )
                    else:
                        system_prompt = (
                            f"You are an expert Planning Agent. Propose a structured {duration} course syllabus outline "
                            f"for the topic '{topic}'. Keep it concise.\n\n"
                            f"At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                        )
            
            # Prepend framework-specific guidance to system prompt
            framework_guidance = FRAMEWORK_PLANNING_GUIDANCE.get(pedagogical_framework, FRAMEWORK_PLANNING_GUIDANCE["traditional"])
            system_prompt = f"Design Guidance for Framework: {pedagogical_framework.upper()}\n{framework_guidance}\n\n" + system_prompt
            
            prompt = ChatPromptTemplate.from_messages([
                ("system", system_prompt),
                ("user", "Instructions: {instruction}")
            ])
            chain = prompt | llm
            res = await chain.ainvoke({"instruction": prompt_instruction})
            outline = res.content
        except Exception as e:
            logger.error(f"Planning LLM call failed: {e}")
            outline = f"Error: Failed to generate planning outline. LLM Error: {str(e)[:100]}. Please check API key."
    else:
        outline = f"Error: LLM not configured. Please check your API key."
        
    await stream_agent_update(user_id, "Planning Agent", "draft", outline)
    
    msg = {
        "role": "assistant",
        "agent": "Planning Agent",
        "content": f"Proposed course outline:\n\n{outline}"
    }
    
    return {
        "outline": outline,
        "messages": [msg],
        "current_agent": "Planning Agent",
        "hitl_status": "pending"
    }


async def hitl_checkpoint_node(state: AgentState) -> Dict[str, Any]:
    """Human-in-the-Loop outline approval checkpoint node.
    
    NOTE: When interrupt_before is used, this node only executes AFTER the user
    has already approved/rejected via the handler. The approval_request is sent
    by the handler code, not this node.
    """
    logger.info(f"HITL checkpoint node executing. Status: {state.get('hitl_status')}")
    return {}


async def content_node(state: AgentState) -> Dict[str, Any]:
    """Drafts detailed course materials based on approved outline."""
    logger.info("Content Agent active")
    topic = state.get("topic", "")
    outline = state.get("outline", "")
    user_id = state.get("user_id", "")
    previous_draft = state.get("previous_draft_content", "")
    pedagogical_framework = state.get("pedagogical_framework", "traditional")
    
    await stream_agent_update(user_id, "Content Agent", "thinking", "Drafting core instructional chapter contents using grounding chunks...")
    
    llm = await get_llm(state.get("project_id"))
    if llm:
        try:
            if previous_draft:
                system_prompt = (
                    f"You are an expert Content Writing Agent. Rewrite and refine the previous instructional reading "
                    f"material for '{topic}' to align with the new approved outline. Maintain premium, educational, and thorough tone.\n\n"
                    f"Previous Material:\n{previous_draft}\n\n"
                    f"At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts (e.g. 'Make it simpler', 'Add more practical examples') in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                )
            else:
                context_chunks = state.get("context_chunks", [])
                context_str = format_context_chunks(context_chunks)
                if context_str:
                    system_prompt = (
                        f"You are an expert Content Writing Agent. Write a highly thorough, detailed, and complete "
                        f"educational reading module for '{topic}' based on the approved outline.\n"
                        f"To ensure it is useful for SCORM LMS packaging, structure it into the following 5 distinct sections:\n"
                        f"1. INTRODUCTION & OBJECTIVES: Outline what learners will achieve.\n"
                        f"2. CORE THEORY & CONCEPTS: Deep explanation of principles and systems.\n"
                        f"3. APPLICATION & PRACTICE: Practical guide on implementation.\n"
                        f"4. EXAMPLES & CASE STUDIES: Grounded real-world scenarios.\n"
                        f"5. TAKEAWAYS & KEY SUMMARY: Bulleted summary of core points.\n\n"
                        f"Strictly use the provided reference materials to ground the details and facts. Maintain a premium, educational, and academic tone.\n"
                        f"CRITICAL GROUNDING RULE: For each fact, concept, or process you introduce from the reference materials, you MUST append an inline citation at the end of the sentence or paragraph in this exact format: [Source: filename, Page: page_number] matching the document name and page number headers specified in the Reference Materials.\n\n"
                        f"Reference Materials:\n{context_str}\n\n"
                        f"At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                    )
                else:
                    system_prompt = (
                        f"You are an expert Content Writing Agent. Write a highly thorough, detailed, and complete "
                        f"educational reading module for '{topic}' based on the approved outline.\n"
                        f"Structure it into the following 5 distinct sections:\n"
                        f"1. INTRODUCTION & OBJECTIVES\n"
                        f"2. CORE THEORY & CONCEPTS\n"
                        f"3. APPLICATION & PRACTICE\n"
                        f"4. EXAMPLES & CASE STUDIES\n"
                        f"5. TAKEAWAYS & KEY SUMMARY\n\n"
                        f"Keep the tone premium, educational, and thorough.\n\n"
                        f"At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                    )
            
            # Prepend framework-specific guidance to system prompt
            framework_guidance = FRAMEWORK_CONTENT_GUIDANCE.get(pedagogical_framework, FRAMEWORK_CONTENT_GUIDANCE["traditional"])
            system_prompt = f"Content Guidance for Framework: {pedagogical_framework.upper()}\n{framework_guidance}\n\n" + system_prompt
            
            prompt = ChatPromptTemplate.from_messages([
                ("system", system_prompt),
                ("user", "Course Topic: {topic}\nApproved Outline:\n{outline}")
            ])
            chain = prompt | llm
            res = await chain.ainvoke({"topic": topic, "outline": outline})
            draft = res.content
        except Exception as e:
            logger.error(f"Content LLM call failed: {e}")
            draft = f"Error: Failed to draft content. LLM Error: {str(e)[:100]}"
    else:
        draft = f"Error: LLM not configured."

    await stream_agent_update(user_id, "Content Agent", "draft", draft)

    msg = {
        "role": "assistant",
        "agent": "Content Agent",
        "content": f"Drafted lesson content:\n\n{draft}"
    }
    
    return {
        "draft_content": draft,
        "messages": [msg],
        "current_agent": "Content Agent"
    }


async def critique_node(state: AgentState) -> Dict[str, Any]:
    """Reviews draft and issues critiques."""
    logger.info("Critique Agent active")
    draft = state.get("draft_content", "")
    rev_count = state.get("revision_count", 0)
    user_id = state.get("user_id", "")
    pedagogical_framework = state.get("pedagogical_framework", "traditional")
    
    await stream_agent_update(user_id, "Critique Agent", "thinking", "Reviewing lesson draft for cognitive quality and Bloom's alignment...")
    
    # Simple rule: if we've already revised once, let it pass critique
    if rev_count >= 1:
        msg = {
            "role": "assistant",
            "agent": "Critique Agent",
            "content": "Review completed. The draft revision meets quality metrics and has been approved."
        }
        await stream_agent_update(user_id, "Critique Agent", "critique", "Approved! Proceeding to assessments. <!-- SUGGESTIONS: [\"Generate quiz questions\"] -->")
        return {
            "critique_notes": [],
            "messages": [msg],
            "current_agent": "Critique Agent"
        }
        
    llm = await get_llm(state.get("project_id"))
    if llm:
        try:
            framework_guidance = FRAMEWORK_CRITIQUE_GUIDANCE.get(pedagogical_framework, FRAMEWORK_CRITIQUE_GUIDANCE["traditional"])
            system_prompt = (
                f"You are an expert Quality Critique Agent. Critique the draft against the following guidelines for the framework {pedagogical_framework.upper()}:\n"
                f"{framework_guidance}\n\n"
                "Analyze this draft. Suggest exactly one improvement. Respond in plain text.\n"
                "At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
            )
            prompt = ChatPromptTemplate.from_messages([
                ("system", system_prompt),
                ("user", "Lesson Draft:\n{draft}")
            ])
            chain = prompt | llm
            res = await chain.ainvoke({"draft": draft})
            critique = res.content
        except Exception as e:
            logger.error(f"Critique LLM call failed: {e}")
            critique = f"Error: Failed to critique draft. LLM Error: {str(e)[:100]}"
    else:
        critique = "Error: Gemini LLM not configured."
        
    await stream_agent_update(user_id, "Critique Agent", "critique", critique)
    
    msg = {
        "role": "assistant",
        "agent": "Critique Agent",
        "content": f"Quality critique notes:\n\n{critique}"
    }
    
    return {
        "critique_notes": [critique],
        "messages": [msg],
        "current_agent": "Critique Agent"
    }


async def revision_node(state: AgentState) -> Dict[str, Any]:
    """Revises draft based on critique notes."""
    logger.info("Revision Agent active")
    draft = state.get("draft_content", "")
    critique = "\n".join(state.get("critique_notes", []))
    rev_count = state.get("revision_count", 0)
    user_id = state.get("user_id", "")
    
    await stream_agent_update(user_id, "Content Agent", "thinking", "Revising lesson content based on critique feedback...")
    
    llm = await get_llm(state.get("project_id"))
    if llm:
        try:
            prompt = ChatPromptTemplate.from_messages([
                ("system", "You are an expert Revision Agent. Rewrite the draft to address the critique notes. Integrate the requested feedback naturally.\n"
                           "At the very end of your response, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."),
                ("user", "Current Draft:\n{draft}\n\nCritique feedback:\n{critique}")
            ])
            chain = prompt | llm
            res = await chain.ainvoke({"draft": draft, "critique": critique})
            new_draft = res.content
        except Exception as e:
            logger.error(f"Revision LLM call failed: {e}")
            new_draft = draft + f"\n\n*(Error during revision: {str(e)[:100]})*"
    else:
        new_draft = draft + "\n\n*(Error: Gemini LLM not configured)*"

    await stream_agent_update(user_id, "Content Agent", "draft", new_draft)

    msg = {
        "role": "assistant",
        "agent": "Content Agent",
        "content": f"Submitted revised lesson content:\n\n{new_draft}"
    }
    
    return {
        "draft_content": new_draft,
        "revision_count": rev_count + 1,
        "critique_notes": [],
        "messages": [msg],
        "current_agent": "Content Agent"
    }


async def assessment_node(state: AgentState) -> Dict[str, Any]:
    """Generates quiz questions for the module."""
    logger.info("Assessment Agent active")
    draft = state.get("draft_content", "")
    user_id = state.get("user_id", "")
    topic = state.get("topic", "Topic")
    generation_mode = state.get("generation_mode", "full")
    instruction = state.get("instruction", "")
    pedagogical_framework = state.get("pedagogical_framework", "traditional")
    
    q_count = parse_question_count(instruction)
    
    await stream_agent_update(user_id, "Assessment Agent", "thinking", f"Generating {q_count} multiple-choice quiz questions...")
    
    llm = await get_llm(state.get("project_id"))
    quizzes = []
    suggestions = []
    if llm:
        try:
            if generation_mode == "quiz":
                context_chunks = state.get("context_chunks", [])
                context_str = format_context_chunks(context_chunks)
                system_prompt = (
                    f"You are an expert Assessment Agent. Generate a comprehensive quiz with exactly {q_count} diverse multiple-choice questions "
                    f"for the topic '{topic}' based on the provided reference materials.\n"
                    f"Reference Materials:\n{context_str}\n\n"
                    "The questions must span different cognitive levels of Bloom's Taxonomy (Remember, Understand, Apply, Analyze).\n"
                    "Return ONLY a valid JSON array of objects matching the schema below:\n"
                    "[\n"
                    "  {{\n"
                    "    \"question_text\": \"What is the primary benefit of X?\",\n"
                    "    \"question_type\": \"multiple_choice\",\n"
                    "    \"options\": [\"Benefit A\", \"Benefit B\", \"Benefit C\", \"Benefit D\"],\n"
                    "    \"correct_answer\": \"Benefit A\",\n"
                    "    \"blooms_level\": \"apply\",\n"
                    "    \"difficulty\": 0.5,\n"
                    "    \"explanation\": \"Why this answer is correct.\",\n"
                    "    \"source_info\": \"Document: filename, Page: page_number\"\n"
                    "  }},\n"
                    "  ...\n"
                    "]\n\n"
                    "CRITICAL GROUNDING RULE: For each generated question, specify the exact source document name and page number under the 'source_info' attribute. Populate it in this exact format: 'Document: filename, Page: page_number'. This must match the reference chunk metadata.\n\n"
                    "At the very end of your response, OUTSIDE the JSON code block, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                )
                user_content = f"Quiz Topic: {topic}\nApproved Quiz Plan:\n{state.get('outline', '')}"
            else:
                system_prompt = (
                    f"You are an expert Assessment Agent. Generate a comprehensive quiz with exactly {q_count} diverse multiple-choice questions based on the lesson content.\n"
                    "The questions must span different cognitive levels of Bloom's Taxonomy (Remember, Understand, Apply, Analyze).\n"
                    "Return ONLY a valid JSON array of objects matching the schema below:\n"
                    "[\n"
                    "  {{\n"
                    "    \"question_text\": \"What is the primary benefit of X?\",\n"
                    "    \"question_type\": \"multiple_choice\",\n"
                    "    \"options\": [\"Benefit A\", \"Benefit B\", \"Benefit C\", \"Benefit D\"],\n"
                    "    \"correct_answer\": \"Benefit A\",\n"
                    "    \"blooms_level\": \"apply\",\n"
                    "    \"difficulty\": 0.5,\n"
                    "    \"explanation\": \"Why this answer is correct.\",\n"
                    "    \"source_info\": \"Lesson Content Section X\"\n"
                    "  }},\n"
                    "  ...\n"
                    "]\n\n"
                    "At the very end of your response, OUTSIDE the JSON code block, append a list of 3 context-aware follow-up suggestion prompts in this exact format: <!-- SUGGESTIONS: [\"suggested action 1\", \"suggested action 2\", \"suggested action 3\"] -->."
                )
                user_content = f"Lesson Content:\n{draft}"
            
            # Prepend framework-specific guidance to system prompt
            framework_guidance = FRAMEWORK_ASSESSMENT_GUIDANCE.get(pedagogical_framework, FRAMEWORK_ASSESSMENT_GUIDANCE["traditional"])
            system_prompt = f"Assessment Guidance for Framework: {pedagogical_framework.upper()}\n{framework_guidance}\n\n" + system_prompt
            
            prompt = ChatPromptTemplate.from_messages([
                ("system", system_prompt),
                ("user", user_content)
            ])
            chain = prompt | llm
            res = await chain.ainvoke({})
            
            raw_response = res.content.strip()
            # Clean and parse suggestions from the raw response first
            clean_raw, suggestions = parse_and_strip_suggestions(raw_response)
            
            raw = clean_raw
            if raw.startswith("```json"):
                raw = raw[7:]
            if raw.endswith("```"):
                raw = raw[:-3]
            raw = raw.strip()
            
            q_list = json.loads(raw)
            if isinstance(q_list, list):
                quizzes = q_list
            else:
                quizzes = [q_list]
        except Exception as e:
            logger.error(f"Assessment LLM call failed: {e}")
            quizzes = [{"question_text": f"Error generating quiz: {str(e)[:100]}", "options": ["A"], "correct_answer": "A"}]
    else:
        quizzes = [{"question_text": "Error: LLM not configured", "options": ["A"], "correct_answer": "A"}]
        
    # Build human-readable summary for the chat (NOT raw JSON)
    if quizzes and quizzes[0].get("question_text", "").startswith("Error"):
        quiz_summary = quizzes[0]["question_text"]
    else:
        blooms_levels = Array_Unique([q.get("blooms_level", "understand").capitalize() for q in quizzes])
        blooms_str = ", ".join(blooms_levels)
        quiz_summary = f"Generated **{len(quizzes)} quiz questions** spanning Bloom's levels: **{blooms_str}**."
        if quizzes:
            quiz_summary += f"\n\n> **Preview Q1:** {quizzes[0].get('question_text', '')}\n> • *A)* {quizzes[0].get('options', [''])[0]}"
        
    # Re-append suggestions to quiz_summary so stream_agent_update detects it!
    if suggestions:
        quiz_summary += f"\n\n<!-- SUGGESTIONS: {json.dumps(suggestions)} -->"
    elif generation_mode == "quiz":
        # Fallback suggestions for quiz mode
        quiz_summary += f"\n\n<!-- SUGGESTIONS: [\"Export this quiz\", \"Regenerate quiz\", \"Make it simpler\"] -->"
        
    await stream_agent_update(user_id, "Assessment Agent", "quiz_summary", quiz_summary)
        
    msg = {
        "role": "assistant",
        "agent": "Assessment Agent",
        "content": quiz_summary
    }
    
    return {
        "quiz_questions": quizzes,
        "messages": [msg],
        "current_agent": "Assessment Agent"
    }


def Array_Unique(seq):
    seen = set()
    return [x for x in seq if not (x in seen or seen.add(x))]


async def heatmap_analysis_node(state: AgentState) -> Dict[str, Any]:
    """Calculates text complexity score metrics."""
    logger.info("Heatmap Analysis Agent active")
    draft = state.get("draft_content", "")
    user_id = state.get("user_id", "")
    
    await stream_agent_update(user_id, "Heatmap Agent", "thinking", "Analyzing paragraph cognitive load metrics...")
    
    from app.utils.cognitive_load import analyze_text
    heatmap_scores = analyze_text(draft)
    
    # Build human-readable summary instead of raw JSON
    total = len(heatmap_scores)
    if total > 0:
        avg_score = sum(s.get("compositeScore", 0) for s in heatmap_scores) / total
        avg_fk = sum(s.get("fleschKincaid", 0) for s in heatmap_scores) / total
        high_count = sum(1 for s in heatmap_scores if s.get("compositeScore", 0) > 0.65)
        low_count = sum(1 for s in heatmap_scores if s.get("compositeScore", 0) <= 0.35)
        
        level = "🟢 Easy" if avg_score <= 0.35 else "🟡 Moderate" if avg_score <= 0.65 else "🔴 Complex"
        summary = (f"Analyzed **{total} paragraphs** — Overall: **{level}**\n\n"
                   f"• Average Grade Level: **{avg_fk:.1f}** (Flesch-Kincaid)\n"
                   f"• Average Cognitive Load: **{avg_score:.2f}** / 1.0\n"
                   f"• 🟢 Low complexity sections: **{low_count}**\n"
                   f"• 🔴 High complexity sections: **{high_count}**")
        if high_count > 0:
            summary += f"\n\n> ⚠️ {high_count} section(s) may be too complex for beginner learners. Consider simplifying."
    else:
        summary = "No paragraphs found to analyze."
        
    summary += "\n\n<!-- SUGGESTIONS: [\"Export this module\", \"Create another module\", \"Increase difficulty\"] -->"
    
    await stream_agent_update(user_id, "Heatmap Agent", "heatmap_summary", summary)
    
    msg = {
        "role": "assistant",
        "agent": "Heatmap Agent",
        "content": summary
    }
    
    return {
        "heatmap_data": {"scores": heatmap_scores},
        "messages": [msg],
        "current_agent": "Heatmap Agent"
    }


# --- CONDITIONAL ROUTING EDGES ---

def check_hitl_status(state: AgentState) -> str:
    """Decides transition depending on HITL outline approval."""
    status = state.get("hitl_status", "pending")
    mode = state.get("generation_mode", "full")
    if status == "approved":
        return "approved_quiz" if mode == "quiz" else "approved"
    elif status == "rejected":
        return "rejected"
    return "pending"


def should_revise(state: AgentState) -> str:
    """Decides if the Critique Agent has critique notes to resolve."""
    notes = state.get("critique_notes", [])
    if notes and len(notes) > 0:
        return "revise"
    return "pass"


# --- BUILD GRAPH ---

def build_curriculum_graph(checkpointer=None):
    """Compiles the multi-agent curriculum graph."""
    if checkpointer is None:
        checkpointer = MemorySaver()
        
    workflow = StateGraph(AgentState)
    
    # Add nodes
    workflow.add_node("planning", planning_node)
    workflow.add_node("hitl_outline", hitl_checkpoint_node)
    workflow.add_node("content", content_node)
    workflow.add_node("critique", critique_node)
    workflow.add_node("revision", revision_node)
    workflow.add_node("assessment", assessment_node)
    workflow.add_node("heatmap", heatmap_analysis_node)
    
    # Add edges
    workflow.add_edge("planning", "hitl_outline")
    
    workflow.add_conditional_edges(
        "hitl_outline",
        check_hitl_status,
        {
            "approved": "content",
            "approved_quiz": "assessment",
            "rejected": "planning",
            "pending": "hitl_outline"
        }
    )
    
    workflow.add_edge("content", "critique")
    
    workflow.add_conditional_edges(
        "critique",
        should_revise,
        {
            "revise": "revision",
            "pass": "assessment"
        }
    )
    
    workflow.add_edge("revision", "critique")
    
    workflow.add_conditional_edges(
        "assessment",
        lambda state: "heatmap" if state.get("generation_mode", "full") == "full" else "end",
        {
            "heatmap": "heatmap",
            "end": END
        }
    )
    
    workflow.add_edge("heatmap", END)
    
    workflow.set_entry_point("planning")
    
    return workflow.compile(
        checkpointer=checkpointer,
        interrupt_before=["hitl_outline"]
    )
