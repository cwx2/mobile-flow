"""Project management handler.

Module: server/handlers/
Responsibility:
    Handle project.list, project.add, project.remove, project.switch,
    project.current, and project.search messages.
"""

from __future__ import annotations

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.payloads.chat import ChatHistoryResultPayload
from mobileflow_protocol.payloads.project import (
    ProjectAddPayload,
    ProjectCurrentPayload,
    ProjectListResultPayload,
    ProjectRemovePayload,
    ProjectSearchPayload,
    ProjectSearchResultPayload,
    ProjectSwitchPayload,
)
from mobileflow_protocol.types import MessageType

from ...utils.i18n import t
from .base import BaseHandler


class ProjectHandler(BaseHandler):
    """Handles project lifecycle operations over WebSocket.

    Manages the list of registered projects, switching between them,
    searching for projects on the filesystem, browsing directories,
    and rebuilding dependent services (FileService, CLI sessions) on switch.
    """

    async def handle_project_list(self, client_id, ws, msg):
        """Return the list of registered projects.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (no payload required).
        """
        projects = self.project_manager.list_projects()
        await self.send(ws, Message.from_typed(
            MessageType.PROJECT_LIST_RESULT,
            ProjectListResultPayload(projects=projects),
        ))

    async def handle_project_add(self, client_id, ws, msg):
        """Add a new project directory and auto-switch to it.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path`` and optional ``name``.
        """
        p = msg.typed_payload(ProjectAddPayload)
        path = p.path
        name = p.name
        logger.debug(f"添加项目: path={path}")
        success = self.project_manager.add_project(path, name)
        if not success:
            from pathlib import Path as P
            if not P(path).is_dir():
                await self.send_error(ws, t("backend.dirNotExist", path=path))
                return
        await self._notify_project_changed(client_id, ws)

    async def handle_project_remove(self, client_id, ws, msg):
        """Remove a project from the registered list.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path``.
        """
        p = msg.typed_payload(ProjectRemovePayload)
        path = p.path
        logger.debug(f"project.remove: path={path}")
        self.project_manager.remove_project(path)
        await self._notify_project_changed(client_id, ws)

    async def handle_project_switch(self, client_id, ws, msg):
        """Switch to a different project.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path``.
        """
        p = msg.typed_payload(ProjectSwitchPayload)
        path = p.path
        logger.info(f"project.switch: path={path}")
        self.project_manager.switch_project(path)
        await self._notify_project_changed(client_id, ws)

    async def _notify_project_changed(self, client_id: str, ws) -> None:
        """Unified project change handler — single source of truth.

        Called after add, remove, or switch. Performs the full project
        transition sequence:
        1. Rebuild services (FileService, GitService) via apply_current
        2. Clean up old CLI sessions (prevents stale session leaks)
        3. Send updated project list and current project to App
        4. Load and send chat history for the new project

        This ensures all three operations (add/remove/switch) have
        identical post-change behaviour. No handler needs to remember
        which steps to perform.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
        """
        current = self.project_manager.apply_current(self.server)
        await self.cli_manager.cleanup_sessions(client_id)

        # Reset git handler's active repo — the new project may have
        # different sub-repositories, so the previous selection is stale.
        self.server._git.reset_active_repo()

        projects = self.project_manager.list_projects()
        await self.send(ws, Message.from_typed(
            MessageType.PROJECT_LIST_RESULT,
            ProjectListResultPayload(projects=projects),
        ))
        await self.send(ws, Message.from_typed(
            MessageType.PROJECT_CURRENT,
            ProjectCurrentPayload(**current),
        ))

        # Load chat history for the new project (empty if no project)
        cli_name = self.config.default_cli
        if current.get("path"):
            history = await self.cli_manager.read_history(cli_name, client_id)
        else:
            history = []
        await self.send(ws, Message.from_typed(
            type=MessageType.CHAT_HISTORY_RESULT,
            payload=ChatHistoryResultPayload(messages=history, cli=cli_name),
        ))

    async def handle_project_current(self, client_id, ws, msg):
        """Return the currently active project.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message (no payload required).
        """
        current = self.project_manager.get_current()
        await self.send(ws, Message.from_typed(
            MessageType.PROJECT_CURRENT,
            ProjectCurrentPayload(**current),
        ))

    async def handle_project_search(self, client_id, ws, msg):
        """Handle project.search: search, browse, or list recent projects.

        Dispatches to one of three modes based on the payload:
        - If ``path`` is provided → browse mode: list subdirectories of that path.
        - If ``query`` is provided (no path) → search mode: scan filesystem for matches.
        - If neither → recent mode: return recently opened projects.

        Browse mode sends results with ``is_browsing=True`` and ``current_path``.
        Search and recent modes send results with ``is_browsing=False``.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``query``, ``path``, ``max_results``.
        """
        p = msg.typed_payload(ProjectSearchPayload)
        path = p.path
        query = p.query
        max_results = p.max_results
        logger.debug(f"project.search: path={path!r}, query={query!r}, max_results={max_results}")

        scanner = self.server.project_scanner

        try:
            if path is not None:
                # Browse mode: list subdirectories of the given path
                results = await scanner.list_directory(path)
                await self.send(ws, Message.from_typed(
                    MessageType.PROJECT_SEARCH_RESULT,
                    ProjectSearchResultPayload(
                        results=results,
                        is_browsing=True,
                        current_path=str(path),
                        is_complete=True,
                    ),
                ))
            elif query:
                # Search mode: scan filesystem for matching directories
                async def on_batch(batch: list[dict]) -> None:
                    """Stream partial results to the client as they are found."""
                    await self.send(ws, Message.from_typed(
                        MessageType.PROJECT_SEARCH_RESULT,
                        ProjectSearchResultPayload(
                            results=batch,
                            is_browsing=False,
                            current_path="",
                            is_complete=False,
                        ),
                    ))

                results = await scanner.search(
                    query,
                    max_results=max_results,
                    on_batch=on_batch,
                )
                # Send final complete result
                await self.send(ws, Message.from_typed(
                    MessageType.PROJECT_SEARCH_RESULT,
                    ProjectSearchResultPayload(
                        results=results,
                        is_browsing=False,
                        current_path="",
                        is_complete=True,
                    ),
                ))
            else:
                # Recent mode: return recently opened projects
                limit = self.config.project_scanner.recent_projects_limit
                results = self.project_manager.get_recent_projects(limit=limit)
                await self.send(ws, Message.from_typed(
                    MessageType.PROJECT_SEARCH_RESULT,
                    ProjectSearchResultPayload(
                        results=results,
                        is_browsing=False,
                        current_path="",
                        is_complete=True,
                    ),
                ))
        except ValueError as e:
            # Path outside allowed boundaries
            logger.warning(f"project.search 路径验证失败: {e}")
            await self.send(ws, Message.from_typed(
                MessageType.PROJECT_SEARCH_RESULT,
                ProjectSearchResultPayload(
                    results=[],
                    is_browsing=bool(path is not None),
                    current_path=str(path) if path else "",
                    is_complete=True,
                    error=str(e),
                ),
            ))
        except FileNotFoundError as e:
            # Path does not exist
            logger.warning(f"project.search 目录不存在: {e}")
            await self.send(ws, Message.from_typed(
                MessageType.PROJECT_SEARCH_RESULT,
                ProjectSearchResultPayload(
                    results=[],
                    is_browsing=True,
                    current_path=str(path) if path else "",
                    is_complete=True,
                    error=str(e),
                ),
            ))
        except Exception as e:
            logger.error(f"project.search 处理失败: {e}")
            await self.send(ws, Message.from_typed(
                MessageType.PROJECT_SEARCH_RESULT,
                ProjectSearchResultPayload(
                    results=[],
                    is_browsing=bool(path is not None),
                    current_path=str(path) if path else "",
                    is_complete=True,
                    error=t("backend.searchFailed", error=str(e)),
                ),
            ))
