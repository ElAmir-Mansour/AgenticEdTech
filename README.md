# Agentic EdTech Platform

> Transform instructional design from manual authoring to human-directed AI orchestration.

## Overview

A native iOS/iPadOS application for e-learning specialists and curriculum developers. Uses a multi-agent AI framework (powered by free Google Gemini) to automate data ingestion, curriculum drafting, and simulation testing.

## Architecture

| Layer | Technology | Cost |
|:---|:---|:---|
| **Client** | SwiftUI (iOS/iPadOS) | Free |
| **Backend** | Python (FastAPI) | Free (DigitalOcean student credit) |
| **LLM** | Google Gemini (AI Studio) | Free |
| **Database** | Neon PostgreSQL | Free |
| **Vector DB** | Qdrant Cloud | Free |

## Documentation

Start here → [`AGENT_CONTEXT.md`](./AGENT_CONTEXT.md) — Master handoff for agents and developers.

All reference docs in `docs/`:
- [`01-architecture.md`](./docs/01-architecture.md) — Two-layer system architecture
- [`02-technology-research.md`](./docs/02-technology-research.md) — 2025/2026 technology research
- [`03-data-models.md`](./docs/03-data-models.md) — Database schemas and data models
- [`04-code-architecture.md`](./docs/04-code-architecture.md) — Python + SwiftUI code patterns
- [`05-ios-design-reference.md`](./docs/05-ios-design-reference.md) — iOS/iPadOS design system
- [`06-cost-and-business.md`](./docs/06-cost-and-business.md) — Cost ($0/month!) and competitive analysis
- [`07-security-and-testing.md`](./docs/07-security-and-testing.md) — Security and testing strategy
- [`08-devops.md`](./docs/08-devops.md) — Deployment (single server, no Docker)
- [`09-roadmap.md`](./docs/09-roadmap.md) — 4-phase development roadmap
- [`10-free-infrastructure.md`](./docs/10-free-infrastructure.md) — Free hosting strategy (GitHub Student Pack)

## Quick Start

```bash
# Backend
cd backend
uv sync
uv run python -m spacy download en_core_web_sm
uv run uvicorn app.main:app --reload --port 8080

# iOS
open ios/AgenticEdTech.xcodeproj
```

## License

Private — All rights reserved.
