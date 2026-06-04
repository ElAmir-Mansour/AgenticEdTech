import asyncio
from datetime import datetime, timedelta

class GeminiRateLimiter:
    """Simple rate limiter for Gemini free tier to respect requests-per-minute limits."""
    
    def __init__(self, max_rpm: int = 15):
        self.max_rpm = max_rpm
        self.requests: list[datetime] = []
        self.lock = asyncio.Lock()
    
    async def acquire(self):
        """Blocks execution if request frequency exceeds max_rpm until sliding window frees up."""
        async with self.lock:
            now = datetime.now()
            # Filter out requests older than 1 minute
            self.requests = [r for r in self.requests if now - r < timedelta(minutes=1)]
            
            if len(self.requests) >= self.max_rpm:
                # Wait until the oldest request in the window falls outside the 1 minute duration
                wait_time = 60.0 - (now - self.requests[0]).total_seconds()
                if wait_time > 0:
                    await asyncio.sleep(wait_time)
            
            # Record current timestamp
            self.requests.append(datetime.now())

# Global rate limiter instance (default to 10 RPM to remain safely within the 15 RPM limit)
gemini_rate_limiter = GeminiRateLimiter(max_rpm=10)
