"""Git state manager — holds cached git state in memory.

Module: services/
Responsibility:
    All git read operations (status, branches, log) return data from this
    in-memory state. Write operations go through run() which automatically
    triggers update_model_state() after completion.

    This eliminates the 650ms git status call on every App request.
    Instead, state is refreshed only when:
    1. A write operation completes (commit, stage, push, etc.)
    2. A file system change is detected (via RefreshScheduler)
    3. The user explicitly requests a refresh

    Architecture:
    - run() wraps all operations with lifecycle events and retry logic
    - status() is throttled to prevent concurrent status calls
    - updateModelState() uses generation counters to cancel stale refreshes
    - retryRun() has quadratic backoff for lock conflicts
    - RepositoryState guards run() to reject operations on disposed repos

Used by:
    - server/handlers/git_handler.py (read cached state, execute writes)
    - services/refresh_scheduler.py (triggers update_model_state)

Dependencies:
    - services/git_service.py (executes actual git commands)
    - utils/operation.py (OperationManager, Operation, Op)
    - utils/async_tools.py (Throttler for status throttling)
    - core/event_bus.py (EventBus for state change notifications)
"""

from __future__ import annotations

import asyncio
from enum import Enum
from typing import Any, Callable, Coroutine, TypeVar

from loguru import logger

from ..core.event_bus import EventBus
from ..core.events import Events
from ..utils.async_tools import Throttler
from ..utils.operation import Operation, OperationManager

T = TypeVar("T")


class RepositoryState(Enum):
    """Repository lifecycle state.

    Guards run() — operations are rejected unless state is Idle.
    """

    IDLE = "idle"
    DISPOSED = "disposed"


class GitStateManager:
    """Manages cached git state with operation-driven refresh.

    State fields (populated by update_model_state, read by handlers):
        _status:   GitStatusResult dict (branch, staged, unstaged, untracked)
        _branches: dict with "branches" list and "error"
        _log:      dict with "entries" list and "error"

    All fields start as None and are populated on first refresh.
    Handlers check for None and trigger initialization if needed.

    Key patterns implemented:
        - run() guards with RepositoryState check
        - run() fires onRunOperation / onDidRunOperation events
        - status() is throttled to prevent concurrent calls
        - retryRun() distinguishes lock errors vs retry-eligible errors
        - updateModelState() cancels stale refreshes via generation counter
        - isRepositoryHuge flag disables auto-refresh for large repos
    """

    def __init__(
        self,
        git_service: Any,
        event_bus: EventBus,
        status_limit: int = 5000,
    ) -> None:
        self._git = git_service
        self._event_bus = event_bus
        self._operations = OperationManager()

        # Repository lifecycle state
        self._state = RepositoryState.IDLE

        # Cached state — populated by update_model_state()
        self._status: dict | None = None
        self._branches: dict | None = None
        self._log: dict | None = None

        # Previous HEAD for change detection
        self._prev_head: str | None = None

        # Large repository flag — disables auto-refresh
        self._is_repository_huge: bool = False
        # Threshold for huge repo detection (default 10000 changed files)
        self._status_limit = status_limit

        # Cancellation for in-flight refresh (generation counter)
        self._refresh_generation: int = 0

        # Throttler for status() — prevents concurrent status calls
        self._status_throttler = Throttler()

    # ── Public read accessors (zero-cost, return cached state) ──

    @property
    def status(self) -> dict | None:
        """Cached git status result. None if not yet loaded."""
        return self._status

    @property
    def branches(self) -> dict | None:
        """Cached branches result. None if not yet loaded."""
        return self._branches

    @property
    def log_entries(self) -> dict | None:
        """Cached log result. None if not yet loaded."""
        return self._log

    @property
    def operations(self) -> OperationManager:
        """The operation manager tracking in-flight operations."""
        return self._operations

    @property
    def is_initialized(self) -> bool:
        """True if at least one refresh has completed."""
        return self._status is not None

    @property
    def state(self) -> RepositoryState:
        """Current repository lifecycle state."""
        return self._state

    @property
    def is_repository_huge(self) -> bool:
        """True if the repository has too many changes for auto-refresh.

        Set when git status returns more files than the configured limit.
        When True, RefreshScheduler skips file-change-triggered refreshes.
        """
        return self._is_repository_huge

    # ── Core: run() — all operations go through here ──

    async def run(
        self,
        operation: Operation,
        run_operation: Callable[[], Coroutine[Any, Any, T]] | None = None,
        get_optimistic: Callable[[], dict | None] | None = None,
    ) -> T | None:
        """Execute a git operation with automatic state refresh.

        Flow:
          1. Guard: reject if state != Idle
          2. Register operation in OperationManager
          3. Fire "git.op.start" event
          4. Execute the operation with retry (retryRun)
          5. If NOT read_only → trigger update_model_state()
          6. Unregister operation
          7. Fire "git.op.done" event

        Args:
            operation: Operation descriptor (from Op.* constants).
            run_operation: Async callable that performs the actual work.
                If None, just triggers a refresh (used by status/refresh).
            get_optimistic: Optional callable returning optimistic state
                dict to apply immediately before the real refresh.

        Returns:
            The return value of run_operation, or None.

        Raises:
            RuntimeError: If repository state is not Idle.
        """
        # Guard: reject operations on non-idle repository
        if self._state != RepositoryState.IDLE:
            raise RuntimeError(
                f"仓库状态异常，无法执行操作: state={self._state.value}"
            )

        result = None
        error = None
        op_id = self._operations.start(operation)

        # Fire operation start event
        await self._event_bus.emit("git.op.start", {
            "kind": operation.kind.value,
            "blocking": operation.blocking,
            "read_only": operation.read_only,
        })

        try:
            if run_operation is not None:
                result = await self._retry_run(operation, run_operation)

            # Write operations trigger automatic state refresh
            if not operation.read_only:
                optimistic = get_optimistic() if get_optimistic else None
                await self.update_model_state(optimistic)

            return result

        except Exception as e:
            error = e
            logger.error(
                f"Git 操作失败: {operation.kind.value}, error={e}"
            )

            # Mark repository as disposed if it's no longer a git repo
            from ..core.errors import AppErrorCode, GitError
            if isinstance(e, GitError) and e.code == AppErrorCode.GIT_NOT_A_REPO:
                self._state = RepositoryState.DISPOSED
            elif "not a git repository" in str(e).lower():
                self._state = RepositoryState.DISPOSED

            # Even on error, refresh state for write operations
            if not operation.read_only:
                try:
                    await self.update_model_state()
                except Exception:
                    pass
            raise

        finally:
            self._operations.end(op_id)
            # Fire operation done event
            await self._event_bus.emit("git.op.done", {
                "kind": operation.kind.value,
                "error": str(error) if error else None,
            })

    async def _retry_run(
        self,
        operation: Operation,
        run_operation: Callable[[], Coroutine[Any, Any, T]],
    ) -> T:
        """Execute with retry on lock conflicts.

        Uses structured GitError codes for classification:
        1. GIT_REPO_LOCKED (index.lock) — always retryable
        2. GIT_CANT_LOCK_REF — only retryable if operation.retry is True
        3. GIT_CANT_REBASE — only retryable if operation.retry is True

        Quadratic backoff: attempt^2 * 50ms, max 10 attempts.

        Args:
            operation: Operation descriptor (for retry policy).
            run_operation: The async callable to execute.

        Returns:
            The result of the operation.

        Raises:
            Exception: If all retries are exhausted or error is not retryable.
        """
        from ..core.errors import AppErrorCode, GitError

        max_attempts = 10
        for attempt in range(1, max_attempts + 1):
            try:
                return await run_operation()
            except Exception as e:
                # Classify the error using structured codes
                git_code = None
                if isinstance(e, GitError):
                    git_code = e.code
                else:
                    # Fallback: classify from error message string
                    git_code = GitError.classify(str(e))

                # Condition 1: index.lock — always retryable
                is_repo_locked = git_code == AppErrorCode.GIT_REPO_LOCKED

                # Condition 2: ref lock — only retryable if operation.retry
                is_ref_locked = (
                    operation.retry
                    and git_code == AppErrorCode.GIT_CANT_LOCK_REF
                )

                # Condition 3: rebase conflict — only retryable if operation.retry
                is_rebase_conflict = (
                    operation.retry
                    and git_code == AppErrorCode.GIT_CANT_REBASE
                )

                should_retry = (
                    attempt <= max_attempts
                    and (is_repo_locked or is_ref_locked or is_rebase_conflict)
                )

                if should_retry:
                    # Quadratic backoff: attempt^2 * 50ms
                    delay = (attempt ** 2) * 0.05
                    logger.warning(
                        f"Git 锁冲突，重试 #{attempt}: "
                        f"op={operation.kind.value}, code={git_code}, "
                        f"delay={delay:.2f}s"
                    )
                    await asyncio.sleep(delay)
                else:
                    raise
        # Unreachable, but satisfies type checker
        raise RuntimeError("重试耗尽")

    # ── Throttled status ──

    async def throttled_status(self) -> None:
        """Throttled status refresh.

        Multiple concurrent calls result in at most one execution at a time,
        with the latest queued call running after the current one finishes.
        """
        await self._status_throttler.queue(self._do_status)

    async def _do_status(self) -> None:
        """Execute a status refresh via run().

        Wraps the status operation in run() to get lifecycle events,
        operation tracking, and automatic state refresh.
        """
        from ..utils.operation import Op
        await self.run(Op.Status)

    # ── State refresh ──

    async def update_model_state(
        self, optimistic: dict | None = None
    ) -> None:
        """Refresh all cached git state from disk.

        Flow:
          1. Cancel previous in-flight refresh (increment generation counter)
          2. Apply optimistic update if provided
          3. Parallel fetch: status, branches, log
          4. Detect HEAD changes
          5. Update internal state
          6. Check for huge repository
          7. Emit change events → App receives push updates

        Args:
            optimistic: Optional dict with pre-computed state to apply
                immediately. Keys can include "status", "branches", "log".
        """
        # Cancel previous refresh (increment generation to invalidate in-flight)
        self._refresh_generation += 1
        my_generation = self._refresh_generation

        # Apply optimistic update immediately
        if optimistic:
            logger.debug(f"乐观更新: keys={list(optimistic.keys())}")
            if "status" in optimistic:
                self._status = optimistic["status"]
                await self._notify_change("git.status", self._status)

        try:
            # Parallel fetch all state
            results = await asyncio.gather(
                self._git.status(),
                self._git.branches(),
                self._git.log(count=50),
                return_exceptions=True,
            )

            # Check if this refresh is still current
            if my_generation != self._refresh_generation:
                logger.debug("状态刷新被取消（有更新的刷新请求）")
                return

            status_result, branches_result, log_result = results

            # Update status
            if not isinstance(status_result, Exception):
                new_status = (
                    status_result.to_dict()
                    if hasattr(status_result, "to_dict")
                    else status_result
                )

                # Detect HEAD change
                new_head = new_status.get("branch", "") if new_status else ""
                if self._prev_head is not None and new_head != self._prev_head:
                    logger.info(
                        f"HEAD 变更: {self._prev_head} → {new_head}"
                    )
                self._prev_head = new_head

                # Check for huge repository (too many changes for auto-refresh)
                if new_status:
                    total_changes = (
                        len(new_status.get("staged", []))
                        + len(new_status.get("unstaged", []))
                        + len(new_status.get("untracked", []))
                    )
                    was_huge = self._is_repository_huge
                    self._is_repository_huge = total_changes > self._status_limit
                    if self._is_repository_huge and not was_huge:
                        logger.warning(
                            f"大仓库检测: {total_changes} 个变更文件 "
                            f"(limit={self._status_limit})，自动刷新已禁用"
                        )

                self._status = new_status
            else:
                logger.warning(f"git status 刷新失败: {status_result}")

            # Update branches
            if not isinstance(branches_result, Exception):
                self._branches = branches_result
            else:
                logger.warning(f"git branches 刷新失败: {branches_result}")

            # Update log
            if not isinstance(log_result, Exception):
                self._log = log_result
            else:
                logger.warning(f"git log 刷新失败: {log_result}")

            # Push updates to App via EventBus
            await self._notify_change("git.status", self._status)
            await self._notify_change("git.branches", self._branches)
            await self._notify_change("git.log", self._log)

            logger.debug("Git 状态刷新完成")

        except Exception as e:
            if my_generation == self._refresh_generation:
                logger.error(f"Git 状态刷新出错: {e}")

    async def _notify_change(self, key: str, data: Any) -> None:
        """Push a state change event to the App via EventBus.

        The WebSocket server subscribes to "state.changed" events and
        forwards them to all connected App clients.

        Args:
            key: State key (e.g. "git.status", "git.branches").
            data: The state data to push.
        """
        if data is not None:
            await self._event_bus.emit(
                "state.changed", {"key": key, "data": data}
            )

    # ── Lifecycle ──

    async def initialize(self) -> None:
        """Load initial state on startup or project switch.

        Clears all cached state and does a full refresh.
        """
        logger.info("Git 状态管理器初始化...")
        self._state = RepositoryState.IDLE
        self._status = None
        self._branches = None
        self._log = None
        self._prev_head = None
        self._is_repository_huge = False
        self._refresh_generation += 1
        await self.update_model_state()

    def clear(self) -> None:
        """Clear all cached state without refreshing.

        Used during project switch before the new project is ready.
        """
        self._status = None
        self._branches = None
        self._log = None
        self._prev_head = None
        self._is_repository_huge = False
        self._refresh_generation += 1
        logger.debug("Git 状态缓存已清除")

    def update_project(self, new_cwd: str) -> None:
        """Switch to a new project directory.

        Updates the underlying GitService's working directory and clears
        all cached state. Called by ProjectManager on project switch.
        Symmetric with FileService.update_root().

        Args:
            new_cwd: New working directory path for git commands.
        """
        self._git._update_cwd(new_cwd)
        self.clear()
        logger.info(f"Git 状态管理器切换项目: {new_cwd}")

    def dispose(self) -> None:
        """Cancel pending async tasks to allow clean shutdown.

        Cancels the status throttler's in-flight Futures so the event
        loop can exit without hanging on pending tasks.
        """
        self._status_throttler.cancel()
        self._refresh_generation += 1
        logger.debug("Git 状态管理器已释放")
