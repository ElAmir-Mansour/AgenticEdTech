# 07 — Security Architecture & Testing Strategy

> **Reference Type**: Permanent security & QA reference
> **Last Updated**: 2026-06-02

---

## Part 1: Security Architecture

### Authentication Flow

```
1. User taps "Sign In with Apple" on iPhone or iPad
2. Apple returns Identity Token (JWT) to app
3. App sends Identity Token to FastAPI: POST /api/auth/apple
4. FastAPI verifies token (signature, audience, issuer) with Apple's servers
5. FastAPI upserts user in Neon PostgreSQL
6. FastAPI returns: {access_token (short-lived JWT), refresh_token}
7. All subsequent REST requests include Bearer token
8. WebSocket connects with token: ws://host/ws?token={access_token}
```

### JWT Structure

```json
{
    "sub": "user-uuid",
    "email": "user@example.com",
    "exp": 1735689600,
    "iat": 1735686000,
    "iss": "agentic-edtech-api"
}
```

- **Access Token**: 15 minutes TTL
- **Refresh Token**: 30 days TTL, stored in iOS Keychain

### Authorization Model (RBAC)

| Role | Permissions |
|:---|:---|
| **Owner** | Full CRUD on project + all children |
| **Editor** | Read/Write curriculum, Run simulations |
| **Viewer** | Read-only access |

### Data Isolation Rules

| Rule | Enforcement |
|:---|:---|
| ALL Qdrant queries MUST include `project_id` filter | RAG retriever module |
| ALL PostgreSQL queries MUST include `project_id` in WHERE | SQLAlchemy models |
| LLM system prompts enforce source-only answers | Agent prompt templates |
| LLM outputs pass through attribution checker | Containment module |

### Security Checklist

| Control | Priority | Status |
|:---|:---|:---|
| TLS via Caddy (auto Let's Encrypt) | P0 | ⬜ |
| Apple Sign In + JWT | P0 | ⬜ |
| Project-scoped RBAC | P0 | ⬜ |
| Qdrant project_id filtering | P0 | ⬜ |
| Pydantic input validation | P0 | ⬜ |
| File upload: MIME validation, 50MB limit | P1 | ⬜ |
| Gemini rate limit handling | P1 | ⬜ |
| Audit logging | P1 | ⬜ |
| Environment variables for secrets | P0 | ⬜ |

---

## Part 2: Testing Strategy

### Testing Pyramid

```
         🔺 E2E Tests (5-10 flows)
      🔶 Integration Tests (~30 tests)
    🟩 Unit Tests (150+ tests)
```

### Unit Tests

| Module | What to Test | Examples |
|:---|:---|:---|
| `analysis/` | Cognitive load formulas, readability | `test_flesch_kincaid_grade` |
| `agents/` | State transitions, prompt construction | `test_hitl_state_machine` |
| `ingestion/` | Chunking logic, Bloom's classifier | `test_semantic_chunking` |
| `packaging/` | SCORM manifest, xAPI statements | `test_scorm_manifest_valid` |
| `auth/` | JWT creation/validation | `test_jwt_expiry` |
| SwiftUI | ViewModels, WebSocket parsing, heatmap colors | `testHeatmapColorMapping` |

### Integration Tests

| Test | Purpose |
|:---|:---|
| FastAPI + PostgreSQL | CRUD operations, event persistence |
| FastAPI + Qdrant | Document ingestion → vector search |
| WebSocket E2E | Connect → subscribe → receive stream |
| Gemini API | Agent graph execution end-to-end |

### LLM Evaluation

| Metric | Method | Target |
|:---|:---|:---|
| Context Adherence | LLM-as-judge | ≥ 90% |
| Bloom's Accuracy | Golden dataset (100 labeled) | ≥ 85% |
| Persona Consistency | Constraint checker | ≥ 80% |
| Heatmap Accuracy | Known-complexity corpus | ±10% |

### Test Commands

```bash
# Python unit tests
cd backend && uv run pytest tests/unit/ -v --cov

# Python integration tests
cd backend && uv run pytest tests/integration/ -v

# LLM evaluation
cd backend && uv run pytest tests/eval/ -v

# Swift unit tests (iPhone & iPad)
xcodebuild test -scheme AgenticEdTech -destination 'platform=iOS Simulator,name=iPhone 15' -destination 'platform=iOS Simulator,name=iPad Pro'
```
