# 03 — Data Models & Schema Design

> **Reference Type**: Permanent schema reference
> **Last Updated**: 2026-06-02

---

## Overview

The data layer uses three storage systems:

| System | Purpose | Data Types |
|:---|:---|:---|
| **PostgreSQL 16** | Event store, projects, users, curriculum, simulation results | Relational + JSONB |
| **Qdrant** | Vector embeddings for RAG retrieval | Vectors + metadata payloads |
| **Redis** | Session cache, semantic cache | Key-value, TTL-based |

---

## PostgreSQL Schemas

### Events Table (Event Sourcing — Source of Truth)

```sql
CREATE TABLE events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  VARCHAR(50) NOT NULL,
    aggregate_id    UUID NOT NULL,
    event_type      VARCHAR(100) NOT NULL,
    event_data      JSONB NOT NULL,
    metadata        JSONB DEFAULT '{}',
    version         INTEGER NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (aggregate_id, version)
);

CREATE INDEX idx_events_aggregate ON events (aggregate_id, version);
CREATE INDEX idx_events_type ON events (event_type, created_at);
```

### Users & Projects

```sql
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) UNIQUE NOT NULL,
    display_name    VARCHAR(100) NOT NULL,
    apple_id        VARCHAR(255) UNIQUE,
    avatar_url      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE projects (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id        UUID NOT NULL REFERENCES users(id),
    title           VARCHAR(255) NOT NULL,
    description     TEXT,
    status          VARCHAR(20) NOT NULL DEFAULT 'draft',
    settings        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    filename        VARCHAR(500) NOT NULL,
    mime_type       VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    storage_path    TEXT NOT NULL,
    processing_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    chunk_count     INTEGER DEFAULT 0,
    metadata        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Agent Sessions & Messages

```sql
CREATE TABLE agent_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_type    VARCHAR(50) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'active',
    langgraph_thread_id VARCHAR(255),
    checkpoint_data JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

CREATE TABLE agent_messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES agent_sessions(id) ON DELETE CASCADE,
    agent_role      VARCHAR(50) NOT NULL,
    message_type    VARCHAR(30) NOT NULL,
    content         TEXT NOT NULL,
    metadata        JSONB DEFAULT '{}',
    sequence_num    INTEGER NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Curriculum Modules & Quizzes

```sql
CREATE TABLE curriculum_modules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_id      UUID REFERENCES agent_sessions(id),
    title           VARCHAR(500) NOT NULL,
    content         TEXT NOT NULL,
    blooms_level    VARCHAR(20),
    sequence_order  INTEGER NOT NULL,
    heatmap_data    JSONB,
    parent_module_id UUID REFERENCES curriculum_modules(id),
    version         INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE quiz_questions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id       UUID NOT NULL REFERENCES curriculum_modules(id) ON DELETE CASCADE,
    question_text   TEXT NOT NULL,
    question_type   VARCHAR(20) NOT NULL,
    options         JSONB,
    correct_answer  TEXT NOT NULL,
    blooms_level    VARCHAR(20),
    difficulty      FLOAT,
    explanation     TEXT,
    sequence_order  INTEGER NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Prerequisite Graph

```sql
CREATE TABLE concepts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    blooms_level    VARCHAR(20),
    source_document_id UUID REFERENCES documents(id),
    source_page     INTEGER,
    embedding_id    VARCHAR(255),
    metadata        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE concept_prerequisites (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    concept_id      UUID NOT NULL REFERENCES concepts(id) ON DELETE CASCADE,
    prerequisite_id UUID NOT NULL REFERENCES concepts(id) ON DELETE CASCADE,
    confidence      FLOAT NOT NULL DEFAULT 0.8,
    relationship    VARCHAR(50) DEFAULT 'requires',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (concept_id, prerequisite_id),
    CHECK (concept_id != prerequisite_id)
);
```

### Simulation Results

```sql
CREATE TABLE simulation_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_id      UUID REFERENCES agent_sessions(id),
    status          VARCHAR(20) NOT NULL DEFAULT 'running',
    persona_count   INTEGER NOT NULL,
    total_questions INTEGER NOT NULL,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

CREATE TABLE persona_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id          UUID NOT NULL REFERENCES simulation_runs(id) ON DELETE CASCADE,
    persona_profile JSONB NOT NULL,
    module_id       UUID NOT NULL REFERENCES curriculum_modules(id),
    question_id     UUID REFERENCES quiz_questions(id),
    passed          BOOLEAN NOT NULL,
    response_text   TEXT,
    confusion_signal TEXT,
    time_estimate_seconds FLOAT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## Qdrant Vector Collections

### document_chunks

```python
{
    "collection_name": "document_chunks",
    "vectors": {"size": 1024, "distance": "Cosine"},
    "payload_schema": {
        "project_id":      {"type": "keyword"},    # CRITICAL for tenant isolation
        "document_id":     {"type": "keyword"},
        "chunk_index":     {"type": "integer"},
        "section_title":   {"type": "text"},
        "page_number":     {"type": "integer"},
        "content":         {"type": "text"},        # for BM25 hybrid search
        "source_filename": {"type": "keyword"},
        "created_at":      {"type": "datetime"}
    }
}
```

### concept_embeddings

```python
{
    "collection_name": "concept_embeddings",
    "vectors": {"size": 1024, "distance": "Cosine"},
    "payload_schema": {
        "project_id":   {"type": "keyword"},
        "concept_id":   {"type": "keyword"},
        "concept_name": {"type": "text"},
        "blooms_level": {"type": "keyword"},
        "description":  {"type": "text"}
    }
}
```

---

## JSON Schemas

### Persona Profile

```json
{
    "persona_id": "uuid",
    "name": "Overwhelmed Beginner",
    "demographics": {
        "age_range": "18-22",
        "education_level": "high_school",
        "native_language": "English",
        "tech_comfort": 0.3
    },
    "cognitive_profile": {
        "blooms_ceiling": "understand",
        "reading_level_grade": 8,
        "attention_span_minutes": 12,
        "working_memory_capacity": "low",
        "preferred_learning_style": "visual"
    },
    "knowledge_state": {
        "known_concepts": ["basic_programming", "variables"],
        "unknown_concepts": ["functions", "classes", "inheritance"],
        "common_misconceptions": [
            "Variables are like boxes that hold values",
            "Functions always return something"
        ]
    },
    "behavioral_constraints": {
        "error_rate_range": [0.3, 0.6],
        "skips_long_paragraphs": true,
        "requires_examples": true,
        "frustration_threshold": 3,
        "gives_up_after_n_failures": 2
    },
    "system_prompt_override": "You are a first-year college student..."
}
```

### WebSocket Message

```json
{
    "type": "agent_output | hitl_request | heatmap_update | simulation_result",
    "workspace": "ingestion | canvas | simulation | dashboard",
    "payload": {},
    "target_user": "uuid | null",
    "timestamp": "ISO8601"
}
```

### Heatmap Data

```json
{
    "paragraphs": [
        {
            "paragraph_index": 0,
            "text_preview": "First 50 chars...",
            "flesch_kincaid": 12.5,
            "token_density": 0.45,
            "avg_sentence_length": 22.3,
            "sentence_variance": 8.1,
            "composite_score": 0.65,
            "color": "#FF9800"
        }
    ]
}
```
