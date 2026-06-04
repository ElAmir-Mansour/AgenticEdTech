# 09 — Development Roadmap

> **Reference Type**: Living document — update as milestones are completed
> **Last Updated**: 2026-06-03
> **Client Policy**: Dual support for both iPhone and iPad layout form-factors.

---

## Overview

5 phases, ~40 weeks total. Each phase delivers user-facing value.

---

## Phase 1: Foundation (Weeks 1–6)

**Goal**: Establish the core client-server architecture with REST and WebSocket end-to-end communication.

| Task | Technology | Status |
|:---|:---|:---|
| FastAPI Project Scaffold | Python 3.11+, FastAPI | ✅ Completed |
| WebSocket Connection Manager | websockets, ConnectionManager | ✅ Completed |
| Database Connection Layer | SQLAlchemy Async, aiosqlite/asyncpg | ✅ Completed |
| SQLAlchemy ORM Table Declarations | User, Project, Module, etc. | ✅ Completed |
| Client-side Network Integration | APIClient (REST) | ✅ Completed |
| Client-side Real-time Integration | WebSocketManager | ✅ Completed |
| Client Observable State Setup | Swift @Observable AppState | ✅ Completed |
| Design Tokens & Color Palettes | DesignTokens.swift | ✅ Completed |
| User Signup/Login & Apple Auth Stub | FastAPI routers, JWT | ✅ Completed |
| Project CRUD API endpoints | REST router controllers | ✅ Completed |

**Milestone**: User opens iPhone or iPad app → authenticates → creates project → sends WebSocket Ping and receives PONG back in real-time.

---

## Phase 2: Ingestion Vault (Weeks 7–14)

**Goal**: Users upload documents, extract knowledge graphs, and build a grounding RAG repository.

| Task | Technology | Status |
|:---|:---|:---|
| PDF parsing pipeline | PyMuPDF, pdfplumber | ✅ Completed |
| Semantic chunking | Custom (heading-based) | ✅ Completed |
| Qdrant setup + collection creation | Qdrant Cloud | ✅ Completed |
| Embedding pipeline | sentence-transformers | ✅ Completed |
| Hybrid search (dense + BM25) | Qdrant hybrid | ✅ Dense search completed |
| Cross-encoder reranking | cross-encoder model | ⬜ Not Started |
| Prerequisite graph extraction | spaCy + LLM (Gemini) | ✅ Completed |
| Bloom's taxonomy classifier | LLM zero-shot + verb lookup | ✅ Completed |
| RAG containment (grounding prompts) | Python containment module | ✅ Completed |
| iOS Node graph view (iPad) | SwiftUI Canvas | ✅ Completed |
| iOS Document upload UI (iPhone/iPad) | SwiftUI adaptive | ✅ Completed |
| iOS RAG vault query UI (iPhone/iPad) | SwiftUI adaptive | ✅ Completed |

**Milestone**: Upload Swift programming textbook from iPhone or iPad → see interactive concept dependency graph → ask questions answered and verified ONLY from the uploaded document.

---

## Phase 3: Agentic Canvas (Weeks 15–22)

**Goal**: AI agents collaboratively draft curriculum with human oversight.

| Task | Technology | Status |
|:---|:---|:---|
| LangGraph agent graph definition | LangGraph | ✅ Completed |
| Planning Agent (system prompt + node) | LangGraph + Gemini-2.0-flash | ✅ Completed |
| Content Agent | LangGraph + Gemini-2.0-flash | ✅ Completed |
| Assessment Agent | LangGraph + Gemini-2.0-flash | ✅ Completed |
| Critique Agent | LangGraph + Gemini-2.0-flash | ✅ Completed |
| Supervisor / Router node | LangGraph conditional edges | ✅ Completed |
| Shared state + reducers | LangGraph TypedDict | ✅ Completed |
| LangGraph checkpointing to PostgreSQL | PostgresSaver / asyncpg | 🔄 In-memory checkpointing |
| HITL state machine | LangGraph Postgres checkpointer | ✅ Completed (MemorySaver) |
| Real-time agent stream (FastAPI → client)| WebSocket streaming | ✅ Completed |
| Real-time agent output in SwiftUI | WebSocket + streaming UI | ✅ Completed |
| HITL approval UI (iPhone/iPad) | HITLApprovalCard | ✅ Completed |
| Cognitive load heatmap (Python) | TRUNAJOD + spaCy | ✅ Completed |
| Heatmap overlay (iPhone/iPad SwiftUI) | Custom Paragraph Overlay | ✅ Completed |

**Milestone**: Request "Create module on Agile" on iPhone or iPad → watch agents debate in real-time → approve outline → receive complete module with quiz → view cognitive load complexity colors.

---

## Phase 4: Simulation & Dashboard (Weeks 23–30)

**Goal**: Test curriculum with synthetic student personas, export to standard LMS, and monitor live metrics.

| Task | Technology | Status |
|:---|:---|:---|
| Persona engine (Python) | Constrained LLM prompting | ✅ Completed |
| Persona profile JSON schema | Pydantic validation | ✅ Completed |
| Response constraint validator | Custom Python | ✅ Completed |
| Simulation runner (FastAPI workers) | Async worker pool | ✅ Completed |
| Simulation results aggregation | SQLAlchemy Async | ✅ Completed |
| iOS Simulation UI (iPhone/iPad) | SwiftUI | ✅ Completed |
| SCORM 1.2 packager | zipfile + xml.etree | ✅ Completed |
| SCORM 2004 packager | zipfile + xml.etree | ⬜ Not Started |
| xAPI statement generator | JSON payload + HTTP client | ⬜ Not Started |
| imsmanifest.xml generator | xml.etree templates | ✅ Completed |
| Telemetry API endpoint | FastAPI router | ✅ Completed (metrics) |
| Threshold-based alerting | FastAPI background tasks | ⬜ Not Started |
| Dashboard UI (iPhone/iPad SwiftUI) | SwiftUI Charts | ✅ Completed |
| iOS Export UI (iPhone/iPad) | SwiftUI ShareLink | ✅ Completed |
| Integration testing (full pipeline) | pytest + mock clients | ✅ Completed (23/23) |
| SCORM compliance validation | SCORM Cloud test suite | ⬜ Not Started |

**Milestone**: Run 5 synthetic student personas on iPhone or iPad against the Agile module → view quiz fail points → export SCORM zip archive → upload to LMS → receive telemetry performance alerts on your mobile dashboard.

---

## Phase 5: On-Device Offline Study Mode (Weeks 31–40)

**Goal**: Bring the full RAG search experience to students completely offline using Apple-native frameworks — zero cloud dependency, zero network latency, maximum privacy.

> **Architecture Decision (2026-06-03)**: Evaluated replacing Qdrant Cloud with an Apple-native on-device vector pipeline. Full replacement is infeasible because the LangGraph multi-agent canvas, persona simulations, and ingestion NLP pipelines require a Python runtime. Instead, adopt a **hybrid model**: server handles curriculum generation (teacher-facing), device handles offline study search (student-facing).

### Why Now Isn't the Right Time
- Core platform stability comes first (hosting, Apple Sign-In provisioning, SCORM validation)
- `NLContextualEmbedding` requires iOS 18+ — too restrictive for current user base
- Mixing on-device and server-side embeddings requires careful vector space alignment

### Implementation Plan

| Task | Technology | Status |
|:---|:---|:---|
| Download & sync generated modules to SwiftData | SwiftData + `ModelContainer` | ⬜ Not Started |
| Local embedding of downloaded module text | `NLContextualEmbedding` (iOS 18+) | ⬜ Not Started |
| Local vector store (chunk → embedding) | `SwiftData` + `[Float]` stored as `Data` | ⬜ Not Started |
| Cosine similarity search (on-device) | `Accelerate.vDSP` (SIMD optimized) | ⬜ Not Started |
| Offline-first query result display | SwiftUI (reuse RAGQueryView components) | ⬜ Not Started |
| Graceful fallback: offline → server RAG | Reachability check before query dispatch | ⬜ Not Started |
| Optional Apple Intelligence summary | `Foundation Models` (iOS 18.1+, Apple Silicon only) | ⬜ Not Started |
| Sync conflict resolution (server vs. device) | Last-write-wins + module versioning | ⬜ Not Started |
| Storage quota management & LRU eviction | Local `@AppStorage` policy settings | ⬜ Not Started |
| Integration tests for offline search | XCTest + mock `NLContextualEmbedding` | ⬜ Not Started |

**Milestone**: Student with no Wi-Fi opens the app → selects a downloaded curriculum module → searches "What is Bloom's taxonomy?" → receives instant, grounded answer from on-device vector store in < 100ms.

### Key Technical Notes

```
On-Device RAG Stack:
  NLContextualEmbedding  ──▶  vDSP cosine similarity (Accelerate)
         ↕                            ↕
  SwiftData (chunks + vectors)   Foundation Models (summarization)

Server RAG Stack (unchanged):
  SentenceTransformers   ──▶  Qdrant (Local disk or Cloud)
         ↕
  FastAPI + LangGraph agents
```

> ⚠️ **Embedding Mismatch**: `NLContextualEmbedding` produces different vector spaces than `all-MiniLM-L6-v2`. Do NOT mix — device vectors are only compared to other device vectors, server vectors are only compared to server vectors.

---

## Post-Launch

| Task | Priority | Status |
|:---|:---|:---|
| Performance optimization | P1 | ⬜ |
| macOS support (Catalyst or native) | P2 | ⬜ |
| Team collaboration (multi-user editing) | P2 | ⬜ |
| Custom LLM model fine-tuning | P3 | ⬜ |
| Video transcript support | P2 | ⬜ |
| Multi-language support | P3 | ⬜ |
| Open-source Ingestion Vault library | P2 | ⬜ |
| API-as-a-Service offering | P3 | ⬜ |
| On-device quantized teacher model (MLX) | P3 | ⬜ |
| watchOS study reminders + streak tracking | P3 | ⬜ |

---

## Legend

- ⬜ Not Started
- 🔄 In Progress
- ✅ Completed
- ❌ Blocked
