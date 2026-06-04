# AGENTS.md — Project Knowledge Spec
<!-- AUTO-UPDATED: 2026-06-04T00:22:00+03:00 -->
<!-- TOKEN BUDGET: ~2500 tokens. Read THIS file first. Only read linked files if needed. -->

## Identity
- **Name**: Agentic EdTech Platform
- **Stack**: SwiftUI iOS 17+ ↔ FastAPI Python 3.12+ ↔ Gemini 2.0 Flash ↔ Qdrant Cloud ↔ SQLite (dev) / Neon PostgreSQL (prod)
- **Owner**: @elamir
- **Root**: `/Users/elamir/Desktop/E_Learning_Project`
- **Constraint**: Free-tier only ($0/month). Groq or Gemini only (no OpenAI/Anthropic). Single Python backend (no Go/Node).

## Quick Start
```bash
# Backend
cd backend && source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload

# iOS — open in Xcode
open ios/AgenticEdTech/AgenticEdTech/AgenticEdTech.xcodeproj

# Tests
cd backend && .venv/bin/python -m pytest tests/test_integration.py -v  # 23 tests
```

## Architecture
```
iOS (SwiftUI @Observable)  ──REST+WS──▶  FastAPI (uvicorn :8080)
                                           ├── SQLAlchemy Async (SQLite/PostgreSQL)
                                           ├── LangGraph (multi-agent graph)
                                           ├── Qdrant Cloud (vector embeddings)
                                           ├── Groq (Llama 3 for LLM calls)
                                           ├── spaCy en_core_web_sm (NLP fallback)
                                           └── SentenceTransformers all-MiniLM-L6-v2
```

## File Map — Backend (`backend/app/`)

| File | Purpose | Key Functions/Classes |
|:--|:--|:--|
| `main.py` | FastAPI app, lifespan, CORS, router mounts, `/ws` endpoint, `/health` | `app`, `lifespan()` |
| `config.py` | `pydantic_settings.BaseSettings` — loads `.env` | `settings` singleton |
| `database.py` | SQLAlchemy async engine, `Base`, `init_db()`, `get_db()` | `async_session_maker` |
| **models/** | | |
| `database.py` | ORM: User, Project, Document, AgentSession, AgentMessage, CurriculumModule, QuizQuestion, Concept, ConceptPrerequisite, SimulationRun, PersonaResult | All 10 tables |
| `schemas.py` | Pydantic: request/response models for all endpoints | PersonaProfile, RunSimulationRequest |
| **api/** | | |
| `auth.py` | POST `/register`, `/login`, `/apple-login` — JWT-based, bcrypt | `create_access_token()` |
| `projects.py` | CRUD `/api/projects/`, GET `/{id}/metrics` | Full REST + metrics aggregation |
| `documents.py` | POST upload (multipart), GET list, DELETE, POST `/{id}/query` (RAG) | `rag_query()` — Qdrant search + Gemini answer |
| `concepts.py` | GET `/{id}/concepts` — returns concept graph + prerequisites | `ConceptGraphResponse` |
| `modules.py` | GET `/{id}/modules` — lists curriculum modules with quizzes | |
| `simulations.py` | POST `/{id}/simulations/run`, GET list — Gemini persona simulation | `run_simulation()` L103-293 |
| `export.py` | GET `/{id}/export/scorm` — generates SCORM 1.2 ZIP | `generate_scorm_package()` |
| **agents/** | | |
| `graph.py` | LangGraph StateGraph: planning→hitl→content→critique→revision→assessment→heatmap→END | `build_curriculum_graph()`, `get_llm()` |
| `state.py` | `AgentState` TypedDict for LangGraph | |
| **utils/** | | |
| `ingestion_service.py` | PDF parse → semantic chunk → Qdrant embed → Gemini concept extract | `process_document_ingestion()`, `get_encoder()` |
| `qdrant_client.py` | Qdrant Cloud connection singleton | `get_qdrant_client()` |
| `cognitive_load.py` | Text readability/complexity scoring per paragraph | `analyze_text()` |
| **ws/** | | |
| `manager.py` | `WebSocketConnectionManager` — user↔socket map | `ws_manager` singleton |
| `handler.py` | WS message router: ping, start_agent_debate, submit_hitl_approval | `websocket_endpoint()` |
| **workers/** | | |
| `pool.py` | Async worker pool for background ingestion tasks | `worker_pool.submit()` |

## File Map — iOS (`ios/.../AgenticEdTech/`)

| File | Purpose | Key Types |
|:--|:--|:--|
| `AgenticEdTechApp.swift` | App entry, injects `AppState` into environment | |
| `AppState.swift` | Global `@Observable` state: auth, project, WS status | `AppState`, `WorkspaceType` enum |
| `ContentView.swift` | TabView (iPhone) / NavigationSplitView (iPad) | `WorkspaceContextPanel`, `WorkspaceDetailView` |
| **Core/Network/** | | |
| `APIClient.swift` | Singleton REST client, multipart upload, JWT auth | `APIClient.shared`, `baseURL = localhost:8080` |
| `WebSocketManager.swift` | WS connection, auto-reconnect, Combine publisher | `WebSocketManager.shared` |
| `ServerMessage.swift` | Codable WS message types, `AnyCodable` | `ServerMessage`, `ClientMessage` |
| **Core/Theme/** | | |
| `DesignTokens.swift` | Colors (`.brand`, `.brandLight`, `.error`, `.success`, `.warning`, `.info`), Spacing, Font extensions | |
| **Features/Auth/** | | |
| `LoginView.swift` | Email/password login, registration, Sign in with Apple | `LoginViewModel` |
| **Features/Dashboard/** | | |
| `DashboardView.swift` | KPI cards, Bloom's chart, persona chart, WS health | `DashboardViewModel`, `MetricCard` |
| **Features/Ingestion/** | | |
| `IngestionView.swift` | Document upload, concept graph, status polling | `IngestionViewModel`, `ConceptGraphVisualizer` |
| `RAGQueryView.swift` | Question→vector search→grounded answer | `RAGQueryViewModel` |
| **Features/Canvas/** | | |
| `AgenticCanvasView.swift` | WS agent chat, HITL approval, SCORM export | `AgenticCanvasViewModel` |
| **Features/Simulation/** | | |
| `SimulationSandboxView.swift` | Persona config, run simulation, results table | `SimulationViewModel` |
| **Features/Testing/** | | |
| `DiagnosticsView.swift` | Integration test runner UI | |
| **Shared/Components/** | | |
| `GlassView.swift` | Glassmorphism container | |
| `BrandButton.swift` | Primary/secondary/ghost button styles | |
| `BrandTextField.swift` | Themed text field | |
| `ErrorBanner.swift` | Reusable dismissible status banner (error/warning/info/success) + `.errorBanner()` modifier | `StatusBanner`, `AutoDismissErrorBanner` |
| `AgentMessageBubble.swift` | Chat bubble for agent messages | |
| `HITLApprovalCard.swift` | Human-in-the-loop approve/reject card | |

## API Contract (All require `Authorization: Bearer <token>` except auth + health)

| Method | Path | Body | Returns |
|:--|:--|:--|:--|
| GET | `/health` | — | `{"status":"ok"}` |
| POST | `/api/auth/register` | `{email, password, display_name}` | `UserResponse` |
| POST | `/api/auth/login` | `{email, password}` | `{access_token, token_type, user}` |
| POST | `/api/auth/apple-login` | `{apple_id, email, display_name}` | `{access_token, token_type, user}` |
| GET/POST | `/api/projects/` | `{title, description}` | `ProjectResponse[]` or single |
| GET | `/api/projects/{id}` | — | `ProjectResponse` |
| PUT | `/api/projects/{id}` | `{title?, description?, status?}` | `ProjectResponse` |
| DELETE | `/api/projects/{id}` | — | 204 |
| GET | `/api/projects/{id}/metrics` | — | `ProjectMetrics` |
| POST | `/api/projects/{id}/documents` | multipart `file` | `DocumentResponse` |
| GET | `/api/projects/{id}/documents` | — | `DocumentResponse[]` |
| DELETE | `/api/projects/{id}/documents/{docId}` | — | 204 |
| POST | `/api/projects/{id}/query` | `{question, topK?, generateAnswer?}` | `{answer, chunks[]}` |
| GET | `/api/projects/{id}/concepts` | — | `{concepts[], prerequisites[]}` |
| GET | `/api/projects/{id}/modules` | — | `CurriculumModuleResponse[]` |
| POST | `/api/projects/{id}/simulations/run` | `{module_id, personas?[]}` | `SimulationRunResponse` |
| GET | `/api/projects/{id}/simulations` | — | `SimulationRunResponse[]` |
| GET | `/api/projects/{id}/export/scorm` | — | ZIP file (binary) |
| WS | `/ws?token=<jwt>` | — | Bidirectional JSON messages |

## WebSocket Message Protocol

**Client → Server:**
| type | payload |
|:--|:--|
| `ping` | `{}` |
| `start_agent_debate` | `{topic, project_id}` |
| `submit_hitl_approval` | `{session_id, approved: bool}` |

**Server → Client:**
| type | payload |
|:--|:--|
| `connection_established` | `{user_id}` |
| `pong` | `{}` |
| `agent_session_created` | `{sessionId}` |
| `agent_stream` | `{agent, messageType, content}` |
| `agent_complete` | `{session_id}` |
| `error` | `{message}` |

## Data Models (10 Tables)
`User → Project → Document, AgentSession, CurriculumModule, Concept, SimulationRun`
- `AgentSession → AgentMessage`
- `CurriculumModule → QuizQuestion`
- `Concept → ConceptPrerequisite`
- `SimulationRun → PersonaResult`
- All IDs are UUID strings (36 chars)
- All timestamps are `DateTime` (UTC)

## Coding Conventions

### Python
- **Async everywhere**: all DB operations use `async/await` with `AsyncSession`
- **Pydantic v2**: `model_config = SettingsConfigDict(...)`, `from_attributes = True`
- **Logging**: `logger = logging.getLogger(__name__)` — never `print()`
- **Error handling**: always `try/except` with `logger.error(msg, exc_info=True)`
- **Imports**: stdlib → third-party → local (`from app.xxx import yyy`)
- **Groq check pattern**: `if api_key and api_key != "mock_key":` before LLM calls

### Swift
- **State**: `@Observable` classes (NOT `ObservableObject`). Never use `@Published`.
- **Environment**: `@Environment(AppState.self) private var appState`
- **Networking**: `APIClient.shared.request(path:method:body:)` — generic Decodable
- **Errors**: use `.errorBanner($viewModel.errorMessage)` modifier, NOT inline `Text()`
- **Components**: reuse `GlassView`, `BrandButton`, `BrandTextField`, `StatusBanner`
- **Layout**: `sizeClass == .compact` → iPhone layout, `.regular` → iPad layout
- **Naming**: `camelCase` properties auto-decoded via `JSONDecoder().keyDecodingStrategy = .convertFromSnakeCase`

## Environment (.env in backend/)
```
GOOGLE_API_KEY=<Gemini API key>
GROQ_API_KEY=<Groq API key>
QDRANT_URL=<Qdrant Cloud cluster endpoint>
QDRANT_API_KEY=<Qdrant API key>
DATABASE_URL=sqlite+aiosqlite:///./edtech.db
JWT_SECRET=<secret>
PORT=8080
```

## iPhone Testing
⚠️ `localhost:8080` does NOT work on a physical iPhone. Options:
1. Change `APIClient.baseURL` to Mac's local IP: `http://192.168.x.x:8080`
2. Or use `ngrok http 8080` and set the ngrok URL

## Current Status (2026-06-03)

| Feature | Backend | iOS | Notes |
|:--|:--|:--|:--|
| Auth (email + Apple) | ✅ | ✅ | Apple Sign-In needs provisioning profile |
| Projects CRUD | ✅ | ✅ | Auto-creates default on first login |
| Document Upload + Ingestion | ✅ | ✅ | PDF→chunks→Qdrant→concepts pipeline |
| Concept Graph | ✅ | ✅ | Bloom's taxonomy, prerequisite edges |
| RAG Query | ✅ | ✅ | Vector search + Gemini grounded answer |
| Agent Canvas (LangGraph) | ✅ | ✅ | WebSocket streaming, HITL approval |
| Persona Simulation | ✅ | ✅ | Gemini LLM personas, per-question scoring |
| Cognitive Heatmap | ✅ | ✅ | Paragraph-level readability scores |
| SCORM Export | ✅ | ✅ | SCORM 1.2 ZIP with imsmanifest.xml |
| Dashboard Metrics | ✅ | ✅ | Charts, KPIs, WS health |
| Diagnostics Tests | ✅ | ✅ | 23/23 integration tests passing |

## Known Issues / TODO
- [ ] **Hosting**: Backend runs on localhost only. Need Cloud Run / Railway / DO deployment.
- [ ] **PostgreSQL**: Using SQLite for dev. Switch `DATABASE_URL` to Neon for production.
- [ ] **LangGraph checkpointing**: Uses `MemorySaver` (in-memory). Need `PostgresSaver` for persistence.
- [ ] **Cross-encoder reranking**: Not implemented — dense search only.
- [x] **SCORM 2004 / multi-SCO**: Fully implemented multi-SCO packaging for SCORM 1.2 and SCORM 2004.
- [ ] **Threshold alerting**: Not implemented.
- [ ] **Apple Sign-In**: Needs Apple Developer account provisioning profile configured.

## Agent Rules
1. **Read this file first** — do NOT explore the codebase blindly
2. **Check file map above** — go directly to the file you need
3. **Python only backend** — do NOT introduce Go, Node.js, or other languages
4. **Groq / Gemini only** — do NOT add OpenAI or Anthropic
5. **Free tier only** — do NOT add paid services
6. **No simulations** — every feature must use real backend APIs, no fake data
7. **SwiftUI is display only** — no heavy computation on client
8. **Use StatusBanner** for errors — no inline `Text()` error displays
9. **Update this file** when you make significant changes (see changelog below)
10. **Run tests** after changes: `pytest tests/test_integration.py -v` + Xcode build

---

## Changelog
<!-- Append new entries at the top. Format: YYYY-MM-DD | Agent/Human | Summary -->

| Date | Author | Changes |
|:--|:--|:--|
| 2026-06-04 | Agent | Upgraded classroom Simulation Sandbox into a high-value pedagogical diagnostic engine. Refactored backend simulation endpoints (`/simulations/run`, `/simulations/{run_id}`) to capture student distractor reasoning, classify failure modes using `confusion_signal` metrics, and run asynchronous Gemini agents to compile structured pedagogical recommendations. Designed and built the segmented **Simulation Analysis Report** view in SwiftUI, incorporating a historic runs drawer, interactive help sheets, tabbed overview charts, question-by-question breakdown drawers with student attempt avatars, and custom AI suggestion panels. |
| 2026-06-04 | Agent | Architected and implemented dynamic Local LLM Integration System. Created backend diagnostic connection router and completions check endpoint (`POST /api/projects/{project_id}/llm-config/test`). Refactored LangGraph agents, simulations sandbox, RAG query synthesizer, and document ingestion concept extraction pipelines to support custom project-level LLM settings. Designed and built the glassmorphic segmented **AI Model Configuration Panel** in the iPad Sidebar/Workspace Context Panel with live handshake tests and latency markers. |
| 2026-06-04 | Agent | Upgraded Agentic Canvas UI/UX: implemented simultaneously composed gestures (pan, zoom, and spring reset) in CurriculumNodeGraph, matched geometry sliding capsule selector highlights on the framework selector cards, dynamic spring scale suggestion chips transitions, and redesigned the Telemetry Console drawer with monospaced logs, scroll tracking, and a live breathing pulse indicator. Upgraded LMS Simulator Player frame to use immersive fullScreenCover, added adaptive ZStack slide-over drawers for compact iPhone viewports, and auto-collapsed sidebar on mobile start to prevent layout squeezing. Redesigned the iPad Sidebar/Workspace Context Panel with glassmorphic user profile card gradients, folder badges, dynamic workspace capsule tag rows, and live pulsing connection check indicators. |
| 2026-06-04 | Agent | Implemented the Pedagogical Framework Selector. Extended AgentState with the pedagogical framework choice. Formulated guidance prompts for Planning, Content, Critique, and Assessment agents mapping to Scenario-Based Learning, Socratic Inquiry, Bloom's Progression, and Traditional models. Updated WebSocket handlers and built a premium grid selector inside the iOS welcome view with an interactive floating capsule menu in the chat bar. |
| 2026-06-04 | Agent | Implemented premium UI/UX enhancements across all core views. Added horizontal scrolling filter chips (Bloom's Taxonomy Levels) and a document selector on the Ingestion Vault dependency map. Added a pulsing status dot with scale animations to track dashboard server connectivity. Added dynamic student emojis on linear gradients and animated circular score rings for classroom simulations. Replaced static Mermaid.js graphs with interactive Cytoscape.js force-directed layouts inside parent boundaries. |
| 2026-06-04 | Agent | Added missing `GET /api/projects/{id}/simulations` route to backend simulations.py, updated schemas.py to make module_id optional, and expanded test_integration.py with robust assertions for all GET/POST export types (SCORM 1.2, SCORM 2004, xAPI Tin Can, and xAPI statements). Fixed prompt template JSON escaping, added dynamic quiz question count parsing, and added dynamic course syllabus duration parsing, verifying 26/26 passing test cases. |
| 2026-06-04 | Agent | Enhanced Agentic Canvas with standalone quiz mode routing (bypassing course writing), dynamic AI-generated suggestions, and fully compliant Tin Can (xAPI) ZIP package export with premium responsive CSS styling for all course exports. |
| 2026-06-04 | Agent | Enhanced SCORM export to support multi-SCO project exports for SCORM 1.2 & SCORM 2004. Added self-healing fallback for xAPI exports when no classroom simulations have been run. Fixed WKWebView node clicks by implementing robust event delegation and custom hover styles. Resolved Swift client request type mismatch. |
| 2026-06-03 | Agent | Created AGENTS.md. Fixed RAG query (wrong API key, encoder reuse, missing filename). Removed all iOS simulations. Added StatusBanner component. Fixed iPad hardcoded content. Fixed simulation progress bar. Updated roadmap. 23/23 tests pass. |
| 2026-06-02 | Agent | Initial backend + iOS scaffold. Auth, projects, documents, agents, simulations, export, dashboard, diagnostics. WebSocket integration. |
