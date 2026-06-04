from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.api import auth, projects, documents, concepts, modules, simulations, export
from app.ws.handler import websocket_endpoint
from app.database import init_db
from app.workers.pool import worker_pool

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handles startup DB migration execution and background worker execution."""
    # Startup
    await init_db()
    await worker_pool.start()
    yield
    # Shutdown
    await worker_pool.shutdown()

app = FastAPI(
    title="Agentic EdTech API",
    version="0.1.0",
    lifespan=lifespan,
)

# Global CORS configurations to allow local iOS simulators to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# API Routers mapping
app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(projects.router, prefix="/api/projects", tags=["projects"])
app.include_router(documents.router, prefix="/api/projects", tags=["documents"])
app.include_router(concepts.router, prefix="/api/projects", tags=["concepts"])
app.include_router(modules.router, prefix="/api/projects", tags=["modules"])
app.include_router(simulations.router, prefix="/api/projects", tags=["simulations"])
app.include_router(export.router, prefix="/api/projects", tags=["export"])

# WebSocket Endpoint mapping
@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket):
    await websocket_endpoint(websocket)

# Health check endpoint
@app.get("/health")
async def health():
    return {"status": "ok"}
