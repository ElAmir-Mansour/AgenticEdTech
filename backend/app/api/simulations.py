import random
import logging
from datetime import datetime
from typing import Literal, Optional, Any
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.database import get_db
from app.models.database import Project, QuizQuestion, CurriculumModule, SimulationRun, PersonaResult
from app.models.schemas import RunSimulationRequest, PersonaProfile as SchemaPersonaProfile, SimulationRunResponse, SimulationRunDetailResponse, PersonaResultResponse
from app.auth.dependencies import get_current_user_id

logger = logging.getLogger(__name__)
router = APIRouter()

# Default validated personas
PERSONAS = [
    SchemaPersonaProfile(name="Alex", experience="Beginner", background="Career Changer (Sales)", attention_span="Low", error_rate=0.45),
    SchemaPersonaProfile(name="Sofia", experience="Intermediate", background="Product Associate", attention_span="High", error_rate=0.18),
    SchemaPersonaProfile(name="Jordan", experience="Expert", background="Software Dev (Junior)", attention_span="Medium", error_rate=0.08),
]


def generate_cohort(cohort_size: int, template_personas: list[SchemaPersonaProfile]) -> list[SchemaPersonaProfile]:
    if cohort_size <= len(template_personas):
        return template_personas[:cohort_size]
    
    cohort = []
    cohort.extend(template_personas)
    
    remaining = cohort_size - len(template_personas)
    
    first_names = ["Emma", "Liam", "Olivia", "Noah", "Ava", "Oliver", "Sophia", "Elijah", "Isabella", "James", 
                   "Mia", "Benjamin", "Charlotte", "Lucas", "Amelia", "Mason", "Harper", "Ethan", "Evelyn", "Alexander"]
    last_initials = ["A.", "B.", "C.", "D.", "E.", "F.", "G.", "H.", "K.", "M.", "P.", "R.", "S.", "T.", "W."]
    
    backgrounds = [
        "Career Changer (Support)", "Business Analyst", "Marketing Specialist", "Customer Success Rep",
        "Operations Specialist", "Associate Project Manager", "Technical Writer", "Quality Assurance Analyst",
        "Systems Administrator", "Data Analyst (Junior)"
    ]
    
    for i in range(remaining):
        name = f"{random.choice(first_names)} {random.choice(last_initials)}"
        exp_rand = random.random()
        if exp_rand < 0.4:
            experience = "Beginner"
            error_rate = round(random.uniform(0.35, 0.60), 2)
            attention_span = random.choice(["Low", "Medium"])
            bg = random.choice(backgrounds[:5])
        elif exp_rand < 0.8:
            experience = "Intermediate"
            error_rate = round(random.uniform(0.15, 0.35), 2)
            attention_span = random.choice(["Medium", "High"])
            bg = random.choice(backgrounds[5:])
        else:
            experience = "Expert"
            error_rate = round(random.uniform(0.04, 0.15), 2)
            attention_span = random.choice(["Medium", "High"])
            bg = "Senior Specialist"
            
        if random.random() < 0.2:
            error_rate = min(0.9, error_rate + 0.1)
            bg = f"{bg} (ESL Learner)"
            
        cohort.append(SchemaPersonaProfile(
            name=name,
            experience=experience,
            background=bg,
            attention_span=attention_span,
            error_rate=error_rate
        ))
        
    return cohort


def calculate_standard_deviation(scores: list[float]) -> float:
    if len(scores) <= 1:
        return 0.0
    mean = sum(scores) / len(scores)
    variance = sum((x - mean) ** 2 for x in scores) / (len(scores) - 1)
    import math
    return round(math.sqrt(variance), 1)


async def generate_pedagogical_recommendations(
    module: CurriculumModule,
    results_list: list[dict],
    llm: Optional[Any] = None
) -> list[dict]:
    """Generates actionable pedagogical recommendations using Gemini by analyzing incorrect answers."""
    if not llm:
        return []
    
    # Filter for incorrect results
    failed_results = [r for r in results_list if not r["passed"]]
    if not failed_results:
        return [
            {
                "target": "Course Progression",
                "description": "All learner personas achieved 100% pass rates across all questions.",
                "suggestion": "The current quiz might be too simple. Consider adding higher-level cognitive challenge questions (Analyze, Evaluate, Create level under Bloom's Taxonomy) or introducing more advanced concepts."
            }
        ]
        
    try:
        import json
        from langchain_core.prompts import ChatPromptTemplate
        
        # Prepare text payload to describe the failures to the LLM
        failures_summary = []
        for r in failed_results:
            failures_summary.append(
                f"Persona: {r['persona_name']} ({r['persona_experience']} level, Background: {r['persona_background']})\n"
                f"Question: {r['question_text']}\n"
                f"Bloom's Level: {r['blooms_level']}\n"
                f"Student Choice & Reasoning: {r['response_text']}\n"
                f"Confusion Factor: {r['confusion_signal']}\n"
                f"---"
            )
        failures_str = "\n".join(failures_summary[:15]) # cap at 15 for safety
        
        system_prompt = (
            "You are a professional instructional design consultant and curriculum auditor.\n"
            "You are reviewing the simulation results of three synthetic student personas taking a course module quiz:\n"
            "Module Title: {module_title}\n"
            "Module Content Outline: {module_content}\n\n"
            "Here are the student answers that were marked INCORRECT during simulation:\n"
            "{failures_str}\n\n"
            "Analyze these failure patterns. Identify why they failed (e.g. beginners struggling with complex terms, experts finding phrasing ambiguous, low attention spans misreading distractors).\n"
            "Generate exactly 2 to 3 actionable, highly specific pedagogical recommendations to improve the curriculum or assessment.\n\n"
            "Respond ONLY with a valid JSON array of objects, where each object has this structure:\n"
            "[\n"
            "  {{\n"
            "    \"target\": \"Target Question or Concept Name\",\n"
            "    \"description\": \"A concise description of the failure mode found (e.g., Beginners failed Question 2 due to lack of Scrum definitions in the syllabus content).\",\n"
            "    \"suggestion\": \"Specific, concrete guidance for the course designer (e.g., Add a brief paragraph defining Scrum roles in Module 1 before the quiz, or simplify the options in Question 2).\"\n"
            "  }}\n"
            "]\n"
            "Do not include any other text, explanations, or markdown blocks. Only JSON."
        )
        
        prompt = ChatPromptTemplate.from_messages([
            ("system", system_prompt)
        ])
        
        chain = prompt | llm
        res = await chain.ainvoke({
            "module_title": module.title,
            "module_content": module.content[:1000] if module.content else "No content",
            "failures_str": failures_str
        })
        
        raw = res.content.strip()
        if raw.startswith("```json"):
            raw = raw[7:]
        if raw.endswith("```"):
            raw = raw[:-3]
        raw = raw.strip()
        
        data = json.loads(raw)
        if isinstance(data, list):
            return data
        return []
    except Exception as e:
        logger.error(f"Error generating pedagogical recommendations: {e}", exc_info=True)
        return [
            {
                "target": "Assessment Phrasing",
                "description": "Learners failed due to terminology and conceptual gaps.",
                "suggestion": "Review question options and ensure all tested vocabulary is defined in the module curriculum text before the quiz."
            }
        ]


async def simulate_persona_with_gemini(persona: SchemaPersonaProfile, question: QuizQuestion, llm: Optional[Any] = None) -> Optional[tuple[bool, str, float, str]]:
    """Uses the project-configured LLM (or default) to simulate a student persona answering a question.
    
    Returns:
        (passed, response_text, time_estimate_seconds, confusion_signal) or None if fallback is needed.
    """
    if not llm:
        from app.agents.graph import get_llm
        llm = await get_llm(project_id=question.module.project_id if hasattr(question, "module") and question.module else None)
        
    if not llm:
        return None
        
    try:
        from langchain_core.prompts import ChatPromptTemplate
        import json

        
        system_prompt = (
            "You are a student simulating an exam. You must stay in character as this student persona:\n"
            "Name: {name}\n"
            "Background: {background}\n"
            "Subject Experience Level: {experience}\n"
            "Attention Span: {attention_span}\n"
            "Error Rate (Probability of mistake): {error_rate}\n\n"
            "Here is the multiple choice quiz question you are taking:\n"
            "Question: {question_text}\n"
            "Options: {options}\n\n"
            "Stay in character! A beginner or low attention span student might pick wrong options or get confused by complex terminology. "
            "An expert will almost always get it right but might complain it is too easy.\n"
            "Think about the options strictly based on your background and experience. Speak from the first person in your reasoning.\n\n"
            "Respond ONLY with a valid JSON object of this structure:\n"
            "{{\n"
            "  \"reasoning\": \"Your student persona's internal thoughts and brief explanation of why they chose this answer.\",\n"
            "  \"chosen_option\": \"The exact string value of the option you chose from the list.\",\n"
            "  \"time_taken_seconds\": 4.5,\n"
            "  \"confusion_signal\": \"none\" or \"missing_prerequisite\" or \"careless_mistake\" or \"complex_jargon\" or \"ambiguous_options\"\n"
            "}}\n"
            "Identify 'confusion_signal' as 'none' if you answered correctly. If you chose an incorrect option, identify the closest reason why: "
            "'missing_prerequisite' (lack of baseline concept), 'careless_mistake' (skipped or misread due to low attention span), "
            "'complex_jargon' (confused by hard terms), or 'ambiguous_options' (felt two choices were correct).\n"
            "Provide no other markdown or text outside of the JSON."
        )
        
        prompt = ChatPromptTemplate.from_messages([
            ("system", system_prompt)
        ])
        
        chain = prompt | llm
        options_str = ", ".join([f'"{opt}"' for opt in question.options]) if question.options else "[]"
        res = await chain.ainvoke({
            "name": persona.name,
            "background": persona.background,
            "experience": persona.experience,
            "attention_span": persona.attention_span,
            "error_rate": persona.error_rate,
            "question_text": question.question_text,
            "options": options_str
        })
        
        raw = res.content.strip()
        if raw.startswith("```json"):
            raw = raw[7:]
        if raw.endswith("```"):
            raw = raw[:-3]
        raw = raw.strip()
        
        result_data = json.loads(raw)
        chosen = result_data.get("chosen_option", "").strip()
        reasoning = result_data.get("reasoning", "No explanation provided.")
        time_taken = float(result_data.get("time_taken_seconds", 4.0))
        confusion_sig = result_data.get("confusion_signal", "none").strip().lower()
        
        passed = (chosen.lower() == question.correct_answer.lower())
        if passed:
            confusion_sig = "none"
        elif confusion_sig == "none":
            confusion_sig = "missing_prerequisite"  # Default fallback if wrong but says none
            
        return passed, f"Chose '{chosen}': {reasoning}", time_taken, confusion_sig
    except Exception as e:
        logger.error(f"Error in Gemini persona simulation: {e}", exc_info=True)
        return None


@router.post("/{project_id}/simulations/run", status_code=status.HTTP_201_CREATED)
async def run_simulation(
    project_id: str,
    module_id: Optional[str] = None,
    req: Optional[RunSimulationRequest] = None,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Executes synthetic persona simulation runs against module quiz questions."""
    # Determine the target module ID and personas
    target_module_id = "default"
    active_personas = PERSONAS
    cohort_size = 3
    hourly_wage = 45.0

    if req:
        if req.module_id:
            target_module_id = req.module_id
        if req.personas is not None:
            active_personas = req.personas
        if req.cohort_size is not None:
            cohort_size = req.cohort_size
        if req.hourly_wage is not None:
            hourly_wage = req.hourly_wage
    elif module_id:
        target_module_id = module_id

    # Generate dynamic cohort if cohort_size is set greater than current list size
    if cohort_size > len(active_personas):
        active_personas = generate_cohort(cohort_size, active_personas)

    # 1. Verify project ownership
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    if not proj_result.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )
        
    from app.agents.graph import get_llm
    llm = await get_llm(project_id, db=db)
        
    # 2. Verify module exists or auto-create default if none exists
    module_result = await db.execute(
        select(CurriculumModule).where(
            CurriculumModule.project_id == project_id,
            (CurriculumModule.id == target_module_id) | (target_module_id == "default")
        )
    )
    module = module_result.scalars().first()
    if not module:
        # Check if project has ANY module
        any_module_result = await db.execute(
            select(CurriculumModule).where(CurriculumModule.project_id == project_id)
        )
        module = any_module_result.scalars().first()
        
        if not module:
            # Self-healing: create a default module with sample quiz questions
            module = CurriculumModule(
                project_id=project_id,
                title="Sprint Retrospectives & Continuous Improvement",
                content="Sprint Retrospectives focus on team processes, quality, and collaboration.",
                blooms_level="understand",
                sequence_order=1,
                heatmap_data={}
            )
            db.add(module)
            await db.commit()
            await db.refresh(module)
            
            # Add sample questions to the new module
            sample_questions = [
                QuizQuestion(
                    module_id=module.id,
                    question_text="What is the primary goal of a Sprint Retrospective?",
                    question_type="multiple_choice",
                    options=["Identify process improvements", "Assign blame for failures", "Write status reports", "Plan the next Sprint outline"],
                    correct_answer="Identify process improvements",
                    blooms_level="remember",
                    difficulty=0.3,
                    explanation="Retrospectives are inspect-and-adapt cycles for team process improvements.",
                    sequence_order=1
                ),
                QuizQuestion(
                    module_id=module.id,
                    question_text="How should psychological safety be fostered in a team retrospective?",
                    question_type="multiple_choice",
                    options=["Establish a blameless culture focused on processes", "Publicly rank team members", "Strictly enforce performance targets", "Restrict discussions to status metrics"],
                    correct_answer="Establish a blameless culture focused on processes",
                    blooms_level="apply",
                    difficulty=0.6,
                    explanation="Blameless environments allow open reflection without fear of reprisal.",
                    sequence_order=2
                )
            ]
            db.add_all(sample_questions)
            await db.commit()
            
    # 3. Query questions
    questions_result = await db.execute(
        select(QuizQuestion).where(QuizQuestion.module_id == module.id)
    )
    questions = questions_result.scalars().all()
    
    # 4. Create simulation run record
    run = SimulationRun(
        project_id=project_id,
        session_id=None,
        persona_count=len(active_personas),
        total_questions=len(questions) if questions else 5,
        status="running"
    )
    db.add(run)
    await db.commit()
    await db.refresh(run)
    
    # If there are no questions, generate 5 mock questions to simulate
    simulated_questions = questions if questions else [
        QuizQuestion(id=f"q_{i}", blooms_level=bl_level, question_text=f"Sample Question {i}", options=["A", "B", "C", "D"], correct_answer="A")
        for i, bl_level in enumerate(["remember", "understand", "apply", "analyze", "evaluate"])
    ]
    
    logs = ["Initializing simulation environment..."]
    pass_rates = {p.name: 0 for p in active_personas}
    bloom_heatmap = {"Remember": 0.0, "Understand": 0.0, "Apply": 0.0, "Analyze": 0.0, "Evaluate": 0.0, "Create": 0.0}
    
    # Count totals per bloom level for averaging
    bloom_counts = {"Remember": 0, "Understand": 0, "Apply": 0, "Analyze": 0, "Evaluate": 0, "Create": 0}
    
    results_for_recs = []
    
    # Initialize failure counter for questions
    question_failures = {
        (q.id if not str(q.id).startswith("q_") else f"q_{idx+1}"): 0
        for idx, q in enumerate(simulated_questions)
    }
    
    # Store times spent for average speed
    total_time_spent = 0.0
    total_responses_count = 0
    
    for idx, q in enumerate(simulated_questions):
        q_idx = idx + 1
        q_bloom = (q.blooms_level or "understand").capitalize()
        if q_bloom not in bloom_heatmap:
            q_bloom = "Understand"
            
        logs.append(f"📝 Testing Question {q_idx}: {q.question_text[:50]}...")
        bloom_counts[q_bloom] += 1
        
        q_key = q.id if not str(q.id).startswith("q_") else f"q_{q_idx}"
        
        # Determine success for each persona
        for p in active_personas:
            # Optimize LLM cost/latencies: only call LLM for core template personas
            is_core = p.name in ["Alex", "Sofia", "Jordan"]
            
            gemini_res = None
            if is_core:
                gemini_res = await simulate_persona_with_gemini(p, q, llm=llm)
                
            if gemini_res is not None:
                is_correct, response_desc, time_spent, confusion_sig = gemini_res
            else:
                # Statistical fallback mapping demographics to scoring
                is_correct = random.random() > p.error_rate
                
                # Penalty for harder levels and low experience
                if q.blooms_level in ["apply", "analyze", "evaluate", "create"] and p.experience == "Beginner":
                    is_correct = random.random() > (p.error_rate + 0.25)
                
                # Penalty for language barrier
                if "ESL" in p.background and not is_correct:
                    is_correct = random.random() > (p.error_rate + 0.1)
                    
                time_spent = round(random.uniform(1.0, 5.0) if is_correct else random.uniform(3.0, 10.0), 1)
                
                if is_correct:
                    confusion_sig = "none"
                    response_desc = f"Correct - Synthesized options correctly based on {p.experience.lower()} experience."
                else:
                    signals = ["complex_jargon", "missing_prerequisite", "careless_mistake", "ambiguous_options"]
                    confusion_sig = random.choice(signals)
                    if p.experience == "Beginner":
                        confusion_sig = "complex_jargon"
                    elif p.attention_span == "Low":
                        confusion_sig = "careless_mistake"
                    
                    reasons = {
                        "complex_jargon": "Confused by advanced terminology and acronyms.",
                        "missing_prerequisite": "Struggled with cognitive leaps lacking foundation scaffolding.",
                        "careless_mistake": "Failed to read all options due to attention exhaustion.",
                        "ambiguous_options": "Torn between two highly similar distractor options."
                    }
                    response_desc = f"Incorrect - {reasons[confusion_sig]}"
            
            total_time_spent += time_spent
            total_responses_count += 1
            
            if is_correct:
                pass_rates[p.name] += 1
                bloom_heatmap[q_bloom] += 1.0
            else:
                question_failures[q_key] += 1
                
            # Log results
            status_symbol = "✅" if is_correct else "❌"
            logs.append(f"  {status_symbol} {p.name} ({p.experience}): {response_desc} ({time_spent}s)")
            
            # Keep track for recommendations
            results_for_recs.append({
                "persona_name": p.name,
                "persona_experience": p.experience,
                "persona_background": p.background,
                "question_text": q.question_text,
                "blooms_level": q.blooms_level or "understand",
                "passed": is_correct,
                "response_text": response_desc,
                "confusion_signal": confusion_sig
            })
            
            # Save results
            p_result = PersonaResult(
                run_id=run.id,
                persona_profile=p.model_dump(),
                module_id=module.id,
                question_id=q.id if not str(q.id).startswith("q_") else None,
                passed=is_correct,
                response_text=response_desc,
                confusion_signal=confusion_sig,
                time_estimate_seconds=time_spent
            )
            db.add(p_result)
            
    # Calculate final averages
    final_pass_rates = {}
    for p in active_personas:
        final_pass_rates[p.name] = int((pass_rates[p.name] / len(simulated_questions)) * 100) if simulated_questions else 0
        
    for k in bloom_heatmap.keys():
        total_for_level = bloom_counts[k] * len(active_personas)
        if total_for_level > 0:
            bloom_heatmap[k] = round(bloom_heatmap[k] / total_for_level, 2)
        else:
            fallbacks = {"Remember": 0.90, "Understand": 0.80, "Apply": 0.70, "Analyze": 0.55, "Evaluate": 0.40, "Create": 0.30}
            bloom_heatmap[k] = fallbacks[k]
            
    logs.append("🎉 Classroom simulation finished. Calculating scores...")
    
    # Generate recommendations
    logs.append("💡 Generating pedagogical recommendations...")
    recs = await generate_pedagogical_recommendations(module, results_for_recs, llm=llm)
    
    # Calculate Standard Deviation of percentages
    student_pcts = [final_pass_rates[p.name] for p in active_personas]
    standard_deviation = calculate_standard_deviation(student_pcts)
    
    # Calculate failure rates per question
    q_failure_rates = {}
    for q_key, fails in question_failures.items():
        q_failure_rates[q_key] = round((fails / len(active_personas)) * 100, 1) if active_personas else 0.0
        
    # Calculate ROI cost savings
    hours_saved = 15.0
    passing_students = sum(1 for p in active_personas if (pass_rates[p.name]/len(simulated_questions)) >= 0.70)
    pass_rate_factor = passing_students / len(active_personas) if active_personas else 0.0
    roi_savings = round(len(active_personas) * hours_saved * hourly_wage * pass_rate_factor, 2)
    
    # Average response time
    avg_response_time = round(total_time_spent / total_responses_count, 1) if total_responses_count > 0 else 0.0
    
    # Update run record
    run.meta = {
        "pass_rates": final_pass_rates,
        "bloom_heatmap": bloom_heatmap,
        "recommendations": recs,
        "logs": logs,
        "cohort_size": len(active_personas),
        "standard_deviation": standard_deviation,
        "average_response_time": avg_response_time,
        "predicted_roi_savings": roi_savings,
        "question_failure_rates": q_failure_rates
    }
    run.status = "completed"
    run.completed_at = datetime.utcnow()
    
    await db.commit()
    await db.refresh(run)
    
    return {
        "run_id": run.id,
        "logs": logs,
        "pass_rates": final_pass_rates,
        "bloom_heatmap": bloom_heatmap,
        "cohort_size": len(active_personas),
        "standard_deviation": standard_deviation,
        "average_response_time": avg_response_time,
        "predicted_roi_savings": roi_savings,
        "question_failure_rates": q_failure_rates
    }


@router.post("/{project_id}/simulate", status_code=status.HTTP_201_CREATED)
async def run_simulation_legacy(
    project_id: str,
    req: Optional[RunSimulationRequest] = None,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Legacy redirect endpoint for simulations to support integration tests."""
    return await run_simulation(project_id, None, req, user_id, db)


@router.get("/{project_id}/simulations", response_model=list[SimulationRunResponse])
async def list_simulations(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Retrieves all simulation runs for a given project."""
    # 1. Verify project ownership
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    if not proj_result.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )

    # 2. Query simulation runs
    runs_result = await db.execute(
        select(SimulationRun)
        .where(SimulationRun.project_id == project_id)
        .order_by(SimulationRun.started_at.desc())
    )
    return runs_result.scalars().all()


@router.get("/{project_id}/simulations/{run_id}", response_model=SimulationRunDetailResponse)
async def get_simulation_run(
    project_id: str,
    run_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Retrieves detailed results for a specific simulation run, including question-by-question breakdown."""
    from sqlalchemy.orm import selectinload

    # 1. Verify project ownership
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    if not proj_result.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Project not found or unauthorized access"
        )

    # 2. Query simulation run details with eager-loaded persona results
    run_result = await db.execute(
        select(SimulationRun)
        .options(selectinload(SimulationRun.persona_results))
        .where(SimulationRun.id == run_id, SimulationRun.project_id == project_id)
    )
    run = run_result.scalars().first()
    if not run:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Simulation run not found"
        )
        
    return run

