# 02 — Technology Research (2025–2026 Frontier)

> **Reference Type**: Permanent research reference
> **Last Updated**: 2026-06-02
> **Research Horizon**: 2025–2026 academic papers, frameworks, and engineering patterns

---

## 1. Multi-Agent Orchestration & State Management

### LangGraph (Industry Standard, 2026)

**What it is**: Graph-based orchestration framework for stateful multi-agent systems.

**Key features for our platform**:
- **Typed state schemas** via `TypedDict` — all agents interact with data in a predictable format
- **Reducer functions** — concurrent agents can update shared state without race conditions
- **Checkpointing to PostgreSQL** — `PostgresSaver` enables HITL workflows where the graph pauses, persists, and resumes after human approval via `interrupt()`
- **One node = one agent** — Planning, Content, Assessment, Critique each get a dedicated node
- **Conditional edges** — route work based on state (e.g., critique triggers revision or approval)

**Architectural fit**: Agentic Canvas (Workspace 2)
**Integration complexity**: Medium — Python-native, well-documented, requires custom bridge to Go orchestrator via gRPC streaming

### Agent Communication Patterns

| Pattern | Description | Best For |
|:---|:---|:---|
| **Supervisor** | Central "brain" routes tasks to sub-agents | Our agent swarm (Supervisor routes to Planning/Content/etc.) |
| **Handoffs** | Agents explicitly transfer control via state transitions | Sequential workflows (outline → draft → critique) |
| **Debate/Discussion** | Agents accumulate messages in shared state, visible to all | Content vs. Critique agent debate |
| **Deep Agents** | Planning agent spawns sub-graphs for localized logic | Complex module decomposition |

### Agent-to-Agent (A2A) Protocol (Emerging 2025–2026)

Standardizes how agents exchange structured data across frameworks. Useful if we ever need to integrate with external agent ecosystems.

### Model Context Protocol (MCP, 2025)

Standardizes how LLMs access external tools and data sources. Ideal for connecting agents to our RAG repository and external APIs.

### Go Worker Pool (Native)

Bounded concurrency via buffered channels. Prevents goroutine explosion. Natural backpressure mechanism. No external dependency — pure Go patterns.

---

## 2. Graph-Based NLP for Prerequisites

### LLM-Driven Entity-Relation Extraction

**What**: Use GPT-4o/Claude/Gemini to extract competencies and relationships from unstructured text.
**Advantage**: Zero training required. Zero-shot extraction.
**Fit**: Ingestion Vault — Phase 2 MVP
**Complexity**: Low — API-based

### Multi-Criteria Prerequisite Inference (arXiv 2025)

**What**: Combines document features, hyperlink analysis, and graph metrics to infer prerequisite relationships unsupervised.
**Advantage**: No labeled data needed, high precision
**Fit**: Ingestion Vault — Phase 2 enhancement
**Complexity**: Medium — custom pipeline

### Graph Neural Networks (GNNs) for Skill Adjacency

**What**: Models skill dependencies as graph structures and predicts missing edges (gap analysis).
**Advantage**: Proactive curriculum suggestions
**Fit**: Ingestion Vault — Phase 3 advanced feature
**Complexity**: High — requires training data and ML expertise

### spaCy + Custom NER Pipeline

**What**: Fast, production-ready NLP for tokenization, POS tagging, and custom named entity recognition for educational concepts.
**Advantage**: Handles text processing at scale with minimal latency
**Fit**: All NLP features, foundational
**Complexity**: Low

### Recommended Pipeline

```
Raw Document (PDF) → spaCy Pipeline (tokenize, POS, NER)
                   → LLM Extraction (identify competencies & relations)
                   → Knowledge Graph Builder
                   → Topological Sort (sequence prerequisites)
                   → JSON Tree Schema → iOS Client → Interactive Node Graph
```

### Graph Database Options

| Option | Pros | Cons | Recommendation |
|:---|:---|:---|:---|
| **Neo4j** | Industry standard, best docs, Cypher query language | Java-based, heavier footprint | Best for learning & complex queries |
| **Memgraph** | C++ (faster), Cypher compatible, lighter | Smaller community | Great Neo4j alternative |
| **FalkorDB** | In-memory, ultra-low latency, forked from RedisGraph | In-memory = data loss risk | Best for real-time AI/RAG |
| **PostgreSQL + JSON** | No new infra, use existing DB | Limited graph query performance | Good for MVP |

**Decision**: Start with PostgreSQL + JSON for prerequisite graphs in MVP. Migrate to Neo4j or Memgraph if query complexity demands it.

---

## 3. Bloom's Taxonomy Automated Classification

### Zero-Shot LLM Classification

**What**: Modern LLMs classify learning objectives by Bloom's level (~85-90% accuracy out of the box).
**No training data needed**. Just prompt: "Classify this learning objective by Bloom's Taxonomy level."
**Complexity**: Low

### BloomBERT (Open Source, GitHub)

**What**: Fine-tuned DistilBERT model specifically for Bloom's classification.
**Advantage**: Runs locally, faster inference than API calls, better for high-volume.
**Complexity**: Medium

### Recommended Approach: Hybrid

1. **Fast path**: Verb lookup table ("Design" → Create, "Compare" → Analyze) — instant, free
2. **Fallback**: LLM API for ambiguous objectives — accurate, costs ~$0.001 per call
3. **Future**: Fine-tune BloomBERT on your own labeled data for maximum accuracy

### Bloom's Taxonomy Levels (Quick Reference)

| Level | Verbs | Quiz Type |
|:---|:---|:---|
| **Remember** | Define, List, Recall, Identify | Multiple choice, True/False |
| **Understand** | Explain, Summarize, Classify, Compare | Short answer, Matching |
| **Apply** | Use, Implement, Demonstrate, Solve | Problem-solving, Scenarios |
| **Analyze** | Differentiate, Examine, Categorize, Contrast | Case studies, Diagrams |
| **Evaluate** | Judge, Critique, Justify, Assess | Rubric-based, Peer review |
| **Create** | Design, Construct, Develop, Produce | Projects, Portfolios, Build |

---

## 4. RAG Containment & Anti-Hallucination

### The Problem

Basic RAG (embed → search → generate) is **NOT sufficient for production**. Training data can leak through, causing hallucinations that reference information not in the uploaded documents.

### Production-Grade RAG Stack (2026)

| Strategy | Priority | Description |
|:---|:---|:---|
| **Hybrid Search** | P0 | Dense vector search (semantic) + sparse BM25 (keyword). Catches both conceptual and exact matches. |
| **Cross-Encoder Reranking** | P0 | After initial retrieval, rerank chunks with a cross-encoder model. Ensures most relevant content surfaces. |
| **Strict Grounding Prompts** | P0 | System instructions: cite sources, admit insufficient evidence, flag contradictions. |
| **Semantic Chunking** | P0 | Split by headings/sections, not fixed token counts. Preserves context boundaries. |
| **Metadata Filtering** | P0 | Tag chunks with source, version, timestamp, doc type for fine-grained retrieval. |
| **Attribution Verification** | P1 | Parse LLM citations against actual retrieved chunks. Reject unverifiable citations. |
| **Self-RAG Critique Loop** | P1 | LLM verifies: "Does this answer use ONLY the provided context?" |
| **Parent-Document Retrieval** | P1 | Store small chunks for precision, retrieve larger parent section for generation. |

### Vector Database: Qdrant (Selected)

**Why Qdrant**:
- Open-source, self-hostable
- Rust core = exceptional performance
- Native hybrid search (dense + sparse)
- Excellent Python and Go clients
- Payload filtering (critical for project-level data isolation)
- Growing community, well-maintained

### RAG Evaluation Metrics

| Metric | Description | Target |
|:---|:---|:---|
| **Context Adherence** | Does the answer strictly follow retrieved context? | ≥ 90% |
| **Groundedness** | Is the answer supported by sources? | ≥ 90% |
| **Retrieval Precision** | Did we retrieve the correct chunks? | ≥ 80% |
| **Retrieval Recall** | Did we miss any relevant chunks? | ≥ 75% |

---

## 5. Persona Simulation & Cognitive Fidelity

### The Drift Problem

LLM personas lose character consistency during extended interactions (~18 turns).

### Mitigation Strategies

| Strategy | Description | Complexity |
|:---|:---|:---|
| **Full Profile Re-injection** | Send complete persona JSON every turn, not just first message | Low |
| **Knowledge Graph State** | Track what the persona "knows" and "doesn't know" | Medium |
| **Constraint Validation** | Check if response matches persona's reading level and error rate | Medium |
| **Cognitive Prototype Modeling** | Define imperfection profiles: misconceptions, attention patterns | Medium |
| **RLVR (Research-grade)** | Train persona behavior with reinforcement learning | High |

### Persona Profile Structure

Each persona is a structured JSON profile containing:
- Demographics (age, education, language, tech comfort)
- Cognitive profile (Bloom's ceiling, reading level, attention span, working memory)
- Knowledge state (known/unknown concepts, common misconceptions)
- Behavioral constraints (error rate, skip patterns, frustration threshold)
- System prompt override (LLM instructions for this persona)

### SSDataBench Validation

Standardized benchmark for validating that synthetic personas produce statistically realistic behavior. Use as quality gate.

---

## 6. Cognitive Load & Text Diagnostics

### Lightweight Analysis Stack (No GPU Required)

| Metric | Library | Latency | Description |
|:---|:---|:---|:---|
| **Flesch-Kincaid Grade** | Custom (spaCy) | <1ms/para | Standard readability scoring |
| **Token Density** | Custom | <1ms/para | Unique tokens / total tokens — identifies "walls of text" |
| **Sentence Length Variance** | Custom | <1ms/para | Monotony detection — uniform sentences reduce engagement |
| **TRUNAJOD Complexity** | TRUNAJOD (spaCy) | ~10ms/para | Semantic coherence, syntactic complexity, word frequency |
| **Composite Score** | Weighted average | <5ms/para | Normalized 0–1 scale for heatmap |

### Heatmap Color Mapping

| Score | Color | Meaning |
|:---|:---|:---|
| 0.0–0.3 | 🟢 Green (#4CAF50) | Easy, clear text |
| 0.3–0.6 | 🟡 Yellow (#FFC107) | Moderate complexity |
| 0.6–0.8 | 🟠 Orange (#FF9800) | Dense, may need simplification |
| 0.8–1.0 | 🔴 Red (#F44336) | Cognitive overload — requires revision |

### Key Insight

All metrics are **mathematical formulas**, not ML models. They run with near-zero latency and no GPU. Critical for real-time canvas experience.

---

## 7. SCORM & xAPI Packaging

### SCORM Packaging (Go)

Go's `archive/zip` and `encoding/xml` are purpose-built for this:
- Generate `imsmanifest.xml` from internal JSON course structure
- Package HTML5 content + quiz data into SCORM 1.2/2004 compliant ZIP
- Validate with SCORM Cloud test suite

### xAPI (Experience API)

- Generate JSON statements: Actor + Verb + Object model
- Push to Learning Record Store (LRS)
- Recommended LRS: **Yet Analytics SQL LRS** (open-source, PostgreSQL-based)

### Compatibility Strategy

- **SCORM 1.2**: Broadest LMS compatibility (Moodle, Canvas, Blackboard)
- **SCORM 2004**: Complex sequencing support
- **xAPI**: Modern analytics, detailed tracking beyond completion/score

---

## 8. SwiftUI Graph Visualization

### Recommended: Grape Library

**Grape** (SwiftGraphs/Grape on GitHub) — force-directed graph visualization for SwiftUI.

**Architecture**:
1. Define data model (Nodes and Links)
2. Grape simulation engine calculates (x, y) coordinates
3. SwiftUI `Canvas` view draws nodes and links (immediate-mode rendering)
4. Gestures mapped to node data model for interactivity

### Why Canvas API (Not View Hierarchy)

- `Canvas` uses immediate-mode rendering — ideal for 100+ nodes at 60fps
- No SwiftUI `View` per node — vastly better performance
- Combined with `DragGesture` for interactive manipulation

---

## References & Key Papers

| Topic | Source | Year |
|:---|:---|:---|
| Multi-agent state management | LangGraph documentation | 2026 |
| Prerequisite extraction (unsupervised) | arXiv multi-criteria approach | 2025 |
| LLM persona stability | NeurIPS workshop papers | 2025 |
| Synthetic user validation | SSDataBench (PNAS) | 2025 |
| RAG containment strategies | Industry consensus + arXiv | 2025–2026 |
| Cognitive load metrics | TRUNAJOD documentation | 2025 |
| SCORM packaging | SCORM.com developer docs | Ongoing |
| SwiftUI graph visualization | Grape (GitHub) | 2025 |
