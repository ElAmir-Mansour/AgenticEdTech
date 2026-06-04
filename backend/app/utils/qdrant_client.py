import os
import logging
from qdrant_client import QdrantClient
from app.config import settings

logger = logging.getLogger(__name__)

# Thread-safe global QdrantClient instance
_qdrant_client = None

def get_qdrant_client() -> QdrantClient:
    """Returns a configured QdrantClient instance.
    
    Falls back to a local storage directory (`./qdrant_db`) if QDRANT_URL is not set.
    """
    global _qdrant_client
    if _qdrant_client is not None:
        return _qdrant_client
        
    url = settings.QDRANT_URL
    api_key = settings.QDRANT_API_KEY
    
    if url:
        logger.info(f"Connecting to remote Qdrant database at {url}")
        _qdrant_client = QdrantClient(url=url, api_key=api_key)
    else:
        # Local persistent storage fallback
        local_db_path = os.path.abspath(os.path.join(os.getcwd(), "qdrant_db"))
        logger.info(f"QDRANT_URL not configured. Using local persistent storage: {local_db_path}")
        os.makedirs(local_db_path, exist_ok=True)
        _qdrant_client = QdrantClient(path=local_db_path)
        
    return _qdrant_client
