# 01 — System Architecture Deep Dive (Simplified)

> **Reference Type**: Permanent architectural reference
> **Last Updated**: 2026-06-02
> **Architecture**: Single Python backend + SwiftUI iOS client

---

## The Two-Layer Architecture

```
  ┌─────────────────────────────────────────────────────┐
  │           🍎 CLIENT LAYER — SwiftUI                 │
  │                                                     │
  │  • Reactive UI with @Observable                     │
  │  • WebSocket manager for real-time updates          │
  │  • Canvas renderer (force-directed graphs)          │
  │  • Heatmap overlay (Core Graphics)                  │
  │  • REST client for CRUD operations                  │
  │                                                     │
  │  Communicates via: WebSocket + REST ↕               │
  ├─────────────────────────────────────────────────────┤
  │           🐍 BACKEND — Python (FastAPI)             │
  │                                                     │
  │  • FastAPI REST API (auth, CRUD, uploads)           │
  │  • FastAPI WebSocket (real-time agent streaming)    │
  │  • LangGraph multi-agent runtime                    │
  │  • Gemini LLM via langchain-google-genai            │
  │  • spaCy NLP pipeline                               │
  │  • Qdrant RAG retrieval                             │
  │  • Cognitive load analyzer                          │
  │  • SCORM/xAPI packager (zipfile + xml.etree)        │
  │  • Persona simulator                                │
  │                                                     │
  ├─────────────────────────────────────────────────────┤
  │           🗄️ DATA LAYER (all free tier)             │
  │                                                     │
  │  Neon PostgreSQL — projects, users, events          │
  │  Qdrant Cloud   — vector embeddings for RAG         │
  │                                                     │
  └─────────────────────────────────────────────────────┘
```

## Why Single Python Backend?

| Concern | Answer |
|:---|:---|
| **"Python is slow for WebSockets"** | FastAPI + uvicorn handles thousands of concurrent connections. We need maybe 5-50 users at MVP. |
| **"Go is better for concurrency"** | True at 10K+ connections. Completely irrelevant at our scale. Python asyncio is plenty. |
| **"Need gRPC between services"** | No separate services → no gRPC needed. Everything in one process. |
| **"What about the worker pool?"** | Python asyncio task queue replaces Go goroutine pool. Same pattern, one language. |
| **"SCORM packaging needs Go?"** | Python's `zipfile` + `xml.etree.ElementTree` do the same thing. No need for Go's archive/zip. |

**Bottom line**: One language = one codebase = one Docker container = one server = less complexity = faster development = cheaper infrastructure.

---

## Communication Protocols

### REST API (CRUD Operations)

**Purpose**: Standard request-response for data operations.

**Endpoints**:
```
POST   /api/auth/apple          # Apple Sign In
POST   /api/auth/refresh        # Refresh JWT token

GET    /api/projects             # List projects
POST   /api/projects             # Create project
GET    /api/projects/{id}        # Get project details
DELETE /api/projects/{id}        # Delete project

POST   /api/projects/{id}/documents      # Upload document
GET    /api/projects/{id}/documents      # List documents
GET    /api/projects/{id}/concepts       # Get prerequisite graph
GET    /api/projects/{id}/modules        # Get curriculum modules

POST   /api/projects/{id}/export/scorm   # Export SCORM package
POST   /api/projects/{id}/export/xapi    # Export xAPI statements

GET    /api/projects/{id}/simulations    # List simulation runs
POST   /api/projects/{id}/simulations    # Start new simulation
```

### WebSocket (Real-Time Streaming)

**Purpose**: Full-duplex channel for agent output, HITL, and live updates.

**Connection**: `wss://api.youredtech.me/ws?token={jwt_token}`

**Message Types (Server → Client)**:
```json
{"type": "agent_output",     "agent": "planning",  "content": "..."}
{"type": "agent_output",     "agent": "content",   "content": "..."}
{"type": "agent_output",     "agent": "critique",  "content": "..."}
{"type": "hitl_request",     "checkpoint_id": "...", "description": "..."}
{"type": "heatmap_update",   "module_id": "...",   "paragraphs": [...]}
{"type": "simulation_result","persona": "...",     "result": {...}}
{"type": "processing_status","document_id": "...", "status": "completed"}
```

**Message Types (Client → Server)**:
```json
{"type": "hitl_response",    "checkpoint_id": "...", "decision": "approve"}
{"type": "start_session",    "project_id": "...",    "session_type": "curriculum_draft"}
{"type": "start_simulation", "project_id": "...",    "personas": [...]}
```

---

## LLM Strategy: Google Gemini (Free)

### Why Gemini?

| Feature | Gemini | OpenAI/Anthropic |
|:---|:---|:---|
| **Cost** | **$0** (AI Studio free tier) | $20-50+/month |
| **Context window** | Up to 2M tokens | 128K-200K tokens |
| **Function calling** | Native support | Supported |
| **LangChain support** | `langchain-google-genai` | Supported |
| **Rate limits (free)** | 5-15 RPM, 250 RPD | No free tier |
| **Multimodal** | Text, images, audio, video | Varies |

### Model Selection

| Task | Model | Why |
|:---|:---|:---|
| **Agent thinking** (Planning, Content, Critique) | `gemini-2.0-flash` | Fast, capable, free |
| **Simple tasks** (Bloom's classification, persona responses) | `gemini-2.0-flash-lite` | Fastest, lowest rate limit usage |
| **Long document analysis** | `gemini-2.0-flash` | 1M+ token context window |

### Rate Limit Management

Free tier limits: ~5-15 RPM, ~250 RPD. Strategies:

1. **Request batching** — combine multiple small requests into one
2. **Caching** — cache identical/similar requests in PostgreSQL
3. **Queue with backoff** — async queue with exponential backoff on 429 errors
4. **Smart model routing** — use `flash-lite` for simple tasks to save RPM for complex ones
5. **Offline processing** — batch non-urgent tasks during low-usage periods

### Integration Code

```python
from langchain_google_genai import ChatGoogleGenerativeAI

# Initialize Gemini model
llm = ChatGoogleGenerativeAI(
    model="gemini-2.0-flash",
    google_api_key=settings.GOOGLE_API_KEY,
    temperature=0.7,
    max_output_tokens=8192,
)

# Use with LangGraph — same as any other LangChain LLM
from langgraph.prebuilt import create_react_agent
agent = create_react_agent(llm, tools=[...])
```

---

## Async Worker Pattern (Replaces Go Worker Pool)

Instead of Go goroutines + channels, use Python asyncio + task queue:

```python
import asyncio
from collections import deque

class AsyncWorkerPool:
    def __init__(self, max_workers: int = 5):
        self.semaphore = asyncio.Semaphore(max_workers)
        self.active_tasks: dict[str, asyncio.Task] = {}

    async def submit(self, task_id: str, coro):
        async def _run():
            async with self.semaphore:
                return await coro
        
        task = asyncio.create_task(_run())
        self.active_tasks[task_id] = task
        task.add_done_callback(lambda t: self.active_tasks.pop(task_id, None))
        return task

    async def shutdown(self):
        for task in self.active_tasks.values():
            task.cancel()
        await asyncio.gather(*self.active_tasks.values(), return_exceptions=True)
```

Same backpressure concept as Go channels, but with `asyncio.Semaphore`.

---

## Event Flow (Simplified)

```
1. iOS (iPhone/iPad) sends request via REST or WebSocket
2. FastAPI handler validates JWT and request
3. For agent tasks: submit to AsyncWorkerPool
4. Worker calls LangGraph → Gemini API
5. LangGraph streams output via callback
6. Callback pushes messages through WebSocket to iOS client
7. State changes persisted to Neon PostgreSQL
8. Vector operations go to Qdrant Cloud
```

---

## HITL State Machine (Python)

Same logic as before, but now in Python instead of Go:

```
initialized → planning_active → awaiting_approval
                                      ↓ (approved)     ↓ (rejected)
                                content_drafting    planning_active
                                      ↓
                                critique_review ← revision (loop, max 3)
                                      ↓ (passed)
                                assessment_generation
                                      ↓
                                final_review
                                      ↓ (approved)     ↓ (rejected)
                                completed          content_drafting
```

Each transition emits a WebSocket message to the iOS (iPhone/iPad) client.
