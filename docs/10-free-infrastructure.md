# 10 — Free Infrastructure Strategy (Minimal Setup)

> **Reference Type**: Permanent infrastructure reference
> **Last Updated**: 2026-06-02
> **Status**: Master's Student — GitHub Student Developer Pack

---

## Architecture: Maximum Simplicity

```
┌─────────────────────────────────────────────────────────┐
│                 iOS App (iPhone & iPad)                 │
│                      Runs on device — FREE               │
│                                                          │
│            WSS://api.youredtech.me/ws                    │
│                          ↕                               │
├──────────────────────────────────────────────────────────┤
│       DigitalOcean Droplet ($0 with student credit)      │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │         Python (FastAPI + uvicorn)                 │  │
│  │         ONE single process handles:                │  │
│  │         • REST API                                │  │
│  │         • WebSocket                               │  │
│  │         • LangGraph agents                        │  │
│  │         • spaCy NLP                               │  │
│  │         • SCORM/xAPI packaging                    │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  Caddy (reverse proxy + auto-SSL) :443                   │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                  External Free Services                   │
│                                                          │
│  Google AI Studio ─── Gemini API (FREE)                  │
│  Neon ────────────── PostgreSQL (free tier)              │
│  Qdrant Cloud ────── Vector DB (free tier)               │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

**Total services to manage: 1 server + 3 free cloud services. That's it.**

---

## Complete Cost Breakdown: $0/month (except Apple Dev)

| Service | Cost | How |
|:---|:---|:---|
| **LLM (Gemini)** | **$0** | Google AI Studio free tier |
| **Database (PostgreSQL)** | **$0** | Neon free tier (0.5 GB, scales to zero) |
| **Vector DB (Qdrant)** | **$0** | Qdrant Cloud free tier (1 GB, ~1M vectors) |
| **Server** | **$0** | DigitalOcean $200 student credit (8-16 months) |
| **Domain + SSL** | **$0** | Namecheap Student Pack + Let's Encrypt |
| **IDE (GoLand/PyCharm)** | **$0** | JetBrains Student Pack |
| **AI coding assistant** | **$0** | GitHub Copilot Student |
| **Error tracking** | **$0** | Sentry Student Pack |
| **Apple Developer** | **$99/year** | Required for iOS — no free alternative |
| **TOTAL** | **~$8/month** | Only the Apple Dev fee (prorated) |

---

## Google Gemini Free Tier (AI Studio)

### How to Get Your API Key

1. Go to [aistudio.google.com](https://aistudio.google.com/)
2. Sign in with your Google account
3. Click "Get API Key" → "Create API Key"
4. Copy the key → save in `.env` as `GOOGLE_API_KEY`

### Free Tier Limits

| Limit | Value | Impact |
|:---|:---|:---|
| **Requests per minute** | 5-15 RPM | Pace your agent calls |
| **Requests per day** | ~250 RPD | Enough for 10-25 full agent sessions/day |
| **Tokens per minute** | Varies by model | Long documents may need chunked processing |

### Rate Limit Strategy

```python
# app/utils/rate_limiter.py
import asyncio
from datetime import datetime, timedelta

class GeminiRateLimiter:
    """Simple rate limiter for Gemini free tier."""
    
    def __init__(self, max_rpm: int = 10):
        self.max_rpm = max_rpm
        self.requests: list[datetime] = []
        self.lock = asyncio.Lock()
    
    async def acquire(self):
        async with self.lock:
            now = datetime.now()
            # Remove requests older than 1 minute
            self.requests = [r for r in self.requests if now - r < timedelta(minutes=1)]
            
            if len(self.requests) >= self.max_rpm:
                # Wait until oldest request expires
                wait_time = 60 - (now - self.requests[0]).total_seconds()
                if wait_time > 0:
                    await asyncio.sleep(wait_time)
            
            self.requests.append(datetime.now())
```

### Models to Use

| Task | Model | Why |
|:---|:---|:---|
| Agent debate (Planning, Content, Critique) | `gemini-2.0-flash` | Most capable free model |
| Simple classification (Bloom's) | `gemini-2.0-flash-lite` | Fastest, saves rate limit |
| Persona simulation responses | `gemini-2.0-flash-lite` | Many calls, keep it light |
| Long document analysis | `gemini-2.0-flash` | Huge context window |

---

## DigitalOcean Setup (One Server)

### Recommended Droplet

| Size | Cost/Month | Credit Lasts | RAM |
|:---|:---|:---|:---|
| **Basic $12** | $12 | **16 months** | 2 GB |
| **Basic $24** (recommended) | $24 | **8 months** | 4 GB |

### Setup Script

```bash
# 1. Create Droplet: Ubuntu 24.04, Basic $24, nearest region
# 2. SSH in:
ssh root@your-droplet-ip

# 3. Install Python 3.12 + uv
curl -LsSf https://astral.sh/uv/install.sh | sh
apt update && apt install -y python3.12 python3.12-venv

# 4. Install Caddy (reverse proxy with auto-SSL)
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install caddy

# 5. Clone your project
git clone https://github.com/yourusername/E_Learning_Project.git
cd E_Learning_Project/backend

# 6. Install dependencies
uv sync
uv run python -m spacy download en_core_web_sm

# 7. Create .env
cat > .env << 'EOF'
GOOGLE_API_KEY=your-gemini-api-key
DATABASE_URL=postgres://user:pass@ep-xxx.neon.tech/edtech?sslmode=require
QDRANT_URL=https://xxx.qdrant.tech
QDRANT_API_KEY=your-qdrant-key
JWT_SECRET=generate-a-random-secret
EOF

# 8. Run with systemd (auto-restart)
cat > /etc/systemd/system/edtech.service << 'EOF'
[Unit]
Description=EdTech Backend
After=network.target

[Service]
WorkingDirectory=/root/E_Learning_Project/backend
ExecStart=/root/.local/bin/uv run uvicorn app.main:app --host 0.0.0.0 --port 8080
Restart=always
EnvironmentFile=/root/E_Learning_Project/backend/.env

[Install]
WantedBy=multi-user.target
EOF

systemctl enable edtech
systemctl start edtech

# 9. Configure Caddy
cat > /etc/caddy/Caddyfile << 'EOF'
api.youredtech.me {
    reverse_proxy localhost:8080
}
EOF

systemctl restart caddy

# Done! Your API is live at https://api.youredtech.me
```

**No Docker needed.** Just Python running directly with systemd. Simpler = better.

---

## Claim Checklist (Priority Order)

### Must Have
- [ ] GitHub Student Developer Pack (university email)
- [ ] Google AI Studio API Key (Gemini free tier)
- [ ] Neon account (free PostgreSQL)
- [ ] Qdrant Cloud account (free vector DB)
- [ ] DigitalOcean $200 student credit
- [ ] Namecheap free .me domain
- [ ] Apple Developer ($99/year — only paid item)

### Should Have
- [ ] GitHub Copilot (free AI coding)
- [ ] JetBrains (free PyCharm + GoLand)
- [ ] Sentry (free error tracking)
- [ ] 1Password (free API key management)

### Nice to Have
- [ ] Boot.dev (3 months free — learn Python/Go)
- [ ] FrontendMasters (6 months free)
- [ ] Notion (free Education plan)

---

## When Credits Run Out

| Month | Strategy |
|:---|:---|
| **1-8** | DigitalOcean covers server. Everything else free. |
| **9-16** | Switch to Heroku ($13/mo credit, 24 months from Student Pack). |
| **17+** | If product has users → revenue. If learning project → run locally. |
