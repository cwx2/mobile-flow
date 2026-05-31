"""Filesystem scanner for project discovery and directory browsing.

Module: services/
Responsibility:
    Search configured root directories for project folders by name,
    detect project type from marker files, and provide directory
    listing for the browse mode in the Project Picker.

Security:
    All paths are validated against an allowlist (home dir + configured
    search roots). System directories (/etc, /sys, C:\\Windows, etc.)
    are blocked to prevent accidental scanning of sensitive areas.

Design decisions:
    - Uses asyncio.to_thread for filesystem scanning to avoid blocking
      the event loop. Directory traversal is CPU-bound I/O that can
      take seconds on large trees.
    - Uses asyncio.wait_for with configurable timeout so partial results
      are returned if scanning takes too long.
    - Hidden directories (starting with '.') are skipped during search
      but .git detection still works within non-hidden directories.
"""

from __future__ import annotations

import asyncio
import os
import platform
import sys
from pathlib import Path
from typing import Awaitable, Callable

from loguru import logger

from ..core.config import ProjectScannerConfig
from ..utils.i18n import t


class ProjectScanner:
    """Filesystem scanner for project discovery and directory browsing.

    Searches configured root directories for project folders by name,
    detects project type from marker files, and provides directory
    listing for the browse mode.

    Security: all paths are validated against an allowlist (home dir +
    configured search roots). System directories are blocked.

    Attributes:
        config: Scanner settings (search_roots, max_depth, timeout, max_results).
    """

    # Project marker files -> project type mapping.
    # Order matters: first match wins for a given directory.
    PROJECT_MARKERS: dict[str, str | None] = {
        "pyproject.toml": "python",
        "setup.py": "python",
        "requirements.txt": "python",
        "package.json": "node",
        "pubspec.yaml": "flutter",
        "Cargo.toml": "rust",
        "go.mod": "go",
        "pom.xml": "java",
        "build.gradle": "java",
        "build.gradle.kts": "java",
        "CMakeLists.txt": "cpp",
        "Makefile": None,
    }

    # System directories that must never be scanned or browsed (Unix)
    SYSTEM_DIRS_UNIX: set[str] = {
        "/etc", "/sys", "/proc", "/dev", "/boot",
        "/sbin", "/bin", "/usr", "/var", "/tmp",
    }

    # System directories that must never be scanned or browsed (Windows)
    SYSTEM_DIRS_WIN: set[str] = {
        "C:\\Windows", "C:\\Program Files", "C:\\Program Files (x86)",
        "C:\\ProgramData",
    }

    def __init__(self, config: ProjectScannerConfig):
        """Initialize with scanner configuration.

        Args:
            config: Scanner settings (search_roots, max_depth, timeout, max_results).
        """
        self.config = config

    def _resolve_search_roots(self) -> list[Path]:
        """Determine search root directories.

        If config.search_roots is non-empty, use those paths directly.
        Otherwise auto-detect based on OS:
        - Home directory
        - ~/Desktop, ~/Documents
        - ~/Projects, ~/code, ~/repos, ~/workspace, ~/dev (if they exist)
        - On Windows: root of each available drive letter

        Returns:
            List of resolved, existing directory paths (deduplicated).
        """
        if self.config.search_roots:
            roots = []
            for r in self.config.search_roots:
                p = Path(r).expanduser().resolve()
                if p.is_dir():
                    roots.append(p)
                else:
                    logger.debug(f"配置的搜索根目录不存在，跳过: {r}")
            return roots

        # Auto-detect common development directories
        home = Path.home()
        candidates = [
            home,
            home / "Desktop",
            home / "Documents",
            home / "Projects",
            home / "code",
            home / "repos",
            home / "workspace",
            home / "dev",
        ]

        roots = []
        seen: set[Path] = set()
        for c in candidates:
            try:
                resolved = c.resolve()
                if resolved.is_dir() and resolved not in seen:
                    roots.append(resolved)
                    seen.add(resolved)
            except (OSError, PermissionError):
                continue

        # On Windows, add root of each available drive letter
        if sys.platform == "win32":
            for drive in self.get_windows_drives():
                dp = Path(drive)
                if dp not in seen:
                    roots.append(dp)
                    seen.add(dp)

        logger.debug(f"搜索根目录: {len(roots)} 个")
        return roots

    def _is_allowed_path(self, path: Path) -> bool:
        """Check if a path is within allowed boundaries.

        Allowed: home directory, configured search roots, and their descendants.
        Blocked: system directories, paths outside allowed roots.

        Args:
            path: Absolute path to validate.

        Returns:
            True if the path is safe to access.
        """
        try:
            resolved = path.resolve()
        except (OSError, ValueError):
            return False

        # Block system directories
        resolved_str = str(resolved)
        system_dirs = self.SYSTEM_DIRS_WIN if sys.platform == "win32" else self.SYSTEM_DIRS_UNIX
        for sd in system_dirs:
            # Check if path IS a system dir or is INSIDE one
            if resolved_str == sd or resolved_str.startswith(sd + os.sep):
                return False

        # Allow if under home directory
        home = Path.home().resolve()
        try:
            resolved.relative_to(home)
            return True
        except ValueError:
            pass

        # Allow if under any configured search root
        for root_str in self.config.search_roots:
            try:
                root = Path(root_str).expanduser().resolve()
                resolved.relative_to(root)
                return True
            except (ValueError, OSError):
                continue

        # On Windows, allow drive roots themselves (for browsing)
        if sys.platform == "win32":
            for drive in self.get_windows_drives():
                try:
                    resolved.relative_to(Path(drive))
                    return True
                except ValueError:
                    continue

        return False

    @staticmethod
    def _detect_project_type(directory: Path) -> str | None:
        """Detect project type from marker files in a directory.

        Checks for known marker files (package.json, pyproject.toml, etc.)
        and returns the corresponding project type string. Returns the first
        match found — order follows PROJECT_MARKERS dict.

        Args:
            directory: Path to check.

        Returns:
            Project type string ("python", "node", "flutter", etc.) or None
            if no marker file is found.
        """
        for marker, ptype in ProjectScanner.PROJECT_MARKERS.items():
            if (directory / marker).exists():
                return ptype if ptype else "unknown"
        return None

    @staticmethod
    def _has_git(directory: Path) -> bool:
        """Check if directory contains a .git subdirectory.

        Args:
            directory: Path to check.

        Returns:
            True if .git exists as a directory inside the given path.
        """
        return (directory / ".git").is_dir()

    async def search(
        self,
        query: str,
        max_results: int | None = None,
        on_batch: Callable[[list[dict]], Awaitable[None]] | None = None,
    ) -> list[dict]:
        """Search for project directories matching the query.

        Scans all search roots up to max_depth, matching directory names
        case-insensitively. Results are streamed via on_batch callback
        as they are found. Respects timeout — returns partial results
        if time runs out.

        Results are sorted: directories with project markers first,
        then alphabetically by name (case-insensitive).

        Uses asyncio.to_thread for the blocking filesystem walk to avoid
        blocking the event loop.

        Args:
            query: Case-insensitive substring to match against directory names.
            max_results: Override config.max_results if provided.
            on_batch: Async callback for streaming partial results.
                Called with a list of new result dicts as they are found.

        Returns:
            List of project entry dicts with keys:
            path, name, project_type, has_git, exists.
        """
        limit = max_results or self.config.max_results
        query_lower = query.lower()
        roots = self._resolve_search_roots()
        logger.debug(f"项目搜索: query={query!r}, limit={limit}, roots={len(roots)}")

        results: list[dict] = []
        seen_paths: set[str] = set()

        def _scan_sync() -> list[dict]:
            """Synchronous filesystem scan — runs in a thread."""
            for root in roots:
                if len(results) >= limit:
                    break
                try:
                    self._walk_directory(
                        root, query_lower, 0, self.config.max_depth,
                        results, seen_paths, limit,
                    )
                except (OSError, PermissionError) as e:
                    logger.debug(f"扫描根目录出错: root={root}, error={e}")
            return results

        try:
            await asyncio.wait_for(
                asyncio.to_thread(_scan_sync),
                timeout=self.config.search_timeout,
            )
        except asyncio.TimeoutError:
            logger.warning(f"项目搜索超时: query={query!r}, 已找到 {len(results)} 个结果")

        # Sort: project_type first, then alphabetical by name
        results.sort(key=lambda r: (
            0 if r["project_type"] else 1,
            r["name"].lower(),
        ))

        # Trim to limit after sorting
        results = results[:limit]

        # Stream final batch if callback provided
        if on_batch and results:
            await on_batch(results)

        logger.info(f"项目搜索完成: query={query!r}, 结果={len(results)}")
        return results

    def _walk_directory(
        self,
        directory: Path,
        query_lower: str,
        current_depth: int,
        max_depth: int,
        results: list[dict],
        seen_paths: set[str],
        limit: int,
    ) -> None:
        """Recursively walk a directory tree looking for matching directories.

        Skips hidden directories (starting with '.') and system directories.
        Adds matching directories to results list in-place.

        Args:
            directory: Current directory to scan.
            query_lower: Lowercased search query for matching.
            current_depth: Current recursion depth.
            max_depth: Maximum allowed depth.
            results: Shared results list (mutated in-place).
            seen_paths: Set of already-seen paths to avoid duplicates.
            limit: Maximum number of results to collect.
        """
        if current_depth > max_depth or len(results) >= limit:
            return

        try:
            entries = sorted(os.scandir(directory), key=lambda e: e.name.lower())
        except (OSError, PermissionError):
            return

        for entry in entries:
            if len(results) >= limit:
                return

            # Skip non-directories and hidden directories
            if not entry.is_dir(follow_symlinks=False):
                continue
            if entry.name.startswith("."):
                continue

            entry_path = Path(entry.path)

            # Check if name matches query
            if query_lower in entry.name.lower():
                resolved_str = str(entry_path.resolve())
                if resolved_str not in seen_paths:
                    seen_paths.add(resolved_str)
                    results.append({
                        "path": resolved_str,
                        "name": entry.name,
                        "project_type": self._detect_project_type(entry_path),
                        "has_git": self._has_git(entry_path),
                        "exists": True,
                    })

            # Recurse into subdirectories
            if current_depth < max_depth:
                self._walk_directory(
                    entry_path, query_lower, current_depth + 1,
                    max_depth, results, seen_paths, limit,
                )

    def list_roots(self) -> list[dict]:
        """Return filesystem root entries for the browse mode landing page.

        On Windows: returns all available drive letters (C:\\, D:\\, E:\\, etc.)
        plus the user's home directory.
        On Unix: returns the root directory (/) and the user's home directory.

        This is called when the user opens the directory browser (path="")
        so they can pick which drive/root to start browsing from — similar
        to VS Code's file picker.

        Returns:
            List of root entry dicts with keys:
            path, name, project_type, has_git, exists.
        """
        roots: list[dict] = []
        home = Path.home()

        if sys.platform == "win32":
            # Show all available drive letters first
            for drive in self.get_windows_drives():
                dp = Path(drive)
                roots.append({
                    "path": drive,
                    "name": f"💾 {drive}",
                    "project_type": None,
                    "has_git": False,
                    "exists": dp.exists(),
                })
        else:
            # Unix: show root directory
            roots.append({
                "path": "/",
                "name": "/",
                "project_type": None,
                "has_git": False,
                "exists": True,
            })

        # Always include home directory as a quick-access entry
        roots.append({
            "path": str(home),
            "name": f"🏠 {home.name} (Home)",
            "project_type": None,
            "has_git": self._has_git(home),
            "exists": home.is_dir(),
        })

        logger.debug(f"浏览根目录: {len(roots)} 个入口")
        return roots

    async def list_directory(self, path: str) -> list[dict]:
        """List subdirectories of a given path for browse mode.

        Only returns directories (not files), sorted alphabetically by name
        (case-insensitive). Each entry includes project marker detection.

        When path is empty (""), returns filesystem roots (drive letters on
        Windows, / on Unix) via list_roots() — this is the browse landing page.

        Validates the path against the allowlist before listing.

        Args:
            path: Absolute directory path to list. Use "" for root/drive listing,
                "~" for home directory.

        Returns:
            List of directory entry dicts with keys:
            path, name, project_type, has_git, exists.

        Raises:
            ValueError: If path is outside allowed boundaries.
            FileNotFoundError: If path does not exist.
        """
        # Empty path = show filesystem roots (drives on Windows, / on Unix)
        if not path or path.strip() == "":
            logger.debug("目录浏览: 返回根目录/驱动器列表")
            return self.list_roots()

        # Expand ~ to home directory
        target = Path(path).expanduser().resolve()
        logger.debug(f"目录浏览: path={path!r}, resolved={target}")

        if not self._is_allowed_path(target):
            logger.warning(f"目录浏览被拒绝（路径不在允许范围内）: {target}")
            raise ValueError(t("backend.dirNotAccessible", path=str(path)))

        if not target.is_dir():
            logger.warning(f"目录浏览失败（目录不存在）: {target}")
            raise FileNotFoundError(t("backend.dirNotExist", path=str(path)))

        def _list_sync() -> list[dict]:
            """Synchronous directory listing — runs in a thread."""
            entries = []
            try:
                for entry in sorted(os.scandir(target), key=lambda e: e.name.lower()):
                    if not entry.is_dir(follow_symlinks=False):
                        continue
                    # Skip hidden directories in browse mode
                    if entry.name.startswith("."):
                        continue
                    entry_path = Path(entry.path)
                    entries.append({
                        "path": str(entry_path.resolve()),
                        "name": entry.name,
                        "project_type": self._detect_project_type(entry_path),
                        "has_git": self._has_git(entry_path),
                        "exists": True,
                    })
            except (OSError, PermissionError) as e:
                logger.warning(f"目录列表读取失败: path={target}, error={e}")
            return entries

        results = await asyncio.to_thread(_list_sync)
        logger.debug(f"目录浏览完成: path={path!r}, 子目录={len(results)}")
        return results

    def get_windows_drives(self) -> list[str]:
        """Detect available Windows drive letters.

        Uses ctypes on Windows to query the system for available logical
        drives. Returns empty list on non-Windows platforms.

        Returns:
            List of drive root paths (e.g. ["C:\\\\", "D:\\\\"]).
        """
        if sys.platform != "win32":
            return []

        try:
            import ctypes
            bitmask = ctypes.windll.kernel32.GetLogicalDrives()  # type: ignore[attr-defined]
            drives = []
            for i in range(26):
                if bitmask & (1 << i):
                    letter = chr(ord("A") + i)
                    drives.append(f"{letter}:\\")
            logger.debug(f"Windows 驱动器: {drives}")
            return drives
        except Exception as e:
            logger.warning(f"Windows 驱动器检测失败: {e}")
            return []
