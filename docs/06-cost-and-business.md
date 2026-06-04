# 06 — Cost Modeling & Competitive Analysis

> **Reference Type**: Permanent business reference
> **Last Updated**: 2026-06-02
> **LLM Strategy**: Google Gemini free tier (AI Studio)

---

## Competitive Landscape (2026)

### Direct Competitors

| Competitor | What They Do | Missing Capabilities |
|:---|:---|:---|
| **Courseau** | PDF → SCORM course | No agent debate, no prerequisite mapping |
| **Mindsmith** | AI course authoring | No multi-agent system, no RAG |
| **Coursebox** | AI course + quizzes | No cognitive load analysis, no simulation |
| **360Learning** | Collaborative L&D | No agentic AI, no prerequisite graphs |
| **Docebo (Shape)** | Enterprise LMS + AI | Monolithic SaaS, no open architecture |

### Our 4 Unfair Advantages

1. **Multi-Agent Debate with HITL** — agents argue before human approval
2. **Prerequisite Knowledge Graphs** — automated dependency mapping from PDFs
3. **Cognitive Load Heatmaps** — real-time text complexity visualization
4. **Synthetic Student Simulation** — AI personas stress-test curriculum

---

## Cost: $0/month (Gemini Free Tier)

### All LLM Operations — FREE

| Operation | Model | Cost |
|:---|:---|:---|
| Prerequisite Extraction | Gemini 2.0 Flash | **$0** |
| Bloom's Classification | Gemini 2.0 Flash Lite | **$0** |
| Planning Agent | Gemini 2.0 Flash | **$0** |
| Content Agent | Gemini 2.0 Flash | **$0** |
| Critique Agent | Gemini 2.0 Flash | **$0** |
| Assessment Agent | Gemini 2.0 Flash | **$0** |
| Persona Simulation | Gemini 2.0 Flash Lite | **$0** |
| RAG Generation | Gemini 2.0 Flash | **$0** |

### Gemini Free Tier Limits

| Limit | Value |
|:---|:---|
| Requests per minute | 5-15 RPM |
| Requests per day | ~250 RPD |
| Context window | 1M+ tokens |

### What 250 RPD Gets You

| Usage | Requests Used | Sessions/Day |
|:---|:---|:---|
| Full agent session (plan+content+critique+assess) | ~15-20 requests | **12-15 sessions/day** |
| Document ingestion (per document) | ~5-10 requests | **25-50 documents/day** |
| Persona simulation (5 personas × 5 questions) | ~25-30 requests | **8-10 simulations/day** |

**For a solo developer or small team, the free tier is more than enough.**

### Total Monthly Costs

| Item | Cost |
|:---|:---|
| LLM (Gemini) | $0 |
| PostgreSQL (Neon) | $0 |
| Vector DB (Qdrant Cloud) | $0 |
| Server (DigitalOcean student credit) | $0 |
| Domain (Namecheap student) | $0 |
| Error tracking (Sentry student) | $0 |
| Apple Developer | $8.25/month ($99/year) |
| **TOTAL** | **$8.25/month** |

### If You Outgrow Free Tier

| Upgrade | When | Cost |
|:---|:---|:---|
| Gemini Tier 1 (paid) | >250 requests/day consistently | Pay-per-token (very cheap) |
| Neon Pro | >0.5 GB database | $19/month |
| Qdrant Standard | >1M vectors | ~$25/month |

---

## Business Models (Future)

| Model | Description |
|:---|:---|
| **SaaS Subscription** | $29-199/month per seat |
| **Open-Source + Premium** | Core free, advanced agents paid |
| **API-as-a-Service** | Expose RAG + Agent engine as APIs |
