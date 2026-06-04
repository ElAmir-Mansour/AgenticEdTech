import io
import zipfile
import logging
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.database import get_db
from app.models.database import Project, CurriculumModule, QuizQuestion
from app.auth.dependencies import get_current_user_id

router = APIRouter()
logger = logging.getLogger(__name__)

@router.get("/{project_id}/export/scorm")
async def export_scorm(
    project_id: str,
    module_id: str = "default",
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Generates and returns a SCORM 1.2 compliant ZIP package containing curriculum HTML and quiz content."""
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
        
    # Get all modules for multi-SCO checking
    modules_res = await db.execute(
        select(CurriculumModule).where(CurriculumModule.project_id == project_id).order_by(CurriculumModule.sequence_order)
    )
    modules = modules_res.scalars().all()
    
    if not modules:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No curriculum module found to export. Please create one on the canvas first."
        )
        
    # Check if we should export as multi-SCO (more than 1 module exists, and target is default/all)
    if len(modules) > 1 and module_id in ["default", "all"]:
        zip_buffer = io.BytesIO()
        
        with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
            # Generate multi-SCO manifest
            manifest_content = generate_multi_scorm_manifest(project.title, modules)
            zip_file.writestr("imsmanifest.xml", manifest_content)
            
            # Add HTML page for each module
            for idx, mod in enumerate(modules):
                questions_res = await db.execute(
                    select(QuizQuestion).where(QuizQuestion.module_id == mod.id)
                )
                questions = questions_res.scalars().all()
                lesson_content = generate_lesson_html(mod.title, mod.content, questions)
                filename = f"module_{idx + 1}.html"
                zip_file.writestr(filename, lesson_content)
                
        zip_buffer.seek(0)
        filename = f"{project.title.lower().replace(' ', '_')}_course_scorm12.zip"
        return StreamingResponse(
            zip_buffer,
            media_type="application/zip",
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )
        
    # Otherwise, export a single SCO package
    if module_id == "default" or module_id == "all":
        module = modules[0]
    else:
        module_result = await db.execute(
            select(CurriculumModule).where(
                CurriculumModule.project_id == project_id,
                CurriculumModule.id == module_id
            )
        )
        module = module_result.scalars().first()
        if not module:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Requested module not found."
            )
        
    # Get quiz questions for this single module
    questions_res = await db.execute(
        select(QuizQuestion).where(QuizQuestion.module_id == module.id)
    )
    questions = questions_res.scalars().all()
    
    # Generate dynamic SCORM files in-memory
    zip_buffer = io.BytesIO()
    
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
        # Add manifest file
        manifest_content = generate_scorm_manifest(module.title)
        zip_file.writestr("imsmanifest.xml", manifest_content)
        
        # Add lesson content HTML page
        lesson_content = generate_lesson_html(module.title, module.content, questions)
        zip_file.writestr("index.html", lesson_content)
        
    zip_buffer.seek(0)
    
    filename = f"{module.title.lower().replace(' ', '_')}_scorm12.zip"
    return StreamingResponse(
        zip_buffer,
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


# --- TEMPLATE GENERATORS ---

def generate_scorm_manifest(title: str) -> str:
    """Creates a valid SCORM 1.2 imsmanifest.xml metadata package descriptor."""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<manifest identifier="manifest_agentic_edtech" version="1.1"
          xmlns="http://www.imsproject.org/xsd/imscp_rootv1p1p2"
          xmlns:adlcp="http://www.adlnet.org/xsd/adlcp_rootv1p2"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://www.imsproject.org/xsd/imscp_rootv1p1p2 imscp_rootv1p1p2.xsd
                              http://www.adlnet.org/xsd/adlcp_rootv1p2 adlcp_rootv1p2.xsd">
  <metadata>
    <schema>ADL SCORM</schema>
    <schemaversion>1.2</schemaversion>
  </metadata>
  <organizations default="org_agentic">
    <organization identifier="org_agentic">
      <title>{title}</title>
      <item identifier="item_1" identifierref="resource_1">
        <title>Start Lesson</title>
      </item>
    </organization>
  </organizations>
  <resources>
    <resource identifier="resource_1" type="webcontent" adlcp:scormtype="sco" href="index.html">
      <file href="index.html"/>
    </resource>
  </resources>
</manifest>
"""


def generate_multi_scorm_manifest(project_title: str, modules: list) -> str:
    """Creates a valid SCORM 1.2 imsmanifest.xml metadata package descriptor for multiple SCOs (modules)."""
    items_xml = ""
    resources_xml = ""
    
    for idx, mod in enumerate(modules):
        item_id = f"item_{idx + 1}"
        res_id = f"resource_{idx + 1}"
        href = f"module_{idx + 1}.html"
        items_xml += f"""      <item identifier="{item_id}" identifierref="{res_id}">
        <title>{mod.title}</title>
      </item>\n"""
        resources_xml += f"""    <resource identifier="{res_id}" type="webcontent" adlcp:scormtype="sco" href="{href}">
      <file href="{href}"/>
    </resource>\n"""
        
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<manifest identifier="manifest_agentic_edtech" version="1.1"
          xmlns="http://www.imsproject.org/xsd/imscp_rootv1p1p2"
          xmlns:adlcp="http://www.adlnet.org/xsd/adlcp_rootv1p2"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://www.imsproject.org/xsd/imscp_rootv1p1p2 imscp_rootv1p1p2.xsd
                              http://www.adlnet.org/xsd/adlcp_rootv1p2 adlcp_rootv1p2.xsd">
  <metadata>
    <schema>ADL SCORM</schema>
    <schemaversion>1.2</schemaversion>
  </metadata>
  <organizations default="org_agentic">
    <organization identifier="org_agentic">
      <title>{project_title}</title>
{items_xml}    </organization>
  </organizations>
  <resources>
{resources_xml}  </resources>
</manifest>
"""


PREMIUM_CSS = """
        :root {
            --brand-primary: #6366f1; /* Indigo */
            --brand-secondary: #4f46e5;
            --brand-light: #818cf8;
            --success: #10b981;
            --success-light: #d1fae5;
            --warning: #f59e0b;
            --danger: #ef4444;
            --bg-page: #f8fafc;
            --bg-card: #ffffff;
            --text-main: #1e293b;
            --text-muted: #64748b;
            --border-color: #e2e8f0;
        }
        body {
            font-family: 'Inter', -apple-system, sans-serif;
            background-color: var(--bg-page);
            color: var(--text-main);
            line-height: 1.7;
            margin: 0;
            padding: 0;
        }
        .container {
            max-width: 800px;
            margin: 40px auto;
            padding: 0 24px;
        }
        .card {
            background-color: var(--bg-card);
            border-radius: 16px;
            box-shadow: 0 4px 6px -1px rgba(0,0,0,0.05), 0 2px 4px -2px rgba(0,0,0,0.05);
            border: 1px solid var(--border-color);
            padding: 32px;
            margin-bottom: 24px;
        }
        h1, h2, h3 {
            font-weight: 700;
            color: #0f172a;
            margin-top: 0;
        }
        h1 {
            font-size: 2.25rem;
            border-bottom: 2px solid var(--border-color);
            padding-bottom: 12px;
            color: var(--brand-primary);
        }
        h2 {
            font-size: 1.5rem;
            margin-top: 32px;
            margin-bottom: 16px;
        }
        p {
            margin-bottom: 1.25rem;
        }
        code {
            background-color: #f1f5f9;
            color: #e11d48;
            padding: 2px 6px;
            border-radius: 6px;
            font-family: 'Courier New', Courier, monospace;
            font-size: 0.9em;
        }
        pre {
            background-color: #0f172a;
            color: #f8fafc;
            padding: 16px;
            border-radius: 12px;
            overflow-x: auto;
        }
        pre code {
            background-color: transparent;
            color: inherit;
            padding: 0;
        }
        .badge {
            display: inline-block;
            padding: 4px 12px;
            font-size: 0.75rem;
            font-weight: 600;
            border-radius: 9999px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 16px;
        }
        .badge-blooms {
            background-color: #e0e7ff;
            color: var(--brand-primary);
        }
        /* Quiz Styles */
        .quiz-title {
            font-size: 1.25rem;
            font-weight: 600;
            margin-bottom: 20px;
        }
        .quiz-question-box {
            background-color: #f8fafc;
            border-left: 4px solid var(--brand-primary);
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .quiz-option {
            display: flex;
            align-items: center;
            background-color: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 12px 16px;
            margin: 8px 0;
            cursor: pointer;
            transition: all 0.2s ease;
        }
        .quiz-option:hover {
            border-color: var(--brand-light);
            background-color: #f5f3ff;
        }
        .quiz-option input[type="radio"] {
            margin-right: 12px;
            accent-color: var(--brand-primary);
        }
        .quiz-submit-btn {
            background-color: var(--brand-primary);
            color: white;
            font-weight: 600;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            cursor: pointer;
            transition: background-color 0.2s ease;
        }
        .quiz-submit-btn:hover {
            background-color: var(--brand-secondary);
        }
"""

def generate_lesson_html(title: str, content: str, questions: list[QuizQuestion]) -> str:
    """Generates a complete course page with SCORM 1.2 API communications and quiz evaluation scripts."""
    quiz_html = ""
    quiz_js = ""
    
    if questions:
        quiz_html = """
        <div class="card">
            <h2 class="quiz-title">Knowledge Check</h2>
            <div id="quiz-container">
        """
        for idx, q in enumerate(questions):
            q_num = idx + 1
            opts_html = "".join([
                f'<label class="quiz-option"><input type="radio" name="q{q_num}" value="{opt}"> <span>{opt}</span></label>'
                for opt in (q.options or [])
            ])
            quiz_html += f"""
            <div class="quiz-question-box">
                <p><strong>Q{q_num}: {q.question_text}</strong></p>
                {opts_html}
            </div>
            """
        quiz_html += """
                <button onclick="submitQuiz()" class="quiz-submit-btn">Submit Quiz</button>
            </div>
        </div>
        """
        
        ans_array = ", ".join([f'"{q.correct_answer}"' for q in questions])
        quiz_js = f"""
        var correctAnswers = [{ans_array}];
        
        function submitQuiz() {{
            var score = 0;
            for(var i=1; i<=correctAnswers.length; i++) {{
                var selected = document.querySelector('input[name="q' + i + '"]:checked');
                if (selected && selected.value === correctAnswers[i-1]) {{
                    score++;
                }}
            }}
            var percentage = Math.round((score / correctAnswers.length) * 100);
            alert("You scored: " + percentage + "%");
            
            if(scormAPI) {{
                scormAPI.LMSSetValue("cmi.core.score.raw", percentage.toString());
                scormAPI.LMSSetValue("cmi.core.score.min", "0");
                scormAPI.LMSSetValue("cmi.core.score.max", "100");
                if (percentage >= 70) {{
                    scormAPI.LMSSetValue("cmi.core.lesson_status", "passed");
                }} else {{
                    scormAPI.LMSSetValue("cmi.core.lesson_status", "failed");
                }}
                scormAPI.LMSCommit("");
            }}
        }}
        """
        
    clean_content = content.replace('\n', '<br>')
    return f"""<!DOCTYPE html>
<html>
<head>
    <title>{title}</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        {PREMIUM_CSS}
    </style>
    <script>
        // Find SCORM API
        var scormAPI = null;
        function findAPI(win) {{
            var findAttempts = 0;
            while ((win.API == null) && (win.parent != null) && (win.parent != win)) {{
                findAttempts++;
                if (findAttempts > 500) return null;
                win = win.parent;
            }}
            return win.API;
        }}
        
        window.onload = function() {{
            scormAPI = findAPI(window);
            if (scormAPI) {{
                scormAPI.LMSInitialize("");
                scormAPI.LMSSetValue("cmi.core.lesson_status", "incomplete");
                scormAPI.LMSCommit("");
            }}
        }};
        
        window.onunload = function() {{
            if (scormAPI) {{
                scormAPI.LMSSetValue("cmi.core.exit", "suspend");
                scormAPI.LMSFinish("");
            }}
        }};
        
        {quiz_js}
    </script>
</head>
<body>
    <div class="container">
        <div class="card">
            <h1>{title}</h1>
            <div>
                {clean_content}
            </div>
        </div>
        {quiz_html}
    </div>
</body>
</html>
"""


# ═══════════════════════════════════════════════════════════════════════
# SCORM 2004 Export
# ═══════════════════════════════════════════════════════════════════════

@router.get("/{project_id}/export/scorm2004")
async def export_scorm_2004(
    project_id: str,
    module_id: str = "default",
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Generates a SCORM 2004 3rd Edition compliant ZIP package.
    
    SCORM 2004 uses the ADL Sequencing & Navigation model and
    a different API (API_1484_11) compared to SCORM 1.2.
    """
    # Verify project ownership
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")
        
    # Get all modules for multi-SCO checking
    modules_res = await db.execute(
        select(CurriculumModule).where(CurriculumModule.project_id == project_id).order_by(CurriculumModule.sequence_order)
    )
    modules = modules_res.scalars().all()
    
    if not modules:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No curriculum module found to export."
        )
        
    # Check if we should export as multi-SCO (more than 1 module exists, and target is default/all)
    if len(modules) > 1 and module_id in ["default", "all"]:
        zip_buffer = io.BytesIO()
        
        with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
            # Generate multi-SCO manifest
            manifest_content = _scorm2004_multi_manifest(project.title, modules)
            zip_file.writestr("imsmanifest.xml", manifest_content)
            
            # Add HTML page for each module
            for idx, mod in enumerate(modules):
                questions_res = await db.execute(
                    select(QuizQuestion).where(QuizQuestion.module_id == mod.id)
                )
                questions = questions_res.scalars().all()
                lesson_content = _scorm2004_lesson_html(mod.title, mod.content, questions)
                filename = f"module_{idx + 1}.html"
                zip_file.writestr(filename, lesson_content)
                
            zip_file.writestr("adlcp_rootv1p3.xsd", "<!-- SCORM 2004 schema placeholder -->")
            
        zip_buffer.seek(0)
        filename = f"{project.title.lower().replace(' ', '_')}_course_scorm2004.zip"
        return StreamingResponse(
            zip_buffer,
            media_type="application/zip",
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )
        
    # Otherwise, export a single SCO package
    if module_id == "default" or module_id == "all":
        module = modules[0]
    else:
        module_result = await db.execute(
            select(CurriculumModule).where(
                CurriculumModule.project_id == project_id,
                CurriculumModule.id == module_id
            )
        )
        module = module_result.scalars().first()
        if not module:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Requested module not found.")
            
    # Get quiz questions for this single module
    questions_res = await db.execute(
        select(QuizQuestion).where(QuizQuestion.module_id == module.id)
    )
    questions = questions_res.scalars().all()
    
    # Generate SCORM 2004 ZIP
    zip_buffer = io.BytesIO()
    
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
        zip_file.writestr("imsmanifest.xml", _scorm2004_manifest(module.title))
        zip_file.writestr("index.html", _scorm2004_lesson_html(module.title, module.content, questions))
        zip_file.writestr("adlcp_rootv1p3.xsd", "<!-- SCORM 2004 schema placeholder -->")
    
    zip_buffer.seek(0)
    filename = f"{module.title.lower().replace(' ', '_')}_scorm2004.zip"
    return StreamingResponse(
        zip_buffer,
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


def _scorm2004_manifest(title: str) -> str:
    """Creates a SCORM 2004 3rd Edition imsmanifest.xml."""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<manifest identifier="manifest_agentic_edtech_2004" version="1.3"
          xmlns="http://www.imsglobal.org/xsd/imscp_v1p1"
          xmlns:adlcp="http://www.adlnet.org/xsd/adlcp_v1p3"
          xmlns:adlseq="http://www.adlnet.org/xsd/adlseq_v1p3"
          xmlns:adlnav="http://www.adlnet.org/xsd/adlnav_v1p3"
          xmlns:imsss="http://www.imsglobal.org/xsd/imsss"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://www.imsglobal.org/xsd/imscp_v1p1 imscp_v1p1.xsd
                              http://www.adlnet.org/xsd/adlcp_v1p3 adlcp_v1p3.xsd
                              http://www.adlnet.org/xsd/adlseq_v1p3 adlseq_v1p3.xsd
                              http://www.adlnet.org/xsd/adlnav_v1p3 adlnav_v1p3.xsd
                              http://www.imsglobal.org/xsd/imsss imsss_v1p0.xsd">
  <metadata>
    <schema>ADL SCORM</schema>
    <schemaversion>2004 3rd Edition</schemaversion>
  </metadata>
  <organizations default="org_agentic">
    <organization identifier="org_agentic">
      <title>{title}</title>
      <item identifier="item_1" identifierref="resource_1">
        <title>Start Lesson</title>
        <imsss:sequencing>
          <imsss:deliveryControls completionSetByContent="true" objectiveSetByContent="true"/>
        </imsss:sequencing>
      </item>
      <imsss:sequencing>
        <imsss:controlMode choice="true" flow="true"/>
      </imsss:sequencing>
    </organization>
  </organizations>
  <resources>
    <resource identifier="resource_1" type="webcontent" adlcp:scormType="sco" href="index.html">
      <file href="index.html"/>
    </resource>
  </resources>
</manifest>
"""


def _scorm2004_multi_manifest(project_title: str, modules: list) -> str:
    """Creates a valid SCORM 2004 3rd Edition imsmanifest.xml metadata package descriptor for multiple SCOs."""
    items_xml = ""
    resources_xml = ""
    
    for idx, mod in enumerate(modules):
        item_id = f"item_{idx + 1}"
        res_id = f"resource_{idx + 1}"
        href = f"module_{idx + 1}.html"
        items_xml += f"""      <item identifier="{item_id}" identifierref="{res_id}">
        <title>{mod.title}</title>
        <imsss:sequencing>
          <imsss:deliveryControls completionSetByContent="true" objectiveSetByContent="true"/>
        </imsss:sequencing>
      </item>\n"""
        resources_xml += f"""    <resource identifier="{res_id}" type="webcontent" adlcp:scormType="sco" href="{href}">
      <file href="{href}"/>
    </resource>\n"""
        
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<manifest identifier="manifest_agentic_edtech_2004" version="1.3"
          xmlns="http://www.imsglobal.org/xsd/imscp_v1p1"
          xmlns:adlcp="http://www.adlnet.org/xsd/adlcp_v1p3"
          xmlns:adlseq="http://www.adlnet.org/xsd/adlseq_v1p3"
          xmlns:adlnav="http://www.adlnet.org/xsd/adlnav_v1p3"
          xmlns:imsss="http://www.imsglobal.org/xsd/imsss"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://www.imsglobal.org/xsd/imscp_v1p1 imscp_v1p1.xsd
                              http://www.adlnet.org/xsd/adlcp_v1p3 adlcp_v1p3.xsd
                              http://www.adlnet.org/xsd/adlseq_v1p3 adlseq_v1p3.xsd
                              http://www.adlnet.org/xsd/adlnav_v1p3 adlnav_v1p3.xsd
                              http://www.imsglobal.org/xsd/imsss imsss_v1p0.xsd">
  <metadata>
    <schema>ADL SCORM</schema>
    <schemaversion>2004 3rd Edition</schemaversion>
  </metadata>
  <organizations default="org_agentic">
    <organization identifier="org_agentic">
      <title>{project_title}</title>
{items_xml}      <imsss:sequencing>
        <imsss:controlMode choice="true" flow="true"/>
      </imsss:sequencing>
    </organization>
  </organizations>
  <resources>
{resources_xml}  </resources>
</manifest>
"""


def _scorm2004_lesson_html(title: str, content: str, questions: list[QuizQuestion]) -> str:
    """Generates SCORM 2004 lesson HTML using the API_1484_11 interface with premium styling."""
    quiz_html = ""
    quiz_js = ""
    
    if questions:
        quiz_html = """
        <div class="card">
            <h2 class="quiz-title">Knowledge Check</h2>
            <div id="quiz-container">
        """
        for idx, q in enumerate(questions):
            q_num = idx + 1
            opts_html = "".join([
                f'<label class="quiz-option"><input type="radio" name="q{q_num}" value="{opt}"> <span>{opt}</span></label>'
                for opt in (q.options or [])
            ])
            quiz_html += f"""
            <div class="quiz-question-box">
                <p><strong>Q{q_num}: {q.question_text}</strong></p>
                {opts_html}
            </div>
            """
        quiz_html += """
                <button onclick="submitQuiz()" class="quiz-submit-btn">Submit Quiz</button>
            </div>
        </div>
        """
        
        ans_array = ", ".join([f'"{q.correct_answer}"' for q in questions])
        quiz_js = f"""
        var correctAnswers = [{ans_array}];
        function submitQuiz() {{
            var score = 0;
            for(var i=1; i<=correctAnswers.length; i++) {{
                var selected = document.querySelector('input[name="q' + i + '"]:checked');
                if (selected && selected.value === correctAnswers[i-1]) {{ score++; }}
            }}
            var percentage = Math.round((score / correctAnswers.length) * 100);
            alert("You scored: " + percentage + "%");
            if(scormAPI) {{
                scormAPI.SetValue("cmi.score.raw", percentage.toString());
                scormAPI.SetValue("cmi.score.min", "0");
                scormAPI.SetValue("cmi.score.max", "100");
                scormAPI.SetValue("cmi.score.scaled", (percentage/100).toString());
                scormAPI.SetValue("cmi.success_status", percentage >= 70 ? "passed" : "failed");
                scormAPI.SetValue("cmi.completion_status", "completed");
                scormAPI.Commit("");
            }}
        }}"""
    
    clean_content = content.replace('\n', '<br>')
    return f"""<!DOCTYPE html>
<html>
<head>
    <title>{title}</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        {PREMIUM_CSS}
    </style>
    <script>
        var scormAPI = null;
        function findAPI(win) {{
            var attempts = 0;
            while (!win.API_1484_11 && win.parent && win.parent != win && attempts < 500) {{
                attempts++; win = win.parent;
            }}
            return win.API_1484_11 || null;
        }}
        window.onload = function() {{
            scormAPI = findAPI(window);
            if(scormAPI) {{
                scormAPI.Initialize("");
                scormAPI.SetValue("cmi.completion_status", "incomplete");
                scormAPI.Commit("");
            }}
        }};
        window.onunload = function() {{
            if(scormAPI) {{ scormAPI.SetValue("cmi.exit", "suspend"); scormAPI.Terminate(""); }}
        }};
        {quiz_js}
    </script>
</head>
<body>
    <div class="container">
        <div class="card">
            <h1>{title}</h1>
            <div>{clean_content}</div>
        </div>
        {quiz_html}
    </div>
</body>
</html>"""


# ═══════════════════════════════════════════════════════════════════════
# xAPI Statement Generator
# ═══════════════════════════════════════════════════════════════════════

@router.post("/{project_id}/export/xapi")
async def generate_xapi_statements(
    project_id: str,
    payload: dict = {},
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Generates xAPI (Experience API / Tin Can) statements for a project's simulation results.
    
    Returns JSON-LD formatted xAPI statements ready for submission to an LRS
    (Learning Record Store).
    """
    from datetime import datetime, timezone
    
    # Verify project
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")
    
    # Get simulation results
    from app.models.database import SimulationRun, PersonaResult
    
    sim_result = await db.execute(
        select(SimulationRun).where(SimulationRun.project_id == project_id)
    )
    runs = sim_result.scalars().all()
    
    statements = []
    
    if runs:
        for run in runs:
            persona_q = await db.execute(
                select(PersonaResult).where(PersonaResult.run_id == run.id)
            )
            persona_results = persona_q.scalars().all()
            
            for pr in persona_results:
                profile = pr.persona_profile if isinstance(pr.persona_profile, dict) else {}
                persona_name = profile.get("name", "Unknown Learner")
                
                # Build xAPI statement
                statement = {
                    "actor": {
                        "objectType": "Agent",
                        "name": persona_name,
                        "mbox": f"mailto:{persona_name.lower().replace(' ', '_')}@simulated.edtech.local"
                    },
                    "verb": {
                        "id": "http://adlnet.gov/expapi/verbs/answered" if pr.question_id else "http://adlnet.gov/expapi/verbs/attempted",
                        "display": {"en-US": "answered" if pr.question_id else "attempted"}
                    },
                    "object": {
                        "objectType": "Activity",
                        "id": f"urn:agentic-edtech:project:{project_id}:module:{pr.module_id}",
                        "definition": {
                            "type": "http://adlnet.gov/expapi/activities/assessment",
                            "name": {"en-US": f"Quiz Question ({project.title})"},
                            "description": {"en-US": pr.response_text or "Simulated assessment response"}
                        }
                    },
                    "result": {
                        "success": pr.passed,
                        "completion": True,
                        "response": pr.response_text or "",
                        "duration": f"PT{int(pr.time_estimate_seconds or 0)}S",
                        "extensions": {
                            "http://agentic-edtech.local/extensions/confusion_signal": pr.confusion_signal or "",
                            "http://agentic-edtech.local/extensions/persona_experience": profile.get("experience", ""),
                        }
                    },
                    "timestamp": (pr.created_at or datetime.now(timezone.utc)).isoformat(),
                    "context": {
                        "contextActivities": {
                            "parent": [{
                                "objectType": "Activity",
                                "id": f"urn:agentic-edtech:project:{project_id}",
                                "definition": {
                                    "type": "http://adlnet.gov/expapi/activities/course",
                                    "name": {"en-US": project.title}
                                }
                            }]
                        },
                        "extensions": {
                            "http://agentic-edtech.local/extensions/simulation_run_id": run.id,
                        }
                    }
                }
                statements.append(statement)
    else:
        # Fallback: if no simulation runs have been executed yet, generate virtual statements
        # based on the project's curriculum modules and quiz questions.
        from app.models.database import CurriculumModule, QuizQuestion
        import random
        
        modules_res = await db.execute(
            select(CurriculumModule).where(CurriculumModule.project_id == project_id).order_by(CurriculumModule.sequence_order)
        )
        modules = modules_res.scalars().all()
        
        personas = [
            {"name": "Alex", "experience": "Beginner", "error_rate": 0.45},
            {"name": "Sofia", "experience": "Intermediate", "error_rate": 0.18},
            {"name": "Jordan", "experience": "Expert", "error_rate": 0.08},
        ]
        
        for mod in modules:
            questions_res = await db.execute(
                select(QuizQuestion).where(QuizQuestion.module_id == mod.id)
            )
            questions = questions_res.scalars().all()
            
            for p in personas:
                # 1. Generate a module completed statement
                completed_statement = {
                    "actor": {
                        "objectType": "Agent",
                        "name": p["name"],
                        "mbox": f"mailto:{p['name'].lower()}@simulated.edtech.local"
                    },
                    "verb": {
                        "id": "http://adlnet.gov/expapi/verbs/completed",
                        "display": {"en-US": "completed"}
                    },
                    "object": {
                        "objectType": "Activity",
                        "id": f"urn:agentic-edtech:project:{project_id}:module:{mod.id}",
                        "definition": {
                            "type": "http://adlnet.gov/expapi/activities/module",
                            "name": {"en-US": mod.title},
                            "description": {"en-US": "Curriculum reading module completed"}
                        }
                    },
                    "result": {
                        "success": True,
                        "completion": True,
                        "duration": "PT300S",
                        "extensions": {
                            "http://agentic-edtech.local/extensions/persona_experience": p["experience"],
                        }
                    },
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "context": {
                        "contextActivities": {
                            "parent": [{
                                "objectType": "Activity",
                                "id": f"urn:agentic-edtech:project:{project_id}",
                                "definition": {
                                    "type": "http://adlnet.gov/expapi/activities/course",
                                    "name": {"en-US": project.title}
                                }
                            }]
                        }
                    }
                }
                statements.append(completed_statement)
                
                # 2. Generate a statement for each answered question
                for q in questions:
                    passed = random.random() > p["error_rate"]
                    wrong_option = q.options[0] if q.options else "wrong option"
                    response_text = f"Chose option: {q.correct_answer if passed else wrong_option}"
                    time_spent = round(random.uniform(2.0, 10.0), 1)
                    
                    question_statement = {
                        "actor": {
                            "objectType": "Agent",
                            "name": p["name"],
                            "mbox": f"mailto:{p['name'].lower()}@simulated.edtech.local"
                        },
                        "verb": {
                            "id": "http://adlnet.gov/expapi/verbs/answered",
                            "display": {"en-US": "answered"}
                        },
                        "object": {
                            "objectType": "Activity",
                            "id": f"urn:agentic-edtech:project:{project_id}:module:{mod.id}:question:{q.id}",
                            "definition": {
                                "type": "http://adlnet.gov/expapi/activities/assessment",
                                "name": {"en-US": f"Quiz Question ({project.title})"},
                                "description": {"en-US": q.question_text}
                            }
                        },
                        "result": {
                            "success": passed,
                            "completion": True,
                            "response": response_text,
                            "duration": f"PT{int(time_spent)}S",
                            "extensions": {
                                "http://agentic-edtech.local/extensions/persona_experience": p["experience"],
                            }
                        },
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                        "context": {
                            "contextActivities": {
                                "parent": [{
                                    "objectType": "Activity",
                                    "id": f"urn:agentic-edtech:project:{project_id}",
                                    "definition": {
                                        "type": "http://adlnet.gov/expapi/activities/course",
                                        "name": {"en-US": project.title}
                                    }
                                }]
                            }
                        }
                    }
                    statements.append(question_statement)
    
    return {
        "projectId": project_id,
        "projectTitle": project.title,
        "statementCount": len(statements),
        "statements": statements,
    }


# ═══════════════════════════════════════════════════════════════════════
# xAPI / Tin Can ZIP Package Export
# ═══════════════════════════════════════════════════════════════════════

@router.get("/{project_id}/export/tincan")
async def export_tincan(
    project_id: str,
    module_id: str = "all",
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Generates and returns an xAPI (Tin Can) compliant ZIP package containing curriculum HTML and tracking scripts."""
    # Verify project
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")
        
    # Get modules
    modules_res = await db.execute(
        select(CurriculumModule).where(CurriculumModule.project_id == project_id).order_by(CurriculumModule.sequence_order)
    )
    modules = modules_res.scalars().all()
    if not modules:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No curriculum modules found to export.")
        
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
        # Determine target modules
        target_modules = modules
        if module_id != "all" and module_id != "default":
            target_modules = [m for m in modules if m.id == module_id]
            if not target_modules:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Module not found")
        
        # 1. Generate tincan.xml manifest
        manifest = generate_tincan_manifest(project, target_modules)
        zip_file.writestr("tincan.xml", manifest)
        
        # 2. Generate lesson content
        if len(target_modules) == 1:
            mod = target_modules[0]
            questions_res = await db.execute(
                select(QuizQuestion).where(QuizQuestion.module_id == mod.id)
            )
            questions = questions_res.scalars().all()
            html_content = generate_tincan_lesson_html(project, mod, questions)
            zip_file.writestr("index.html", html_content)
        else:
            # Multi-module interactive course reader hub
            course_data = []
            for mod in target_modules:
                questions_res = await db.execute(
                    select(QuizQuestion).where(QuizQuestion.module_id == mod.id)
                )
                questions = questions_res.scalars().all()
                course_data.append({
                    "id": mod.id,
                    "title": mod.title,
                    "content": mod.content,
                    "blooms_level": mod.blooms_level,
                    "questions": [{
                        "question_text": q.question_text,
                        "options": q.options,
                        "correct_answer": q.correct_answer,
                        "explanation": q.explanation
                    } for q in questions]
                })
            
            html_content = generate_tincan_hub_html(project, course_data)
            zip_file.writestr("index.html", html_content)
            
    zip_buffer.seek(0)
    filename = f"{project.title.lower().replace(' ', '_')}_tincan.zip"
    return StreamingResponse(
        zip_buffer,
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


def generate_tincan_manifest(project, modules) -> str:
    """Generates a valid tincan.xml manifest file."""
    activities_xml = f"""    <activity id="urn:agentic-edtech:project:{project.id}" type="course">
      <name lang="en-US">{project.title}</name>
      <description lang="en-US">{project.description or "Agentic EdTech Course Package"}</description>
      <launch>index.html</launch>
    </activity>"""
    
    for mod in modules:
        activities_xml += f"""\n    <activity id="urn:agentic-edtech:project:{project.id}:module:{mod.id}" type="module">
      <name lang="en-US">{mod.title}</name>
      <description lang="en-US">Learning module: {mod.title}</description>
    </activity>"""
        
    return f"""<?xml version="1.0" encoding="utf-8"?>
<tincan xmlns="http://projecttincan.com/tincan.xsd">
  <activities>
{activities_xml}
  </activities>
</tincan>
"""


def generate_tincan_lesson_html(project, module, questions: list[QuizQuestion]) -> str:
    """Generates an xAPI compliant single-module course page with embedded tracking script."""
    quiz_html = ""
    quiz_js = ""
    
    if questions:
        quiz_html = """
        <div class="card">
            <h2 class="quiz-title">Knowledge Check</h2>
            <div id="quiz-container">
        """
        for idx, q in enumerate(questions):
            q_num = idx + 1
            opts_html = "".join([
                f'<label class="quiz-option"><input type="radio" name="q{q_num}" value="{opt}"> <span>{opt}</span></label>'
                for opt in (q.options or [])
            ])
            quiz_html += f"""
            <div class="quiz-question-box">
                <p><strong>Q{q_num}: {q.question_text}</strong></p>
                {opts_html}
            </div>
            """
        quiz_html += """
                <button onclick="submitQuiz()" class="quiz-submit-btn">Submit Quiz</button>
            </div>
        </div>
        """
        
        ans_array = ", ".join([f'"{q.correct_answer}"' for q in questions])
        quiz_js = f"""
        var correctAnswers = [{ans_array}];
        
        function submitQuiz() {{
            var score = 0;
            for(var i=1; i<=correctAnswers.length; i++) {{
                var selected = document.querySelector('input[name="q' + i + '"]:checked');
                if (selected && selected.value === correctAnswers[i-1]) {{
                    score++;
                }}
            }}
            var percentage = Math.round((score / correctAnswers.length) * 100);
            alert("You scored: " + percentage + "%");
            
            sendXAPIStatement(
                "http://adlnet.gov/expapi/verbs/answered",
                "answered",
                activityId + "/quiz",
                "{module.title} Quiz",
                {{
                    "score": {{
                        "raw": score,
                        "min": 0,
                        "max": correctAnswers.length,
                        "scaled": score / correctAnswers.length
                    }},
                    "success": percentage >= 70,
                    "completion": true
                }}
            );
        }}
        """
        
    clean_content = module.content.replace('\n', '<br>')
    return f"""<!DOCTYPE html>
<html>
<head>
    <title>{module.title}</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        {PREMIUM_CSS}
    </style>
    <script>
        var urlParams = new URLSearchParams(window.location.search);
        var endpoint = urlParams.get('endpoint');
        var auth = urlParams.get('auth');
        var actor = urlParams.get('actor');
        var activityId = urlParams.get('activity_id') || "urn:agentic-edtech:project:{project.id}:module:{module.id}";
        var registration = urlParams.get('registration');

        if (actor) {{
            try {{
                actor = JSON.parse(actor);
            }} catch(e) {{
                console.error("Failed to parse actor JSON", e);
            }}
        }}

        function sendXAPIStatement(verbId, verbDisplay, objectId, objectName, result, cb) {{
            if (!endpoint || !auth) {{
                console.log("No LRS configuration. Skipping statement: " + verbDisplay);
                if (cb) cb();
                return;
            }}
            
            var url = endpoint;
            if (url.substring(url.length - 1) !== '/') {{
                url += '/';
            }}
            url += 'statements';
            
            var statement = {{
                "actor": actor || {{
                    "objectType": "Agent",
                    "name": "Anonymous Learner",
                    "mbox": "mailto:anonymous@agenticedtech.local"
                }},
                "verb": {{
                    "id": verbId,
                    "display": {{ "en-US": verbDisplay }}
                }},
                "object": {{
                    "objectType": "Activity",
                    "id": objectId,
                    "definition": {{
                        "name": {{ "en-US": objectName }}
                    }}
                }}
            }};
            
            if (result) {{
                statement.result = result;
            }}
            
            if (registration) {{
                statement.context = {{
                    "registration": registration
                }};
            }}
            
            var xhr = new XMLHttpRequest();
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("Authorization", auth);
            xhr.setRequestHeader("X-Experience-API-Version", "1.0.3");
            
            xhr.onreadystatechange = function() {{
                if (xhr.readyState === 4) {{
                    console.log("xAPI statement sent: " + verbDisplay + " (Status: " + xhr.status + ")");
                    if (cb) cb();
                }}
            }};
            xhr.send(JSON.stringify(statement));
        }}

        window.onload = function() {{
            sendXAPIStatement(
                "http://adlnet.gov/expapi/verbs/attempted",
                "attempted",
                activityId,
                "{module.title}",
                null
            );
        }};

        window.onunload = function() {{
            sendXAPIStatement(
                "http://adlnet.gov/expapi/verbs/completed",
                "completed",
                activityId,
                "{module.title}",
                {{ "completion": true }}
            );
        }};
        
        {quiz_js}
    </script>
</head>
<body>
    <div class="container">
        <div class="card">
            <h1>{module.title}</h1>
            <div>
                {clean_content}
            </div>
        </div>
        {quiz_html}
    </div>
</body>
</html>
"""


def generate_tincan_hub_html(project, course_data: list) -> str:
    """Generates a responsive multi-module course reader hub with a sidebar, progress bar, and LRS tracking."""
    import json
    course_data_json = json.dumps(course_data)
    
    return f"""<!DOCTYPE html>
<html>
<head>
    <title>{project.title}</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        {PREMIUM_CSS}
        
        body {{
            display: flex;
            height: 100vh;
            overflow: hidden;
            background-color: #f1f5f9;
            margin: 0;
            padding: 0;
        }}
        
        .sidebar {{
            width: 320px;
            background-color: #0f172a;
            color: #f8fafc;
            display: flex;
            flex-direction: column;
            border-right: 1px solid #1e293b;
            flex-shrink: 0;
        }}
        
        .sidebar-header {{
            padding: 24px;
            border-bottom: 1px solid #1e293b;
        }}
        
        .sidebar-header h1 {{
            color: #ffffff;
            font-size: 1.25rem;
            border: none;
            margin: 0;
            padding: 0;
        }}
        
        .progress-container {{
            padding: 16px 24px;
            background-color: #1e293b;
            font-size: 0.85rem;
        }}
        
        .progress-bar-bg {{
            background-color: #334155;
            height: 8px;
            border-radius: 9999px;
            overflow: hidden;
            margin-top: 8px;
        }}
        
        .progress-bar-fill {{
            background-color: #10b981;
            height: 100%;
            width: 0%;
            transition: width 0.3s ease;
        }}
        
        .module-list {{
            flex: 1;
            overflow-y: auto;
            padding: 16px 0;
        }}
        
        .module-item {{
            padding: 14px 24px;
            cursor: pointer;
            transition: all 0.2s ease;
            border-left: 4px solid transparent;
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 0.9rem;
            color: #94a3b8;
        }}
        
        .module-item:hover {{
            background-color: #1e293b;
            color: #ffffff;
        }}
        
        .module-item.active {{
            background-color: #1e293b;
            border-left-color: #6366f1;
            font-weight: 600;
            color: #ffffff;
        }}
        
        .main-content {{
            flex: 1;
            overflow-y: auto;
            padding: 40px;
            display: flex;
            flex-direction: column;
            align-items: center;
        }}
        
        .content-card {{
            width: 100%;
            max-width: 800px;
        }}
        
        .completion-check {{
            color: #10b981;
            font-weight: bold;
        }}
        
        .quiz-option input[type="radio"] {{
            margin-right: 12px;
            accent-color: var(--brand-primary);
        }}
        
        .quiz-option {{
            display: flex;
            align-items: center;
            background-color: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 12px 16px;
            margin: 8px 0;
            cursor: pointer;
            transition: all 0.2s ease;
        }}
        
        .quiz-option:hover {{
            border-color: var(--brand-light);
            background-color: #f5f3ff;
        }}
        
        .quiz-question-box {{
            background-color: #f8fafc;
            border-left: 4px solid var(--brand-primary);
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }}
    </style>
    <script>
        var urlParams = new URLSearchParams(window.location.search);
        var endpoint = urlParams.get('endpoint');
        var auth = urlParams.get('auth');
        var actor = urlParams.get('actor');
        var baseActivityId = urlParams.get('activity_id') || "urn:agentic-edtech:project:{project.id}";
        var registration = urlParams.get('registration');

        if (actor) {{
            try {{
                actor = JSON.parse(actor);
            }} catch(e) {{
                console.error("Failed to parse actor JSON", e);
            }}
        }}

        function sendXAPIStatement(verbId, verbDisplay, objectId, objectName, result, cb) {{
            if (!endpoint || !auth) {{
                console.log("No LRS configuration. Skipping statement: " + verbDisplay);
                if (cb) cb();
                return;
            }}
            
            var url = endpoint;
            if (url.substring(url.length - 1) !== '/') {{
                url += '/';
            }}
            url += 'statements';
            
            var statement = {{
                "actor": actor || {{
                    "objectType": "Agent",
                    "name": "Anonymous Learner",
                    "mbox": "mailto:anonymous@agenticedtech.local"
                }},
                "verb": {{
                    "id": verbId,
                    "display": {{ "en-US": verbDisplay }}
                }},
                "object": {{
                    "objectType": "Activity",
                    "id": objectId,
                    "definition": {{
                        "name": {{ "en-US": objectName }}
                    }}
                }}
            }};
            
            if (result) {{
                statement.result = result;
            }}
            
            if (registration) {{
                statement.context = {{
                    "registration": registration
                }};
            }}
            
            var xhr = new XMLHttpRequest();
            xhr.open("POST", url, true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("Authorization", auth);
            xhr.setRequestHeader("X-Experience-API-Version", "1.0.3");
            
            xhr.onreadystatechange = function() {{
                if (xhr.readyState === 4) {{
                    console.log("xAPI statement sent: " + verbDisplay + " (Status: " + xhr.status + ")");
                    if (cb) cb();
                }}
            }};
            xhr.send(JSON.stringify(statement));
        }}

        var courseData = {course_data_json};
        var currentModuleIdx = 0;
        var completedModules = new Set();

        window.onload = function() {{
            sendXAPIStatement(
                "http://adlnet.gov/expapi/verbs/attempted",
                "attempted",
                baseActivityId,
                "{project.title}",
                null
            );
            
            renderModuleList();
            loadModule(0);
        }};

        window.onunload = function() {{
            var courseResult = null;
            if (completedModules.size === courseData.length) {{
                courseResult = {{ "completion": true, "success": true }};
            }}
            sendXAPIStatement(
                "http://adlnet.gov/expapi/verbs/completed",
                "completed",
                baseActivityId,
                "{project.title}",
                courseResult
            );
        }};

        function renderModuleList() {{
            var listEl = document.getElementById("module-list-container");
            listEl.innerHTML = "";
            
            courseData.forEach(function(mod, idx) {{
                var item = document.createElement("div");
                item.className = "module-item" + (idx === currentModuleIdx ? " active" : "");
                item.onclick = function() {{ loadModule(idx); }};
                
                var titleText = document.createElement("span");
                titleText.innerText = (idx + 1) + ". " + mod.title;
                item.appendChild(titleText);
                
                if (completedModules.has(mod.id)) {{
                    var check = document.createElement("span");
                    check.className = "completion-check";
                    check.innerHTML = "✓";
                    item.appendChild(check);
                }}
                
                listEl.appendChild(item);
            }});
            
            var percentage = Math.round((completedModules.size / courseData.length) * 100);
            document.getElementById("progress-text").innerText = completedModules.size + " of " + courseData.length + " modules completed";
            document.getElementById("progress-bar").style.width = percentage + "%";
        }}

        function loadModule(idx) {{
            currentModuleIdx = idx;
            renderModuleList();
            
            var mod = courseData[idx];
            var container = document.getElementById("content-viewer");
            container.innerHTML = "";
            
            var card = document.createElement("div");
            card.className = "card content-card";
            
            var h1 = document.createElement("h1");
            h1.innerText = mod.title;
            card.appendChild(h1);
            
            var contentDiv = document.createElement("div");
            contentDiv.innerHTML = mod.content.replace(/\\n/g, "<br>");
            card.appendChild(contentDiv);
            
            container.appendChild(card);
            
            sendXAPIStatement(
                "http://adlnet.gov/expapi/verbs/attempted",
                "attempted",
                baseActivityId + "/module/" + mod.id,
                mod.title,
                null
            );
            
            if (mod.questions && mod.questions.length > 0) {{
                var quizCard = document.createElement("div");
                quizCard.className = "card content-card";
                
                var qTitle = document.createElement("h2");
                qTitle.className = "quiz-title";
                qTitle.innerText = "Knowledge Check";
                quizCard.appendChild(qTitle);
                
                mod.questions.forEach(function(q, qIdx) {{
                    var qNum = qIdx + 1;
                    var box = document.createElement("div");
                    box.className = "quiz-question-box";
                    
                    var qText = document.createElement("p");
                    qText.innerHTML = "<strong>Q" + qNum + ": " + q.question_text + "</strong>";
                    box.appendChild(qText);
                    
                    q.options.forEach(function(opt) {{
                        var label = document.createElement("label");
                        label.className = "quiz-option";
                        
                        var radio = document.createElement("input");
                        radio.type = "radio";
                        radio.name = "q" + qNum;
                        radio.value = opt;
                        
                        label.appendChild(radio);
                        
                        var span = document.createElement("span");
                        span.innerText = opt;
                        label.appendChild(span);
                        
                        box.appendChild(label);
                    }});
                    
                    quizCard.appendChild(box);
                }});
                
                var btn = document.createElement("button");
                btn.className = "quiz-submit-btn";
                btn.innerText = "Submit Quiz";
                btn.onclick = function() {{ submitQuiz(idx); }};
                quizCard.appendChild(btn);
                
                container.appendChild(quizCard);
            }} else {{
                markModuleCompleted(mod.id, mod.title);
            }}
        }}

        function submitQuiz(idx) {{
            var mod = courseData[idx];
            var score = 0;
            
            for (var i = 1; i <= mod.questions.length; i++) {{
                var selected = document.querySelector('input[name="q' + i + '"]:checked');
                if (selected && selected.value === mod.questions[i - 1].correct_answer) {{
                    score++;
                }}
            }}
            
            var percentage = Math.round((score / mod.questions.length) * 100);
            alert("You scored: " + percentage + "%");
            
            sendXAPIStatement(
                "http://adlnet.gov/expapi/verbs/answered",
                "answered",
                baseActivityId + "/module/" + mod.id + "/quiz",
                mod.title + " Quiz",
                {{
                    "score": {{
                        "raw": score,
                        "min": 0,
                        "max": mod.questions.length,
                        "scaled": score / mod.questions.length
                    }},
                    "success": percentage >= 70,
                    "completion": true
                }}
            );
            
            if (percentage >= 70) {{
                markModuleCompleted(mod.id, mod.title);
            }}
        }}

        function markModuleCompleted(moduleId, moduleTitle) {{
            if (!completedModules.has(moduleId)) {{
                completedModules.add(moduleId);
                renderModuleList();
                
                sendXAPIStatement(
                    "http://adlnet.gov/expapi/verbs/completed",
                    "completed",
                    baseActivityId + "/module/" + moduleId,
                    moduleTitle,
                    {{ "completion": true, "success": true }}
                );
            }}
        }}
    </script>
</head>
<body>
    <div class="sidebar">
        <div class="sidebar-header">
            <h1>Course Reader</h1>
        </div>
        <div class="progress-container">
            <div id="progress-text">0 of 0 completed</div>
            <div class="progress-bar-bg">
                <div class="progress-bar-fill" id="progress-bar"></div>
            </div>
        </div>
        <div class="module-list" id="module-list-container"></div>
    </div>
    <div class="main-content" id="content-viewer"></div>
</body>
</html>
"""


# ═══════════════════════════════════════════════════════════════════════
# Telemetry API
# ═══════════════════════════════════════════════════════════════════════

@router.get("/{project_id}/telemetry")
async def get_telemetry(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db)
):
    """Returns live telemetry metrics for a project with threshold-based alerts.
    
    Monitors pass rates, confusion signals, and document processing health.
    """
    from sqlalchemy import func
    from app.models.database import SimulationRun, PersonaResult, Document
    
    # Verify project
    proj_result = await db.execute(
        select(Project).where(Project.id == project_id, Project.owner_id == user_id)
    )
    project = proj_result.scalars().first()
    if not project:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Project not found")
    
    # Aggregate simulation metrics
    sim_ids_q = await db.execute(
        select(SimulationRun.id).where(SimulationRun.project_id == project_id)
    )
    sim_ids = [row[0] for row in sim_ids_q.all()]
    
    total_answers = 0
    total_passed = 0
    confusion_count = 0
    
    if sim_ids:
        total_q = await db.execute(
            select(func.count(PersonaResult.id)).where(PersonaResult.run_id.in_(sim_ids))
        )
        total_answers = total_q.scalar() or 0
        
        passed_q = await db.execute(
            select(func.count(PersonaResult.id)).where(
                PersonaResult.run_id.in_(sim_ids), PersonaResult.passed == True
            )
        )
        total_passed = passed_q.scalar() or 0
        
        confusion_q = await db.execute(
            select(func.count(PersonaResult.id)).where(
                PersonaResult.run_id.in_(sim_ids),
                PersonaResult.confusion_signal.isnot(None),
                PersonaResult.confusion_signal != ""
            )
        )
        confusion_count = confusion_q.scalar() or 0
    
    # Document health
    doc_count_q = await db.execute(
        select(func.count(Document.id)).where(Document.project_id == project_id)
    )
    doc_total = doc_count_q.scalar() or 0
    
    doc_failed_q = await db.execute(
        select(func.count(Document.id)).where(
            Document.project_id == project_id, Document.processing_status == "failed"
        )
    )
    doc_failed = doc_failed_q.scalar() or 0
    
    overall_pass_rate = round(total_passed / max(total_answers, 1) * 100, 1) if total_answers else 0.0
    confusion_rate = round(confusion_count / max(total_answers, 1) * 100, 1) if total_answers else 0.0
    
    # Threshold-based alerts
    alerts = []
    if overall_pass_rate < 60 and total_answers > 0:
        alerts.append({
            "level": "critical",
            "message": f"Overall pass rate is {overall_pass_rate}% (below 60% threshold)",
            "metric": "pass_rate",
            "threshold": 60,
            "current": overall_pass_rate,
        })
    elif overall_pass_rate < 75 and total_answers > 0:
        alerts.append({
            "level": "warning",
            "message": f"Pass rate is {overall_pass_rate}% (below 75% target)",
            "metric": "pass_rate",
            "threshold": 75,
            "current": overall_pass_rate,
        })
    
    if confusion_rate > 30:
        alerts.append({
            "level": "warning",
            "message": f"High confusion signal rate: {confusion_rate}%",
            "metric": "confusion_rate",
            "threshold": 30,
            "current": confusion_rate,
        })
    
    if doc_failed > 0:
        alerts.append({
            "level": "warning",
            "message": f"{doc_failed} document(s) failed processing",
            "metric": "document_health",
            "threshold": 0,
            "current": doc_failed,
        })
    
    return {
        "projectId": project_id,
        "metrics": {
            "simulationRuns": len(sim_ids),
            "totalAnswers": total_answers,
            "totalPassed": total_passed,
            "overallPassRate": overall_pass_rate,
            "confusionSignals": confusion_count,
            "confusionRate": confusion_rate,
            "documentsTotal": doc_total,
            "documentsFailed": doc_failed,
        },
        "alerts": alerts,
        "alertCount": len(alerts),
    }

