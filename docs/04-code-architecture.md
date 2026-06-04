# 04 — Code Architecture Patterns (Simplified)

> **Reference Type**: Permanent code reference
> **Last Updated**: 2026-06-02
> **Architecture**: Single Python backend (FastAPI) + SwiftUI iOS client

---

## Python Backend — Project Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py                       # FastAPI app entry point
│   ├── config.py                     # Settings (env-based, Pydantic)
│   ├── database.py                   # Neon PostgreSQL connection
│   │
│   ├── api/                          # REST API routes
│   │   ├── __init__.py
│   │   ├── auth.py                   # Apple Sign In + JWT
│   │   ├── projects.py               # Project CRUD
│   │   ├── documents.py              # Document upload + processing
│   │   ├── modules.py                # Curriculum module endpoints
│   │   ├── simulations.py            # Simulation endpoints
│   │   └── export.py                 # SCORM/xAPI export
│   │
│   ├── ws/                           # WebSocket handlers
│   │   ├── __init__.py
│   │   ├── manager.py                # Connection manager (hub)
│   │   └── handler.py                # WebSocket message routing
│   │
│   ├── agents/                       # LangGraph multi-agent system
│   │   ├── __init__.py
│   │   ├── graph.py                  # LangGraph graph definition
│   │   ├── state.py                  # Shared agent state schema
│   │   ├── planning_agent.py         # Curriculum structure planner
│   │   ├── content_agent.py          # Text writer
│   │   ├── assessment_agent.py       # Quiz generator
│   │   ├── critique_agent.py         # Quality reviewer
│   │   └── prompts/                  # Versioned prompt templates
│   │       ├── planning_v1.txt
│   │       ├── content_v1.txt
│   │       ├── assessment_v1.txt
│   │       └── critique_v1.txt
│   │
│   ├── ingestion/                    # Document processing pipeline
│   │   ├── __init__.py
│   │   ├── pdf_parser.py             # PyMuPDF + pdfplumber
│   │   ├── chunker.py                # Semantic chunking
│   │   ├── embedder.py               # sentence-transformers
│   │   ├── prerequisite_extractor.py # Gemini concept extraction
│   │   └── blooms_classifier.py      # Bloom's taxonomy classifier
│   │
│   ├── rag/                          # RAG pipeline
│   │   ├── __init__.py
│   │   ├── retriever.py              # Qdrant hybrid search
│   │   ├── reranker.py               # Cross-encoder reranking
│   │   └── containment.py            # Anti-hallucination guards
│   │
│   ├── simulation/                   # Persona simulation
│   │   ├── __init__.py
│   │   ├── persona_engine.py         # Persona prompt construction
│   │   └── validator.py              # Response constraint validation
│   │
│   ├── analysis/                     # Text analysis
│   │   ├── __init__.py
│   │   ├── cognitive_load.py         # Heatmap score calculator
│   │   └── readability.py            # Flesch-Kincaid, token density
│   │
│   ├── packaging/                    # Export functionality
│   │   ├── __init__.py
│   │   ├── scorm.py                  # SCORM manifest + ZIP builder
│   │   └── xapi.py                   # xAPI statement generator
│   │
│   ├── models/                       # Database models + Pydantic schemas
│   │   ├── __init__.py
│   │   ├── database.py               # SQLAlchemy models
│   │   └── schemas.py                # Pydantic request/response schemas
│   │
│   ├── auth/                         # Authentication
│   │   ├── __init__.py
│   │   ├── jwt_handler.py            # JWT creation + validation
│   │   └── apple_auth.py             # Apple Sign In verification
│   │
│   └── workers/                      # Background task management
│       ├── __init__.py
│       └── pool.py                   # Async worker pool
│
├── migrations/                       # Alembic database migrations
│   ├── alembic.ini
│   └── versions/
│
├── tests/
│   ├── unit/
│   ├── integration/
│   └── eval/                         # LLM evaluation tests
│
├── pyproject.toml                    # Dependencies (uv)
├── Dockerfile
├── .env.example
└── README.md
```

### Key Principles

1. **One single FastAPI application** — REST + WebSocket in the same process
2. **Prompts are versioned files** — stored in `agents/prompts/`, not hardcoded
3. **Analysis functions are pure math** — no LLM calls, no network I/O
4. **Pydantic everywhere** — request validation, response schemas, config
5. **Async-first** — all I/O operations use `async/await`

### Python Key Dependencies

```toml
[project]
name = "edtech-backend"
requires-python = ">=3.12"
dependencies = [
    # Web framework
    "fastapi>=0.115",
    "uvicorn[standard]>=0.30",
    "websockets>=12.0",
    "python-multipart>=0.0.9",
    
    # AI / Agents
    "langgraph>=0.2",
    "langchain>=0.3",
    "langchain-google-genai>=2.0",
    
    # NLP
    "spacy>=3.7",
    
    # Vector DB + Embeddings
    "qdrant-client>=1.9",
    "sentence-transformers>=3.0",
    
    # PDF Processing
    "pymupdf>=1.24",
    "pdfplumber>=0.11",
    
    # Database
    "sqlalchemy[asyncio]>=2.0",
    "asyncpg>=0.29",
    "alembic>=1.13",
    
    # Auth
    "python-jose[cryptography]>=3.3",
    "passlib[bcrypt]>=1.7",
    
    # Utilities
    "pydantic>=2.7",
    "pydantic-settings>=2.2",
    "httpx>=0.27",
]
```

### FastAPI WebSocket Connection Manager

```python
# app/ws/manager.py
from fastapi import WebSocket
from uuid import UUID
import json

class ConnectionManager:
    """Manages WebSocket connections — replaces Go WebSocket Hub."""
    
    def __init__(self):
        self.active_connections: dict[UUID, WebSocket] = {}
    
    async def connect(self, user_id: UUID, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[user_id] = websocket
    
    def disconnect(self, user_id: UUID):
        self.active_connections.pop(user_id, None)
    
    async def send_to_user(self, user_id: UUID, message: dict):
        ws = self.active_connections.get(user_id)
        if ws:
            await ws.send_json(message)
    
    async def broadcast(self, message: dict):
        disconnected = []
        for user_id, ws in self.active_connections.items():
            try:
                await ws.send_json(message)
            except Exception:
                disconnected.append(user_id)
        for uid in disconnected:
            self.active_connections.pop(uid, None)

# Global instance
ws_manager = ConnectionManager()
```

### LangGraph Agent Graph with Gemini

```python
# app/agents/graph.py
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.postgres import PostgresSaver
from langchain_google_genai import ChatGoogleGenerativeAI
from app.agents.state import AgentState
from app.config import settings

# Initialize Gemini (FREE via AI Studio)
llm = ChatGoogleGenerativeAI(
    model="gemini-2.0-flash",
    google_api_key=settings.GOOGLE_API_KEY,
    temperature=0.7,
)

llm_lite = ChatGoogleGenerativeAI(
    model="gemini-2.0-flash-lite",
    google_api_key=settings.GOOGLE_API_KEY,
    temperature=0.3,
)

def build_curriculum_graph(checkpointer):
    graph = StateGraph(AgentState)
    
    graph.add_node("planning", planning_node)
    graph.add_node("hitl_outline", hitl_checkpoint_node)
    graph.add_node("content", content_node)
    graph.add_node("critique", critique_node)
    graph.add_node("revision", revision_node)
    graph.add_node("assessment", assessment_node)
    graph.add_node("heatmap", heatmap_node)
    
    graph.add_edge("planning", "hitl_outline")
    graph.add_conditional_edges("hitl_outline", check_hitl_status, {
        "approved": "content",
        "rejected": "planning",
        "pending": "hitl_outline",
    })
    graph.add_edge("content", "critique")
    graph.add_conditional_edges("critique", should_revise, {
        "revise": "revision",
        "pass": "assessment",
    })
    graph.add_edge("revision", "critique")
    graph.add_edge("assessment", "heatmap")
    graph.add_edge("heatmap", END)
    
    graph.set_entry_point("planning")
    return graph.compile(
        checkpointer=checkpointer,
        interrupt_before=["hitl_outline"]
    )
```

### FastAPI Main Application

```python
# app/main.py
from fastapi import FastAPI, WebSocket, Depends
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.api import auth, projects, documents, modules, simulations, export
from app.ws.handler import websocket_endpoint
from app.database import init_db
from app.workers.pool import worker_pool

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await init_db()
    yield
    # Shutdown
    await worker_pool.shutdown()

app = FastAPI(
    title="Agentic EdTech API",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# REST API routes
app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(projects.router, prefix="/api/projects", tags=["projects"])
app.include_router(documents.router, prefix="/api/projects", tags=["documents"])
app.include_router(modules.router, prefix="/api/projects", tags=["modules"])
app.include_router(simulations.router, prefix="/api/projects", tags=["simulations"])
app.include_router(export.router, prefix="/api/projects", tags=["export"])

# WebSocket endpoint
@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket):
    await websocket_endpoint(websocket)

# Health check
@app.get("/health")
async def health():
    return {"status": "ok"}
```

---

## SwiftUI Client — Project Structure

```
ios/AgenticEdTech/
├── App/
│   ├── AgenticEdTechApp.swift        # @main entry point
│   └── AppState.swift                # Global app state
├── Core/
│   ├── Network/
│   │   ├── WebSocketManager.swift    # WebSocket connection
│   │   ├── APIClient.swift           # REST API client
│   │   └── ServerMessage.swift       # Decoded message types
│   ├── Auth/
│   │   ├── AuthManager.swift         # Apple Sign In + JWT
│   │   └── KeychainHelper.swift      # Secure token storage
│   └── Theme/
│       ├── DesignTokens.swift        # Colors, typography, spacing
│       └── ViewModifiers.swift       # Reusable style modifiers
├── Features/
│   ├── Dashboard/
│   ├── Ingestion/
│   ├── Canvas/
│   ├── Simulation/
│   └── Export/
├── Shared/
│   ├── Components/
│   └── Extensions/
├── Resources/
│   ├── Assets.xcassets
│   └── Localizable.strings
└── Info.plist
```

### Key Principles

1. **Feature-based organization** — each workspace is a feature folder
2. **@Observable ViewModels** — NOT ObservableObject
3. **Adaptive Layout** — 3-column NavigationSplitView on iPad, native TabView on iPhone
4. **Views are "dumb"** — rendering only
5. **APIClient talks REST**, **WebSocketManager handles real-time**

### SwiftUI Architecture Stack

```
View (renders state)
  ↕ @Binding / @Observable
ViewModel (manages view state, calls services)
  ↕ async/await
Service Layer (WebSocketManager, APIClient)
  ↕ URLSession / WebSocket
Python Backend (FastAPI)
```

---

## Running Locally

```bash
# Backend
cd backend
uv sync                    # Install dependencies
uv run python -m spacy download en_core_web_sm
uv run uvicorn app.main:app --reload --port 8080

# iOS
open ios/AgenticEdTech.xcodeproj
# Run on iPhone or iPad Simulator
```

No Docker needed for local development. Just Python + Xcode.
