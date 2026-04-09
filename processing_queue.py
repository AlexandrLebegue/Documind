"""Document processing queue — single-worker FIFO.

All uploads and reprocessing requests are enqueued here instead of being
launched as independent BackgroundTasks.  A single asyncio worker consumes
the queue one job at a time, preventing OOM crashes when many documents are
uploaded at once (e.g. NAS sync).

Public API
----------
ProcessingQueue   — the singleton queue class
get_queue()       — returns the app-level singleton
"""

import asyncio
import logging
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Coroutine, Optional

logger = logging.getLogger(__name__)


class JobStatus(str, Enum):
    PENDING   = "pending"
    PROCESSING = "processing"
    DONE      = "done"
    ERROR     = "error"


@dataclass
class QueueJob:
    id: str
    label: str                          # human-readable name shown in UI
    status: JobStatus = JobStatus.PENDING
    position: int = 0                   # 1-based queue position (0 = processing)
    created_at: float = field(default_factory=time.time)
    started_at: Optional[float] = None
    finished_at: Optional[float] = None
    error: Optional[str] = None
    # Internal: async callable that does the actual work
    _fn: Optional[Callable[[], Coroutine]] = field(default=None, repr=False)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "label": self.label,
            "status": self.status.value,
            "position": self.position,
            "created_at": self.created_at,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "error": self.error,
        }


class ProcessingQueue:
    """Single-worker async FIFO queue for document processing jobs."""

    # How many completed/errored jobs to keep in history for the UI
    _HISTORY_SIZE = 20

    def __init__(self) -> None:
        self._queue: asyncio.Queue[QueueJob] = asyncio.Queue()
        self._active: Optional[QueueJob] = None
        self._history: list[QueueJob] = []          # completed/errored jobs
        self._pending: list[QueueJob] = []           # jobs waiting in queue
        self._lock = asyncio.Lock()
        self._worker_task: Optional[asyncio.Task] = None

    # ------------------------------------------------------------------
    # Public: enqueue
    # ------------------------------------------------------------------

    async def enqueue(
        self,
        label: str,
        fn: Callable[[], Coroutine],
    ) -> QueueJob:
        """Add a job to the queue. Returns the QueueJob immediately."""
        job = QueueJob(
            id=str(uuid.uuid4()),
            label=label,
            _fn=fn,
        )
        async with self._lock:
            self._pending.append(job)
            self._update_positions()
        await self._queue.put(job)
        logger.info("Queued job '%s' (id=%s) — queue size=%d", label, job.id, self._queue.qsize())
        return job

    # ------------------------------------------------------------------
    # Public: status snapshot for API/UI
    # ------------------------------------------------------------------

    def snapshot(self) -> dict:
        """Return a serialisable snapshot of the queue state."""
        active = self._active.to_dict() if self._active else None
        pending = [j.to_dict() for j in self._pending]
        history = [j.to_dict() for j in self._history[-self._HISTORY_SIZE:]]
        return {
            "active": active,
            "pending": pending,
            "history": history,
            "total_pending": len(pending),
            "total_active": 1 if active else 0,
        }

    # ------------------------------------------------------------------
    # Worker lifecycle
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the background worker coroutine. Call once at app startup."""
        if self._worker_task is None or self._worker_task.done():
            self._worker_task = asyncio.create_task(self._worker())
            logger.info("Processing queue worker started")

    def stop(self) -> None:
        """Cancel the worker. Call at app shutdown."""
        if self._worker_task and not self._worker_task.done():
            self._worker_task.cancel()
            logger.info("Processing queue worker stopped")

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    async def _worker(self) -> None:
        """Consume jobs one at a time forever."""
        while True:
            try:
                job = await self._queue.get()
            except asyncio.CancelledError:
                break

            # Mark as active
            async with self._lock:
                if job in self._pending:
                    self._pending.remove(job)
                self._active = job
                self._update_positions()

            job.status = JobStatus.PROCESSING
            job.started_at = time.time()
            job.position = 0
            logger.info("Processing job '%s' (id=%s)", job.label, job.id)

            try:
                await job._fn()
                job.status = JobStatus.DONE
            except Exception as exc:
                job.status = JobStatus.ERROR
                job.error = str(exc)
                logger.error("Job '%s' failed: %s", job.label, exc)
            finally:
                job.finished_at = time.time()
                async with self._lock:
                    self._active = None
                    self._history.append(job)
                    if len(self._history) > self._HISTORY_SIZE:
                        self._history = self._history[-self._HISTORY_SIZE:]
                    self._update_positions()
                self._queue.task_done()
                logger.info(
                    "Job '%s' finished — status=%s in %.1fs",
                    job.label, job.status.value,
                    (job.finished_at or 0) - (job.started_at or 0),
                )

    def _update_positions(self) -> None:
        """Recompute 1-based positions for all pending jobs."""
        for i, job in enumerate(self._pending):
            job.position = i + 1


# ---------------------------------------------------------------------------
# App-level singleton
# ---------------------------------------------------------------------------

_queue: Optional[ProcessingQueue] = None


def get_queue() -> ProcessingQueue:
    global _queue
    if _queue is None:
        _queue = ProcessingQueue()
    return _queue
