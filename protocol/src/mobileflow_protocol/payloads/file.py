"""File domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the sixteen file-related message types:
  - file.tree           (FILE_TREE)           — request directory tree
  - file.tree.result    (FILE_TREE_RESULT)    — directory tree data
  - file.read           (FILE_READ)           — request file content
  - file.read.result    (FILE_READ_RESULT)    — file content response
  - file.write          (FILE_WRITE)          — write file content
  - file.write.result   (FILE_WRITE_RESULT)   — write result
  - file.search         (FILE_SEARCH)         — search files/content
  - file.search.result  (FILE_SEARCH_RESULT)  — search results (final)
  - file.search.stream  (FILE_SEARCH_STREAM)  — search results (streaming)
  - file.create         (FILE_CREATE)         — create file or directory
  - file.create.result  (FILE_CREATE_RESULT)  — create result
  - file.rename         (FILE_RENAME)         — rename file or directory
  - file.rename.result  (FILE_RENAME_RESULT)  — rename result
  - file.delete         (FILE_DELETE)         — delete file or directory
  - file.delete.result  (FILE_DELETE_RESULT)  — delete result
  - file.changed        (FILE_CHANGED)        — file system change notification

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Any, Optional

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


# ── Request payloads (App -> Agent) ──


class FileTreePayload(PayloadBase):
    """Payload for ``file.tree`` — request directory tree.

    Sent by the App to request the file tree starting at a given path.
    The Agent returns a nested tree structure up to the specified depth.

    Attributes:
        path: Root path to list (default "/").
        depth: Maximum directory depth to traverse.
    """

    path: str = "/"
    depth: int = 2


class FileReadPayload(PayloadBase):
    """Payload for ``file.read`` — request file content.

    Sent by the App to read a single file's content.

    Attributes:
        path: Absolute or relative path of the file to read.
    """

    path: str


class FileWritePayload(PayloadBase):
    """Payload for ``file.write`` — write file content.

    Sent by the App to write content to a file on the Agent's
    file system.

    Attributes:
        path: Absolute or relative path of the file to write.
        content: New file content.
    """

    path: str
    content: str


class FileSearchPayload(PayloadBase):
    """Payload for ``file.search`` — search files or content.

    Sent by the App to perform a file name or content search.
    Supports regex, case-sensitive, and whole-word matching flags.

    Attributes:
        query: Search query string.
        search_content: Whether to search inside file content.
        is_regex: Whether the query is a regular expression.
        case_sensitive: Whether the search is case-sensitive.
        whole_word: Whether to match whole words only.
    """

    query: str
    search_content: bool = False
    is_regex: bool = False
    case_sensitive: bool = False
    whole_word: bool = False


class FileCreatePayload(PayloadBase):
    """Payload for ``file.create`` — create a new file or directory.

    Sent by the App to create a file or directory under the given
    parent path.

    Attributes:
        path: Relative path to the parent directory.
        name: Name of the new file or directory.
        type: Node type — ``"file"`` or ``"directory"``.
    """

    path: str = ""
    name: str = ""
    type: str = "file"


class FileRenamePayload(PayloadBase):
    """Payload for ``file.rename`` — rename a file or directory.

    Sent by the App to rename an existing file or directory.

    Attributes:
        path: Relative path to the existing file or directory.
        new_name: New name (not a full path).
    """

    path: str = ""
    new_name: str = ""


class FileDeletePayload(PayloadBase):
    """Payload for ``file.delete`` — delete a file or directory.

    Sent by the App to delete a file or directory (recursively
    for directories).

    Attributes:
        path: Relative path to the file or directory.
    """

    path: str = ""


# ── Response payloads (Agent -> App) ──


class FileTreeResultPayload(PayloadBase):
    """Payload for ``file.tree.result`` — directory tree data.

    Returned by the Agent with the nested file tree structure.

    Attributes:
        data: List of serialized FileNode dicts representing the tree.
        req_path: The path that was originally requested.
    """

    data: list[dict[str, Any]] = []
    req_path: str = "/"


class FileReadResultPayload(PayloadBase):
    """Payload for ``file.read.result`` — file content response.

    Returned by the Agent with the file's content and metadata.

    Attributes:
        path: Absolute path of the file.
        content: File content (None on error).
        language: Detected programming language.
        line_count: Number of lines in the file.
        error: Error message if read failed.
    """

    path: str
    content: Optional[str] = None
    language: Optional[str] = None
    line_count: int = 0
    error: Optional[str] = None


class FileWriteResultPayload(PayloadBase):
    """Payload for ``file.write.result`` — write result.

    Returned by the Agent after a file write operation.

    Attributes:
        success: Whether the write succeeded.
        path: Path of the file that was written.
    """

    success: bool
    path: str


class FileSearchResultPayload(PayloadBase):
    """Payload for ``file.search.result`` — final search results.

    Sent by the Agent when the search completes, containing the
    full result set.

    Attributes:
        results: List of search result dicts.
        query: The original search query (empty string if not echoed).
    """

    results: list[dict[str, Any]] = []
    query: str = ""


class FileSearchStreamPayload(PayloadBase):
    """Payload for ``file.search.stream`` — streaming search results.

    Sent by the Agent incrementally as search results are found,
    before the final ``file.search.result`` message.

    Attributes:
        results: Batch of search result dicts found so far.
        total: Running total of results found across all batches.
    """

    results: list[dict[str, Any]] = []
    total: int = 0


class FileCreateResultPayload(PayloadBase):
    """Payload for ``file.create.result`` — create result.

    Returned by the Agent after a file/directory creation attempt.

    Attributes:
        success: Whether the creation succeeded.
        path: Relative path of the created file/directory (on success).
        error: Error message if creation failed.
    """

    success: bool = False
    path: Optional[str] = None
    error: Optional[str] = None


class FileRenameResultPayload(PayloadBase):
    """Payload for ``file.rename.result`` — rename result.

    Returned by the Agent after a rename attempt.

    Attributes:
        success: Whether the rename succeeded.
        old_path: Original path before rename.
        new_path: New path after rename (on success).
        error: Error message if rename failed.
    """

    success: bool = False
    old_path: Optional[str] = None
    new_path: Optional[str] = None
    error: Optional[str] = None


class FileDeleteResultPayload(PayloadBase):
    """Payload for ``file.delete.result`` — delete result.

    Returned by the Agent after a delete attempt.

    Attributes:
        success: Whether the deletion succeeded.
        path: Path of the deleted file/directory.
        error: Error message if deletion failed.
    """

    success: bool = False
    path: Optional[str] = None
    error: Optional[str] = None


# ── Notification payloads (Agent -> App) ──


class FileChangedPayload(PayloadBase):
    """Payload for ``file.changed`` — file system change notification.

    Pushed by the Agent when a file system change is detected
    (e.g. by a file watcher).

    Attributes:
        path: Relative path of the changed file.
        change: Change type — ``"created"``, ``"modified"``, or ``"deleted"``.
    """

    path: str
    change: str


# ── Registry wiring ──
# Register all file payload models so Message.typed_payload() and
# get_payload_class() can resolve them by MessageType.

register_payload(MessageType.FILE_TREE, FileTreePayload)
register_payload(MessageType.FILE_TREE_RESULT, FileTreeResultPayload)
register_payload(MessageType.FILE_READ, FileReadPayload)
register_payload(MessageType.FILE_READ_RESULT, FileReadResultPayload)
register_payload(MessageType.FILE_WRITE, FileWritePayload)
register_payload(MessageType.FILE_WRITE_RESULT, FileWriteResultPayload)
register_payload(MessageType.FILE_SEARCH, FileSearchPayload)
register_payload(MessageType.FILE_SEARCH_RESULT, FileSearchResultPayload)
register_payload(MessageType.FILE_SEARCH_STREAM, FileSearchStreamPayload)
register_payload(MessageType.FILE_CREATE, FileCreatePayload)
register_payload(MessageType.FILE_CREATE_RESULT, FileCreateResultPayload)
register_payload(MessageType.FILE_RENAME, FileRenamePayload)
register_payload(MessageType.FILE_RENAME_RESULT, FileRenameResultPayload)
register_payload(MessageType.FILE_DELETE, FileDeletePayload)
register_payload(MessageType.FILE_DELETE_RESULT, FileDeleteResultPayload)
register_payload(MessageType.FILE_CHANGED, FileChangedPayload)
