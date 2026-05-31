"""Shared data models for App-Agent protocol payloads.

Contains Pydantic models that appear inside message payloads but are
not messages themselves. These are the "nouns" of the protocol (CLI
info, file nodes, chat context) as opposed to the "verbs" (message
types).
"""

from __future__ import annotations

from enum import Enum
from typing import Optional

from pydantic import BaseModel


# ── Chat ──


class ChatContext(BaseModel):
    """Contextual information about the user's current editor state.

    Sent with ``chat.send`` so the AI CLI knows which file the user
    is looking at and which lines are selected.

    Attributes:
        active_file: Absolute path of the file open in the editor.
        selected_lines: Line numbers currently selected (1-based).
        work_dir: Override working directory for this message.
    """

    active_file: Optional[str] = None
    selected_lines: Optional[list[int]] = None
    work_dir: Optional[str] = None


# ── Streaming ──


class StreamChunkType(str, Enum):
    """Discriminator for streaming output chunks.

    Each chunk in a ``chat.stream`` message carries one of these types
    to tell the App how to render it.
    """

    TEXT = "text"                  # Markdown text from the AI
    CODE = "code"                 # Code block with optional language
    DIFF = "diff"                 # File modification diff
    THINKING = "thinking"         # AI reasoning / chain-of-thought
    TOOL_USE = "tool_use"         # Tool call start (name, input, status)
    TOOL_UPDATE = "tool_update"   # Tool call progress or result update
    ERROR = "error"               # Error message from the AI or tool
    STATUS = "status"             # Agent status change (idle, thinking, etc.)
    MODE_CHANGE = "mode_change"   # ACP current_mode_update notification
    CONFIG_UPDATE = "config_update"  # ACP config_option_update notification
    SESSION_INFO = "session_info"  # ACP session_info_update notification


class StreamChunk(BaseModel):
    """A single chunk of streaming output from the AI agent.

    The ``type`` field determines which optional fields are populated.
    For example, a DIFF chunk uses ``file_path``, ``old_content``, and
    ``new_content``; a TOOL_USE chunk uses ``kind``, ``tool_input``,
    ``tool_id``, and ``status``.

    Attributes:
        type: Chunk discriminator (text, code, diff, tool_use, etc.).
        content: Primary text content of the chunk.
        language: Programming language for CODE chunks.
        file_path: File path for DIFF and TOOL_USE chunks.
        old_content: Original content before modification (DIFF).
        new_content: Modified content after modification (DIFF).
        kind: Tool category (edit, execute, read, etc.) for TOOL_USE.
        tool_input: Tool invocation input (command, path, etc.).
        tool_id: Unique tool call ID for matching updates to calls.
        status: Tool execution status (running, completed, failed).
        locations: File locations involved in the tool call.
        terminal_id: Embedded terminal ID for Terminal-type content.
        content_blocks: Raw ACP ToolCallContent blocks.
    """

    type: StreamChunkType
    content: str
    language: Optional[str] = None
    file_path: Optional[str] = None
    old_content: Optional[str] = None
    new_content: Optional[str] = None
    kind: Optional[str] = None
    tool_input: Optional[str] = None
    tool_id: Optional[str] = None
    status: Optional[str] = None
    locations: Optional[list[dict]] = None
    terminal_id: Optional[str] = None
    content_blocks: Optional[list[dict]] = None


# ── File ──


class FileNode(BaseModel):
    """A node in the file tree (file or directory).

    Attributes:
        name: File or directory name (not full path).
        type: Node type — ``"file"`` or ``"dir"``.
        size: File size in bytes (files only).
        git_status: Git working tree status (modified, staged, untracked).
        children: Child nodes (directories only).
    """

    name: str
    type: str  # "file" | "dir"
    size: Optional[int] = None
    git_status: Optional[str] = None
    children: Optional[list[FileNode]] = None


# ── CLI ──


class CLIInfo(BaseModel):
    """CLI adapter information with ACP capability declaration.

    Returned in ``cli.list.result`` and ``cli.status`` payloads.
    Capability flags reflect what the CLI agent declared during the
    ACP ``initialize`` handshake.

    Attributes:
        name: Internal CLI identifier (e.g. "codex", "kiro").
        display_name: Human-readable name shown in the App UI.
        installed: Whether the CLI binary is available on the system.
        version: CLI version string (from ACP agent_info).
        install_hint: Human-readable install instructions.
        install_npm: npm package name for one-click install.
        is_custom: Whether this is a user-added custom agent.
        can_install: Whether install/uninstall via npm is supported.
        source: Origin of the CLI entry (builtin, custom, plugin).
        supports_session_load: ACP loadSession capability.
        supports_image: ACP promptCapabilities.image.
        supports_audio: ACP promptCapabilities.audio.
        supports_embedded_context: ACP promptCapabilities.embeddedContext.
        supports_session_list: ACP sessionCapabilities.list.
        supports_session_close: ACP sessionCapabilities.close.
        supports_session_fork: ACP sessionCapabilities.fork.
        supports_session_resume: ACP sessionCapabilities.resume.
        supports_mcp_http: ACP mcpCapabilities.http.
        supports_mcp_sse: ACP mcpCapabilities.sse.
        available_modes: Session modes (populated after session creation).
    """

    name: str
    display_name: str
    installed: bool
    version: Optional[str] = None
    install_hint: Optional[str] = None
    install_npm: Optional[str] = None
    is_custom: bool = False
    can_install: bool = False
    source: str = "builtin"

    # ACP AgentCapabilities
    supports_session_load: bool = False

    # ACP promptCapabilities
    supports_image: bool = False
    supports_audio: bool = False
    supports_embedded_context: bool = False

    # ACP sessionCapabilities
    supports_session_list: bool = False
    supports_session_close: bool = False
    supports_session_fork: bool = False
    supports_session_resume: bool = False

    # ACP mcpCapabilities
    supports_mcp_http: bool = False
    supports_mcp_sse: bool = False

    # Available modes
    available_modes: list[dict] = []


# ── Auth ──


class AuthPairPayload(BaseModel):
    """Payload for ``auth.pair`` — initial device pairing request.

    Attributes:
        token: 6-digit pairing code displayed on the Agent.
        device_name: Optional human-readable device name.
    """

    token: str
    device_name: Optional[str] = None


class AuthResultPayload(BaseModel):
    """Payload for ``auth.result`` — authentication outcome.

    Attributes:
        success: Whether authentication succeeded.
        session_token: Persistent token for future reconnections.
        error: Error message on failure.
    """

    success: bool
    session_token: Optional[str] = None
    error: Optional[str] = None


# ── Chat payloads (backward-compatible aliases) ──
# Canonical definitions live in payloads/chat.py (PayloadBase subclasses).
# These aliases keep existing ``from mobileflow_protocol.models import ...``
# imports working during the migration period.

from .payloads.chat import ChatDonePayload as ChatDonePayload  # noqa: F401
from .payloads.chat import ChatSendPayload as ChatSendPayload  # noqa: F401
from .payloads.chat import ChatStreamPayload as ChatStreamPayload  # noqa: F401


# ── File payloads (backward-compatible aliases) ──
# Canonical definitions live in payloads/file.py (PayloadBase subclasses).
# These aliases keep existing ``from mobileflow_protocol.models import ...``
# imports working during the migration period.

from .payloads.file import FileTreePayload as FileTreePayload  # noqa: F401
from .payloads.file import FileReadPayload as FileReadPayload  # noqa: F401
from .payloads.file import FileReadResultPayload as FileReadResultPayload  # noqa: F401
from .payloads.file import FileWritePayload as FileWritePayload  # noqa: F401
from .payloads.file import FileSearchPayload as FileSearchPayload  # noqa: F401
