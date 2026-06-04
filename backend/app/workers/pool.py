import asyncio
import logging

logger = logging.getLogger(__name__)

class WorkerPool:
    """An asynchronous task execution queue and pool replacing complex external queues for local dev."""
    
    def __init__(self, num_workers: int = 4):
        self.num_workers = num_workers
        self.queue = asyncio.Queue()
        self.workers = []
        self.running = False
        
    async def start(self):
        """Starts worker tasks in the background."""
        self.running = True
        self.workers = [
            asyncio.create_task(self._worker_loop(i))
            for i in range(self.num_workers)
        ]
        logger.info(f"Worker pool started with {self.num_workers} worker threads.")
        
    async def submit(self, func, *args, **kwargs):
        """Pushes a task tuple to the queue."""
        await self.queue.put((func, args, kwargs))
        
    async def _worker_loop(self, worker_id: int):
        """Runs the continuous queue fetch and execute loop."""
        while self.running:
            try:
                func, args, kwargs = await self.queue.get()
                try:
                    if asyncio.iscoroutinefunction(func):
                        await func(*args, **kwargs)
                    else:
                        func(*args, **kwargs)
                except Exception as e:
                    logger.error(f"Worker {worker_id} encountered exception executing job: {str(e)}", exc_info=True)
                finally:
                    self.queue.task_done()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Worker {worker_id} queue fetch error: {str(e)}")
                await asyncio.sleep(1) # prevent hot looping on database/queue faults
                
    async def shutdown(self):
        """Gracefully shuts down the queue and cancels working tasks."""
        self.running = False
        for task in self.workers:
            task.cancel()
        await asyncio.gather(*self.workers, return_exceptions=True)
        logger.info("Worker pool shut down completed.")

# Global worker pool instance
worker_pool = WorkerPool()
