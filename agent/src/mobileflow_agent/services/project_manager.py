"""Project manager for multi-directory workspace support.

Manages a list of working directories that the user can switch between from
the mobile App.  The project list is persisted to
``~/.mobileflow/projects.json``.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Optional, TYPE_CHECKING

from loguru import logger

from ..core.config import AgentConfig
from ..utils.json_file import load_json_file

if TYPE_CHECKING:
    from ..server.websocket import WebSocketServer


class ProjectManager:
    """Manages project directories: add, remove, switch, and persist.

    Attributes:
        config: Agent configuration (provides ``work_dir`` and data dir).
    """

    def __init__(self, config: AgentConfig):
        self.config = config
        self._projects: list[dict] = []
        self._current_index: int = 0
        self._config_file = config.ensure_data_dir() / "projects.json"
        self._load()

    def _load(self):
        """Load the project list from disk and restore the last active project."""
        data = load_json_file(self._config_file, default={})
        if isinstance(data, dict) and data:
            try:
                self._projects = data.get("projects", [])
                self._current_index = data.get("current_index", 0)
                # Restore the last active working directory
                if self._projects and self._current_index < len(self._projects):
                    saved_path = self._projects[self._current_index]["path"]
                    if Path(saved_path).is_dir():
                        self.config.work_dir = saved_path
                        logger.info(f"📂 恢复工作目录: {saved_path}")
                logger.info(f"📂 加载了 {len(self._projects)} 个项目")
            except Exception as e:
                logger.warning(f"加载项目配置失败: {e}")

        # Ensure the restored working directory is valid
        if not self.config.work_dir:
            logger.info("📂 未选择项目，等待用户添加")

    def _save(self):
        """Persist the project list and current index to disk."""
        try:
            data = {
                "projects": self._projects,
                "current_index": self._current_index,
            }
            self._config_file.write_text(
                json.dumps(data, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except Exception as e:
            logger.warning(f"保存项目配置失败: {e}")

    def list_projects(self) -> list[dict]:
        """Return all registered projects with their active status.

        Returns:
            List of dicts with ``path``, ``name``, and ``is_current`` keys.
        """
        result = []
        for i, p in enumerate(self._projects):
            result.append({
                "path": p["path"],
                "name": p.get("name", Path(p["path"]).name),
                "is_current": i == self._current_index,
            })
        return result

    def get_current(self) -> dict:
        """Return the currently active project.

        Returns:
            Dict with ``path`` and ``name`` of the active project.
            Both are empty strings when no project is selected.
        """
        if self._projects and self._current_index < len(self._projects):
            p = self._projects[self._current_index]
            return {
                "path": p["path"],
                "name": p.get("name", Path(p["path"]).name),
            }
        return {"path": "", "name": ""}

    def apply_current(self, server: 'WebSocketServer') -> dict:
        """Apply the current project state to the server.

        Updates config.work_dir, rebuilds FileService and GitService
        to point to the new project directory. Returns the current
        project dict for sending to the App.

        This is the single source of truth for project state transitions.
        Called by handle_project_add, handle_project_remove, and
        handle_project_switch.

        Args:
            server: The WebSocketServer instance to update.

        Returns:
            Dict with 'path' and 'name' of the current project
            (path is empty string if no project is selected).
        """
        current = self.get_current()
        path = current.get("path", "")

        self.config.work_dir = path

        if path:
            # Update existing service instances instead of creating new ones.
            # All components (GitStateManager, AutoFetcher, RefreshScheduler)
            # hold references to these services — replacing instances would
            # leave them pointing at stale objects.
            if server.file_service is not None:
                server.file_service.update_root(path)
            else:
                from ..services.file_service import FileService
                server.file_service = FileService(self.config)

            server.git_state.update_project(path)

        return current

    def add_project(self, path: str, name: Optional[str] = None) -> bool:
        """Register a new project directory.

        If this is the first project, it is automatically set as the active one.
        Updates the last_opened timestamp for the project.

        Args:
            path: Filesystem path to the project directory.
            name: Optional display name (defaults to the directory name).

        Returns:
            True if the project was added, False if it already exists or the
            directory does not exist.
        """
        resolved = str(Path(path).resolve())
        if any(p["path"] == resolved for p in self._projects):
            logger.info(f"项目已存在: {resolved}")
            # Still update last_opened when re-adding an existing project
            self._update_last_opened(resolved)
            return False

        if not Path(resolved).is_dir():
            logger.warning(f"目录不存在: {resolved}")
            return False

        self._projects.append({
            "path": resolved,
            "name": name or Path(resolved).name,
            "last_opened": time.time(),
        })

        # Auto-switch to the first project added
        if len(self._projects) == 1:
            self._current_index = 0
            self.config.work_dir = resolved
            logger.info(f"📂 自动切换到首个项目: {resolved}")

        self._save()
        logger.info(f"📂 添加项目: {resolved}")
        return True

    def remove_project(self, path: str) -> bool:
        """Remove a project from the registered list.

        Args:
            path: Filesystem path of the project to remove.

        Returns:
            True if the project was found and removed, False otherwise.
        """
        for i, p in enumerate(self._projects):
            if p["path"] == path:
                self._projects.pop(i)
                if self._current_index >= len(self._projects):
                    self._current_index = max(0, len(self._projects) - 1)
                self._save()
                logger.info(f"📂 删除项目: {path}")
                return True
        return False

    def switch_project(self, path: str) -> Optional[str]:
        """Switch to a different project.

        Updates the last_opened timestamp for the target project.

        Args:
            path: Filesystem path of the target project.

        Returns:
            The new working directory path on success, or None if the project
            was not found.
        """
        for i, p in enumerate(self._projects):
            if p["path"] == path:
                self._current_index = i
                self.config.work_dir = p["path"]
                self._update_last_opened(path)
                logger.info(f"📂 切换项目: {p['path']}")
                return p["path"]
        return None

    def _update_last_opened(self, path: str) -> None:
        """Update the last_opened timestamp for a project.

        Finds the project by path and sets its last_opened field to the
        current time. Called internally when a project is added or switched to.

        Args:
            path: The project path to update.
        """
        for p in self._projects:
            if p["path"] == path:
                p["last_opened"] = time.time()
                self._save()
                logger.debug(f"📂 更新 last_opened: {path}")
                return

    def get_recent_projects(self, limit: int = 10) -> list[dict]:
        """Return recently opened projects sorted by last-opened time.

        Each entry includes: path, name, project_type (detected via
        ProjectScanner), has_git, exists (whether directory still exists
        on disk), and last_opened timestamp.

        Old project entries without a last_opened field default to 0
        for backward compatibility.

        Args:
            limit: Maximum number of entries to return.

        Returns:
            List of recent project dicts, most recent first.
        """
        from .project_scanner import ProjectScanner

        # Sort by last_opened descending (default 0 for old entries)
        sorted_projects = sorted(
            self._projects,
            key=lambda p: p.get("last_opened", 0),
            reverse=True,
        )[:limit]

        results = []
        for p in sorted_projects:
            proj_path = Path(p["path"])
            results.append({
                "path": p["path"],
                "name": p.get("name", proj_path.name),
                "project_type": ProjectScanner._detect_project_type(proj_path),
                "has_git": ProjectScanner._has_git(proj_path),
                "exists": proj_path.is_dir(),
                "last_opened": p.get("last_opened", 0),
            })

        logger.debug(f"📂 最近项目: {len(results)} 个")
        return results

    def get_last_session_id(self) -> Optional[str]:
        """Return the last saved session_id for the current project.

        Returns:
            The session_id string, or None if not available.
        """
        if self._projects and self._current_index < len(self._projects):
            return self._projects[self._current_index].get("last_session_id")
        return None

    def save_session_id(self, session_id: str):
        """Persist the current session_id for the active project.

        Args:
            session_id: The ACP session identifier to save.
        """
        if self._projects and self._current_index < len(self._projects):
            self._projects[self._current_index]["last_session_id"] = session_id
            self._save()
            logger.debug(f"📂 保存 session_id: {session_id}")
