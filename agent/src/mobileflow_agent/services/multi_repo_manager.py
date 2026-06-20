"""Multi-repository manager — orchestrates parallel git state tracking.

Module: services/
Responsibility:
    Manages multiple independent GitStateManager instances, one per
    discovered repository. Enables parallel status queries, per-repo
    file change routing, and aggregated state pushes.

    All repositories are tracked simultaneously with independent state.

Architecture:
    MultiRepoManager
    ├── _managers: dict[path, GitStateManager]  (per-repo instances)
    ├── open_repo(path) → register + initial refresh
    ├── close_repo(path) → dispose + remove
    ├── refresh_all() → parallel status for all repos
    ├── get_repo_for_path(file_path) → longest-prefix match routing
    └── get_all_status() → aggregated snapshot for App

Used by:
    - server/handlers/git_handler.py (routes operations to correct repo)
    - services/refresh_scheduler.py (routes file changes to correct repo)

Dependencies:
    - services/git_service.py (shared, cwd passed per-call)
    - services/git_state.py (one instance per repo)
    - core/event_bus.py (for state change notifications)
"""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

from loguru import logger

from ..core.event_bus import EventBus
from .git_service import GitService
from .git_state import GitStateManager


# Limit concurrent git subprocess spawns to avoid starving the system
_MAX_CONCURRENT_STATUS = 5


class MultiRepoManager:
    """Orchestrates multiple independent GitStateManager instances.

    Each discovered repository gets its own GitStateManager with
    independent throttling, operation tracking, and state caching.
    Operations are routed to the correct repo via file path matching.
    """

    def __init__(self, git_service: GitService, event_bus: EventBus) -> None:
        self._git = git_service
        self._event_bus = event_bus
        self._managers: dict[str, GitStateManager] = {}
        self._semaphore = asyncio.Semaphore(_MAX_CONCURRENT_STATUS)
        self._bg_tasks: set[asyncio.Task] = set()

    # ── Public API ──

    @property
    def repos(self) -> dict[str, GitStateManager]:
        """All managed repository instances, keyed by normalized path."""
        return self._managers

    @property
    def repo_count(self) -> int:
        """Number of managed repositories."""
        return len(self._managers)

    async def open_repo(self, repo_path: str) -> GitStateManager:
        """Register a repository for parallel state tracking.

        Creates a dedicated GitStateManager instance with the repo's
        path as its working directory. Runs initial status refresh.

        Each repo gets its own GitService instance to avoid cwd race
        conditions during parallel refresh operations. GitService is
        lightweight (holds only cwd + timeout config), so the overhead
        is negligible.

        Args:
            repo_path: Absolute path to the repository root.

        Returns:
            The created GitStateManager instance.
        """
        normalized = self._normalize(repo_path)
        if normalized in self._managers:
            logger.debug(f"仓库已注册，跳过: {normalized}")
            return self._managers[normalized]

        # Create a per-repo GitService instance to isolate cwd state.
        # Sharing a single GitService across parallel managers causes race
        # conditions: all repos end up querying the same (last-set) cwd.
        per_repo_git = GitService(
            cwd=repo_path,
            command_timeout=self._git._command_timeout,
            discovery_timeout=self._git._discovery_timeout,
        )

        # Create a per-repo GitStateManager with its own GitService
        manager = GitStateManager(
            git_service=per_repo_git,
            event_bus=self._event_bus,
        )
        self._managers[normalized] = manager

        # Initial refresh (limited concurrency)
        async with self._semaphore:
            try:
                await manager.initialize()
                logger.info(f"✅ 仓库已注册: {Path(repo_path).name} ({normalized})")
            except Exception as e:
                logger.warning(f"仓库初始化失败: {normalized}, error={e}")

        # Background fetch: update remote refs for accurate ahead/behind.
        # Non-blocking — fires after registration, refreshes status on completion.
        task = asyncio.create_task(self._background_fetch(normalized, per_repo_git, manager))
        self._bg_tasks.add(task)
        task.add_done_callback(self._bg_tasks.discard)

        return manager

    async def close_repo(self, repo_path: str) -> None:
        """Unregister a repository and dispose its manager.

        Args:
            repo_path: Absolute path to the repository root.
        """
        normalized = self._normalize(repo_path)
        manager = self._managers.pop(normalized, None)
        if manager:
            manager.dispose()
            logger.info(f"仓库已关闭: {normalized}")

    async def refresh_all(self) -> None:
        """Parallel status refresh for all managed repositories.

        Uses a semaphore to limit concurrent git subprocess spawns.
        Each repo refreshes independently; failures don't block others.
        Background fetch runs after status to update remote refs for next cycle.
        """
        if not self._managers:
            return

        async def _limited_refresh(mgr: GitStateManager) -> None:
            async with self._semaphore:
                try:
                    await mgr.throttled_status()
                except Exception as e:
                    logger.warning(f"仓库刷新失败: error={e}")

        tasks = [_limited_refresh(mgr) for mgr in self._managers.values()]
        await asyncio.gather(*tasks)

        # Background fetch all repos (non-blocking, updates refs for next refresh)
        asyncio.create_task(self._background_fetch_all())

    async def refresh_repo(self, repo_path: str) -> None:
        """Refresh a single repository's status.

        Args:
            repo_path: Absolute path to the repository root.
        """
        normalized = self._normalize(repo_path)
        manager = self._managers.get(normalized)
        if manager:
            async with self._semaphore:
                await manager.throttled_status()

    def get_repo_for_path(self, file_path: str) -> GitStateManager | None:
        """Route a file path to its owning repository manager.

        Uses longest-prefix match (same as VS Code's getRepository(uri)):
        the most deeply nested repository that contains the file wins.

        Args:
            file_path: Absolute file path to route.

        Returns:
            The GitStateManager for the owning repo, or None.
        """
        normalized_file = self._normalize(file_path)
        best_match: str | None = None
        best_len = 0

        for repo_path in self._managers:
            if normalized_file.startswith(repo_path) and len(repo_path) > best_len:
                best_match = repo_path
                best_len = len(repo_path)

        return self._managers.get(best_match) if best_match else None

    def get_manager(self, repo_path: str) -> GitStateManager | None:
        """Get a specific repository's manager by path.

        Args:
            repo_path: Absolute path to the repository root.

        Returns:
            The GitStateManager instance, or None if not registered.
        """
        return self._managers.get(self._normalize(repo_path))

    def get_all_status(self) -> list[dict[str, Any]]:
        """Get aggregated status snapshot for all repositories.

        Returns a list of status dicts suitable for the
        git.status.all.result payload. Each dict includes the repo
        path and name alongside the standard status fields.

        Returns:
            List of repo status dicts.
        """
        result = []
        for path, manager in self._managers.items():
            status = manager.status
            if status is None:
                # Not yet initialized
                result.append({
                    "path": path,
                    "name": Path(path).name,
                    "branch": "",
                    "ahead": 0,
                    "behind": 0,
                    "staged": [],
                    "unstaged": [],
                    "untracked": [],
                    "error": "not_initialized",
                })
            else:
                result.append({
                    "path": path,
                    "name": Path(path).name,
                    "branch": status.get("branch", ""),
                    "ahead": status.get("ahead", 0),
                    "behind": status.get("behind", 0),
                    "staged": status.get("staged", []),
                    "unstaged": status.get("unstaged", []),
                    "untracked": status.get("untracked", []),
                    "error": status.get("error", ""),
                })
        return result

    async def open_discovered_repos(self, repo_list: list[dict]) -> None:
        """Register multiple repositories from a discovery result.

        Called after git.repos discovery completes. Opens each
        repo in parallel with concurrency limiting.

        Args:
            repo_list: List of repo dicts from GitService.discover_repos().
                Each must have a "path" key.
        """
        tasks = []
        for repo in repo_list:
            path = repo.get("path", "")
            if path and self._normalize(path) not in self._managers:
                tasks.append(self.open_repo(path))

        if tasks:
            await asyncio.gather(*tasks)
            logger.info(f"批量注册完成: {len(tasks)} 个仓库")

    async def _background_fetch(
        self, normalized: str, git: GitService, manager: GitStateManager
    ) -> None:
        """Fetch remote refs for one repo, then refresh its status.

        Runs as a fire-and-forget task. Errors are logged and swallowed.
        """
        try:
            async with self._semaphore:
                await git.fetch()
                await manager.throttled_status()
            logger.debug(f"后台 fetch 完成: {Path(normalized).name}")
        except Exception as e:
            logger.debug(f"后台 fetch 失败（可忽略）: {Path(normalized).name}, {e}")

    async def _background_fetch_all(self) -> None:
        """Fetch all repos in parallel (background, non-blocking)."""
        async def _fetch_one(mgr: GitStateManager) -> None:
            try:
                async with self._semaphore:
                    await mgr._git.fetch()
                    await mgr.throttled_status()
            except Exception:
                pass

        tasks = [_fetch_one(mgr) for mgr in self._managers.values()]
        await asyncio.gather(*tasks)

    def dispose(self) -> None:
        """Dispose all managed repositories and cancel background tasks."""
        # Cancel any pending background fetch tasks
        for task in self._bg_tasks:
            task.cancel()
        self._bg_tasks.clear()

        for manager in self._managers.values():
            manager.dispose()
        self._managers.clear()
        logger.debug("MultiRepoManager 已释放")

    # ── Internal ──

    @staticmethod
    def _normalize(path: str) -> str:
        """Normalize a path for consistent dict key comparison.

        Resolves to absolute, forward-slash, no trailing slash.
        """
        return str(Path(path).resolve()).replace("\\", "/").rstrip("/")
