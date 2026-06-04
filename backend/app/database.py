from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import declarative_base
from app.config import settings

DATABASE_URL = settings.DATABASE_URL

# SQLite check for async driver parameters
connect_args = {}
if DATABASE_URL.startswith("sqlite"):
    connect_args["check_same_thread"] = False

engine = create_async_engine(
    DATABASE_URL,
    connect_args=connect_args,
    echo=False,
)

async_session_maker = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

Base = declarative_base()

async def get_db():
    """Dependency for retrieving database session in FastAPI endpoints."""
    async with async_session_maker() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()

async def init_db():
    """Initializes tables for development environments."""
    async with engine.begin() as conn:
        # Import models to register on Base metadata
        import app.models.database
        await conn.run_sync(Base.metadata.create_all)
        
        # Self-healing column addition for database tables
        def add_column_if_missing(connection):
            from sqlalchemy import inspect, text
            inspector = inspect(connection)
            
            # Check simulation_runs
            columns_sr = [col['name'] for col in inspector.get_columns('simulation_runs')]
            if 'meta' not in columns_sr:
                connection.execute(text("ALTER TABLE simulation_runs ADD COLUMN meta JSON DEFAULT '{}';"))
                
            # Check quiz_questions
            columns_qq = [col['name'] for col in inspector.get_columns('quiz_questions')]
            if 'source_info' not in columns_qq:
                connection.execute(text("ALTER TABLE quiz_questions ADD COLUMN source_info TEXT;"))
                
        await conn.run_sync(add_column_if_missing)

