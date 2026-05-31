"""Ring buffer for dashboard log streaming.

Captures loguru log records into a fixed-size deque. The dashboard
polls /api/logs?since=N to fetch new entries since a given index.

Usage:
    buffer = LogBuffer()
    logger.add(buffer.sink)       # register as loguru sink
    entries = buffer.since(42)    # get entries after index 42
"""

from __future__ import annotations

import threading
import time
from collections import deque
from dataclasses import dataclass, field


@dataclass
class LogEntry:
    """Single log entry for dashboard display."""
    index: int
    time: str
    level: str
    message: str


class LogBuffer:
    """Thread-safe ring buffer for log entries.

    Stores the most recent [maxlen] log records. Each entry has a
    monotonic index so the dashboard can request only new entries
    since its last poll.

    Args:
        maxlen: Maximum number of entries to keep.
    """

    def __init__(self, maxlen: int = 500):
        self._buffer: deque[LogEntry] = deque(maxlen=maxlen)
        self._lock = threading.Lock()
        self._index = 0

    def sink(self, message) -> None:
        """Loguru sink function — called for each log record.

        Args:
            message: Loguru message object with .record attribute.
        """
        record = message.record
        t = record["time"].strftime("%H:%M:%S")
        level = record["level"].name
        text = record["message"]

        with self._lock:
            self._index += 1
            self._buffer.append(LogEntry(
                index=self._index,
                time=t,
                level=level,
                message=text,
            ))

    def since(self, after_index: int = 0) -> list[dict]:
        """Get log entries after the given index.

        Args:
            after_index: Return entries with index > this value.
                Pass 0 to get all buffered entries.

        Returns:
            List of log entry dicts with keys: index, time, level, message.
        """
        with self._lock:
            entries = [
                {"index": e.index, "time": e.time, "level": e.level, "message": e.message}
                for e in self._buffer
                if e.index > after_index
            ]
        return entries

    @property
    def latest_index(self) -> int:
        """The index of the most recent entry."""
        with self._lock:
            return self._index
