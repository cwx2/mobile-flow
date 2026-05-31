"""Project domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the eight project-related message types:
  - project.list          (PROJECT_LIST)          — list registered projects
  - project.list.result   (PROJECT_LIST_RESULT)   — project list
  - project.add           (PROJECT_ADD)           — add project directory
  - project.remove        (PROJECT_REMOVE)        — remove project
  - project.switch        (PROJECT_SWITCH)        — switch active project
  - project.current       (PROJECT_CURRENT)       — current project info
  - project.search        (PROJECT_SEARCH)        — search/browse for projects
  - project.search.result (PROJECT_SEARCH_RESULT) — search results

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Any, Optional

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


class ProjectListPayload(PayloadBase):
    """Payload for ``project.list`` — list registered projects.

    Sent by the App to request the list of all registered projects.
    No fields required.
    """

    pass


class ProjectListResultPayload(PayloadBase):
    """Payload for ``project.list.result`` — project list.

    Sent by the Agent with the list of registered projects.

    Attributes:
        projects: List of project info dicts, each containing
            at minimum ``name`` and ``path`` keys.
    """

    projects: list[dict[str, Any]] = []


class ProjectAddPayload(PayloadBase):
    """Payload for ``project.add`` — add a project directory.

    Sent by the App to register a new project directory.

    Attributes:
        path: Filesystem path to the project directory.
        name: Optional display name (derived from path if omitted).
    """

    path: str
    name: Optional[str] = None


class ProjectRemovePayload(PayloadBase):
    """Payload for ``project.remove`` — remove a project.

    Sent by the App to unregister a project from the list.

    Attributes:
        path: Filesystem path of the project to remove.
    """

    path: str


class ProjectSwitchPayload(PayloadBase):
    """Payload for ``project.switch`` — switch active project.

    Sent by the App to change the active working directory.

    Attributes:
        path: Filesystem path of the project to switch to.
    """

    path: str


class ProjectCurrentPayload(PayloadBase):
    """Payload for ``project.current`` — current project info.

    Sent by the Agent with the currently active project details.

    Attributes:
        name: Display name of the current project.
        path: Filesystem path of the current project.
    """

    name: str = ""
    path: str = ""


class ProjectSearchPayload(PayloadBase):
    """Payload for ``project.search`` — search/browse for projects.

    Dispatches to one of three modes based on which fields are set:
    - ``path`` provided → browse mode (list subdirectories).
    - ``query`` provided (no path) → search mode (scan filesystem).
    - Neither → recent mode (return recently opened projects).

    Attributes:
        query: Search query string (empty for recent mode).
        path: Directory path to browse (None for search/recent mode).
        max_results: Maximum number of results to return.
    """

    query: str = ""
    path: Optional[str] = None
    max_results: Optional[int] = None


class ProjectSearchResultPayload(PayloadBase):
    """Payload for ``project.search.result`` — search results.

    Sent by the Agent with matching project directories.  May be
    sent multiple times for streaming results (``is_complete=False``
    for intermediate batches, ``True`` for the final batch).

    Attributes:
        results: List of matching project/directory info dicts.
        is_browsing: Whether results are from browse mode.
        current_path: The browsed directory path (browse mode only).
        is_complete: Whether this is the final result batch.
        error: Error message if the search failed.
    """

    results: list[dict[str, Any]] = []
    is_browsing: bool = False
    current_path: str = ""
    is_complete: bool = True
    error: Optional[str] = None


# ── Registry wiring ──

register_payload(MessageType.PROJECT_LIST, ProjectListPayload)
register_payload(MessageType.PROJECT_LIST_RESULT, ProjectListResultPayload)
register_payload(MessageType.PROJECT_ADD, ProjectAddPayload)
register_payload(MessageType.PROJECT_REMOVE, ProjectRemovePayload)
register_payload(MessageType.PROJECT_SWITCH, ProjectSwitchPayload)
register_payload(MessageType.PROJECT_CURRENT, ProjectCurrentPayload)
register_payload(MessageType.PROJECT_SEARCH, ProjectSearchPayload)
register_payload(MessageType.PROJECT_SEARCH_RESULT, ProjectSearchResultPayload)
