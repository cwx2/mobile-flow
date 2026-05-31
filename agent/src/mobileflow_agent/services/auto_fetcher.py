"""Auto fetcher — periodically runs git fetch in the background.

Module: services/
Responsibility:
    Keeps the local repository in sync with the remote by periodically
    running ``git fetch``.

    Key behaviors:
    - Waits for idle (no write operations) before fetching
    - Configurable period (default 180 seconds)
    - Disables itself on authentication failure
    - Can be enabled/disabled via config

Used by:
    - server/websocket.py (started after git_state initialization)

Dependencies:
    - services/git_service.py (executes git fetch)
    - services/git_state.py (checks idle state via OperationManager)
    - core/event_bus.py (listens for operation events)
"""

from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

from loguru import logger

from ..core.event_bus import EventBus
from ..utils.operation import OperationManager

if TYPE_CHECKING:
    from .git_service import GitService


class AutoFetcher:
    """Periodically runs git fetch in the background.

    The fetch loop:
      1. Wait for idle (no write operations running)
      2. Execute git fetch (silent, no progress)
      3. If auth fails → disable auto-fetch
      4. Wait for the configured period
      5. Repeat

    Attributes:
        _git: GitService for executing fetch.
        _operations: OperationManager to check idle state.
        _enabled: Whether auto-fetch is active.
        _period: Seconds between fetch cycles.
    """

    def __init__(
        self,
        git_service: "GitService",
        operations: OperationManager,
        event_bus: EventBus,
        enabled: bool = False,
        period: int = 180,
    ) -> None:
        self._git = git_service
        self._operations = operations
        self._event_bus = event_bus
        self._enabled = enabled
        self._period = period
        self._task: asyncio.Task | None = None
        self._stop_event = asyncio.Event()

    @property
    def enabled(self) -> bool:
        return self._enabled

    def start(self) -> None:
        """Start the auto-fetch loop if enabled."""
        if not self._enabled:
            return
        if self._task and not self._task.done():
            return
        self._stop_event.clear()
        self._task = asyncio.create_task(self._run())
        logger.info(f"[AutoFetcher] 已启动: period={self._period}s")

    def stop(self) -> None:
        """Stop the auto-fetch loop."""
        self._enabled = False
        self._stop_event.set()
        if self._task and not self._task.done():
            self._task.cancel()
        logger.info("[AutoFetcher] 已停止")

    def set_enabled(self, enabled: bool) -> None:
        """Enable or disable auto-fetch.

        Args:
            enabled: True to enable, False to disable.
        """
        if enabled and not self._enabled:
            self._enabled = True
            self.start()
        elif not enabled and self._enabled:
            self.stop()

    async def _run(self) -> None:
        """Main fetch loop."""
        while self._enabled:
            # Wait for idle
            await self._wait_idle()

            if not self._enabled:
                return

            # Execute fetch (not pull — fetch only downloads, doesn't merge)
            try:
                result = await self._git.fetch()
                # Check for auth failure
                err = result.get("error", "") if isinstance(result, dict) else ""
                if "authentication" in err.lower() or "auth" in err.lower():
                    logger.warning("[AutoFetcher] 认证失败，自动禁用")
                    self._enabled = False
                    return
            except Exception as e:
                if "authentication" in str(e).lower():
                    logger.warning("[AutoFetcher] 认证失败，自动禁用")
                    self._enabled = False
                    return
                logger.debug(f"[AutoFetcher] fetch 出错（可忽略）: {e}")

            if not self._enabled:
                return

            # Wait for the configured period, or until stopped
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(), timeout=self._period
                )
                # stop_event was set → exit
                return
            except asyncio.TimeoutError:
                # Normal: period elapsed, continue loop
                pass

    async def _wait_idle(self) -> None:
        """Wait until no write operations are running."""
        while not self._operations.is_idle():
            if not self._enabled:
                return
            await asyncio.sleep(0.5)

    def dispose(self) -> None:
        """Clean up resources."""
        self.stop()
