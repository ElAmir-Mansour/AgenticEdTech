from fastapi import WebSocket
import json

class ConnectionManager:
    """Manages WebSocket connections, replacing the original Go WebSocket Hub."""
    
    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}
    
    async def connect(self, user_id: str, websocket: WebSocket):
        """Accepts the websocket connection and registers the user."""
        await websocket.accept()
        self.active_connections[user_id] = websocket
    
    def disconnect(self, user_id: str):
        """Removes the user from active connections."""
        self.active_connections.pop(user_id, None)
    
    async def send_to_user(self, user_id: str, message: dict):
        """Sends a JSON message to a specific active user connection."""
        ws = self.active_connections.get(user_id)
        if ws:
            try:
                await ws.send_json(message)
            except Exception:
                self.disconnect(user_id)
    
    async def broadcast(self, message: dict):
        """Broadcasts a JSON message to all connected clients."""
        disconnected = []
        for user_id, ws in list(self.active_connections.items()):
            try:
                await ws.send_json(message)
            except Exception:
                disconnected.append(user_id)
        for uid in disconnected:
            self.disconnect(uid)

# Global connection manager instance
ws_manager = ConnectionManager()
