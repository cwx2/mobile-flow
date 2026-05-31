"""Refresh scheduler — debounce + throttle + idle-wait for file change events.

Module: services/
Responsibility:
    Prevents file system event storms from causing excessive git status calls.
    A typical "save file" triggers 2-3 FS events; without this scheduler,
    each would spawn a 650ms git status call.

    The refresh chain:
      onFileChange() → debounce(1s) → throttle → waitIdle() → refresh → cooldown(5s)

Used by:
    - server/websocket.py (instantiated after services are ready)

Dependencies:
    - services/git_state.py (triggers update_model_state)
    - utils/async_tools.py (Debouncer, Throttler)
    - utils/operation.py (OperationManager.is_idle)
    - core/event_bus.py (subscribes to FILE_CHANGED events)
"""

from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

from loguru import logger

from ..core.event_bus import EventBus
from ..core.events import Events
from ..utils.async_tools import Debouncer, Throttler
from ..utils.operation import OperationManager

if TYPE_CHECKING:
    from .git_state import GitStateManager
    from .file_service import FileService


class RefreshScheduler:
    """Schedules git state refreshes in response to file system events.

    The refresh chain:
      1. on_file_changed() — called for each FS event via EventBus
      2. Guard checks: auto_refresh? operations idle?
      3. debounce — merge rapid FS events into one trigger
      4. throttle — only one refresh at a time, queue the latest
      5. wait_idle() — wait for all write operations to finish
      6. git_state.update_model_state() — actual refresh
      7. cooldown — prevent immediate re-trigger

    Attributes:
        _git_state: GitStateManager to trigger refreshes on.
        _file_service: FileService for tree cache invalidation.
        _operations: OperationManager to check idle state.
        _debouncer: Merges rapid FS events.
        _throttler: Prevents concurrent refreshes.
        _cooldown: Seconds to wait after refresh before allowing next.
        _auto_refresh: Enable/disable auto-refresh on FS events.
    """

    def __init__(
        self,
        git_state: "GitStateManager",
        file_service: "FileService",
        operations: OperationManager,
        event_bus: EventBus,
        debounce_delay: float = 1.0,
        cooldown: float = 5.0,
        auto_refresh: bool = True,
    ) -> None:
        self._git_state = git_state
        self._file_service = file_service
        self._operations = operations
        self._event_bus = event_bus

        self._debouncer = Debouncer(debounce_delay)
        self._throttler = Throttler()
        self._cooldown = cooldown
        self._auto_refresh = auto_refresh

        # Subscribe to file change events from the file watcher
        self._event_bus.on(Events.FILE_CHANGED, self._on_file_changed)

    async def _on_file_changed(self, data: dict) -> None:
        """Handle a file system change event.

        Guard checks before scheduling refresh:
        1. auto_refresh must be enabled
        2. repository must not be huge (too many changed files)
        3. no write operations in progress

        Args:
            data: {path: str, change: "created"|"modified"|"deleted"}
        """
        if not self._auto_refresh:
            return

        # Skip refresh for huge repositories to avoid expensive status calls
        if self._git_state.is_repository_huge:
            logger.debug(
                "[RefreshScheduler] 跳过文件变更刷新: 大仓库"
            )
            return

        if not self._operations.is_idle():
            logger.debug(
                "[RefreshScheduler] 跳过文件变更刷新: 有写操作在进行"
            )
            return

        path = data.get("path", "")
        change = data.get("change", "")

        # Invalidate file tree cache for structural changes
        if change in ("created", "deleted"):
            self._file_service.invalidate_tree_cache(path)

        # Debounce: merge rapid events into one trigger
        self._debouncer.trigger(self._eventually_refresh)

    async def _eventually_refresh(self) -> None:
        """Debounced entry point → throttled refresh."""
        await self._throttler.queue(self._refresh_when_idle)

    async def _refresh_when_idle(self) -> None:
        """Wait for idle, refresh, then cooldown.

        Sequence:
          1. Wait for all write operations to finish
          2. Execute throttled status refresh
          3. Cooldown to prevent immediate re-trigger
        """
        # Wait for all write operations to complete
        await self._wait_idle()

        # Execute refresh via throttled status
        logger.debug("[RefreshScheduler] 开始自动刷新 git 状态")
        try:
            await self._git_state.throttled_status()
        except Exception as e:
            logger.warning(f"[RefreshScheduler] 自动刷新失败: {e}")

        # Cooldown — prevent immediate re-trigger
        if self._cooldown > 0:
            await asyncio.sleep(self._cooldown)

    async def _wait_idle(self) -> None:
        """Wait until no write operations are running.

        Polls every 100ms. In practice, write operations complete quickly
        so this rarely loops more than a few times.
        """
        while not self._operations.is_idle():
            await asyncio.sleep(0.1)

    def set_auto_refresh(self, enabled: bool) -> None:
        """Enable or disable auto-refresh on file system events.

        Args:
            enabled: True to enable, False to disable.
        """
        self._auto_refresh = enabled
        logger.info(f"[RefreshScheduler] auto_refresh={'启用' if enabled else '禁用'}")

    def dispose(self) -> None:
        """Clean up resources and unsubscribe from events."""
        self._debouncer.cancel()
        self._throttler.cancel()
        self._event_bus.off(Events.FILE_CHANGED, self._on_file_changed)
