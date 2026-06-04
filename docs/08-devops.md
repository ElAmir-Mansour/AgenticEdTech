# 08 — DevOps & Deployment (Simplified)

> **Reference Type**: Permanent DevOps reference
> **Last Updated**: 2026-06-02
> **Architecture**: Single Python server (no Docker required)

---

## Local Development

### Prerequisites

```bash
# Install uv (Python package manager — replaces pip/poetry)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Python 3.12 (if not already)
brew install python@3.12     # macOS
# or: apt install python3.12  # Ubuntu

# Install Xcode (for iOS development)
# Download from Mac App Store
```

### Running Locally

```bash
# Backend
cd backend
uv sync                                  # Install all dependencies
uv run python -m spacy download en_core_web_sm  # Download NLP model
cp .env.example .env                     # Copy env template
nano .env                                # Add your API keys

uv run uvicorn app.main:app --reload --port 8080
# API running at http://localhost:8080
# WebSocket at ws://localhost:8080/ws
# Docs at http://localhost:8080/docs (Swagger UI)

# iOS
open ios/AgenticEdTech.xcodeproj
# Set API base URL to http://localhost:8080
# Run on iPhone or iPad Simulator (Cmd+R)
```

### Environment Variables (.env)

```bash
# .env (DO NOT COMMIT)
GOOGLE_API_KEY=your-gemini-key-from-aistudio
DATABASE_URL=postgres://user:pass@ep-xxx.neon.tech/edtech?sslmode=require
QDRANT_URL=https://xxx-xxx.aws.cloud.qdrant.io
QDRANT_API_KEY=your-qdrant-key
JWT_SECRET=generate-a-long-random-string
ENVIRONMENT=development
```

---

## Production Deployment (Single Server)

### Architecture

```
Internet → Caddy (:443 HTTPS) → uvicorn (:8080) → FastAPI app
                                                       ↕
                                                  Neon PostgreSQL
                                                  Qdrant Cloud
                                                  Gemini API
```

**No Docker. No Kubernetes. No container orchestration.**
Just Python + Caddy on a single $24/month DigitalOcean Droplet (free with student credits).

### Deployment Steps

See `docs/10-free-infrastructure.md` for the full setup script.

### Process Management (systemd)

```ini
# /etc/systemd/system/edtech.service
[Unit]
Description=EdTech Backend API
After=network.target

[Service]
Type=exec
User=www-data
WorkingDirectory=/opt/edtech/backend
ExecStart=/opt/edtech/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8080 --workers 2
Restart=always
RestartSec=5
EnvironmentFile=/opt/edtech/backend/.env

[Install]
WantedBy=multi-user.target
```

```bash
# Management commands
sudo systemctl start edtech
sudo systemctl stop edtech
sudo systemctl restart edtech
sudo systemctl status edtech
journalctl -u edtech -f    # View logs
```

### Caddy Configuration (Auto-SSL)

```
# /etc/caddy/Caddyfile
api.youredtech.me {
    reverse_proxy localhost:8080
}
```

Caddy automatically provisions and renews Let's Encrypt certificates. Zero config.

---

## Database Migrations

Use **Alembic** for PostgreSQL migrations:

```bash
# Create migration
uv run alembic revision --autogenerate -m "create users table"

# Run migrations
uv run alembic upgrade head

# Rollback
uv run alembic downgrade -1

# View history
uv run alembic history
```

### Migration File Structure

```
backend/migrations/
├── alembic.ini
├── env.py
├── script.py.mako
└── versions/
    ├── 001_create_events.py
    ├── 002_create_users_projects.py
    ├── 003_create_agent_sessions.py
    └── ...
```

---

## CI/CD Pipeline (GitHub Actions)

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v4
      - run: uv sync
      - run: uv run python -m spacy download en_core_web_sm
      - run: uv run pytest tests/unit/ -v --cov

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to server
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: root
          key: ${{ secrets.SSH_KEY }}
          script: |
            cd /opt/edtech
            git pull
            cd backend
            uv sync
            sudo systemctl restart edtech
```

**That's it.** `git push` → tests run → auto-deploy to production.

---

## Monitoring

### Health Check

```bash
# Simple curl check
curl https://api.youredtech.me/health
# {"status": "ok"}

# Uptime monitoring (free)
# Use UptimeRobot.com (free for 50 monitors)
# or use Sentry (Student Pack)
```

### Logs

```bash
# View live logs
journalctl -u edtech -f

# View last 100 lines
journalctl -u edtech -n 100

# View logs from today
journalctl -u edtech --since today
```

### Key Metrics

| Metric | How to Check |
|:---|:---|
| Server alive | `curl /health` |
| Database connected | Check startup logs |
| Gemini API working | Check agent response logs |
| WebSocket connections | Log connected/disconnected events |
| Disk space | `df -h` |
| Memory usage | `free -m` |
| CPU usage | `htop` |

---

## Backup Strategy

| Data | Method | Frequency |
|:---|:---|:---|
| **PostgreSQL** | Neon automatic backups | Continuous (Neon handles it) |
| **Code** | GitHub repository | Every push |
| **Qdrant vectors** | Re-process from source docs | On-demand (docs stored in PostgreSQL) |
| **User uploads** | Store in PostgreSQL or filesystem + backup | Daily |

---

## Deployment Checklist

- [ ] DigitalOcean Droplet created (Ubuntu 24.04, $24/month)
- [ ] Python 3.12 + uv installed
- [ ] Caddy installed and configured
- [ ] Neon PostgreSQL database created
- [ ] Qdrant Cloud cluster created
- [ ] Google AI Studio API key generated
- [ ] Namecheap domain configured (DNS → Droplet IP)
- [ ] `.env` file configured on server
- [ ] `systemd` service running
- [ ] SSL certificate auto-provisioned by Caddy
- [ ] GitHub Actions CI/CD working
- [ ] Health check endpoint responding
