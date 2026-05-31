"""
AgentProvider abstract base class and unified event types.

This module defines the contract that all AI CLI providers must implement.
Design principle: any ACP-compliant CLI can plug in without special-case logic.

Key types:
  - AgentEventType: Enum of all event types from ACP session/update + extensions.
  - AgentEvent: Unified event structure (type + data dict).
  - ProviderLifecycleState: State machine for provider initialization.
  - ProviderCapabilities: Mirrors ACP AgentCapabilities (session, prompt, MCP, auth).
  - AgentProvider: Abstract base class with lifecycle, session, prompt, config methods.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, AsyncGenerator, Optional


# ── 统一事件类型 ──


class AgentEventType(str, Enum):
    """Unified Agent event types.

    Covers all ACP session/update event types plus application-level extensions.
    Used by ACPConverter to translate raw ACP events into a normalized format
    that the frontend can consume without knowing ACP internals.
    """

    # Text output
    TEXT_CHUNK = "text_chunk"              # Streaming text fragment
    THOUGHT_CHUNK = "thought_chunk"        # AI thinking process
    USER_MESSAGE = "user_message"          # User message (used during replay)

    # Tool calls
    TOOL_CALL_START = "tool_call_start"    # Tool call started
    TOOL_CALL_UPDATE = "tool_call_update"  # Tool progress / result
    TOOL_CALL_END = "tool_call_end"        # Tool call completed

    # File operations
    FILE_EDIT = "file_edit"                # File edit (diff)
    FILE_CREATE = "file_create"            # File created
    FILE_DELETE = "file_delete"            # File deleted

    # Plan
    PLAN_UPDATE = "plan_update"            # Multi-step plan update

    # Mode / commands
    MODE_CHANGE = "mode_change"            # Agent mode change
    COMMANDS_AVAILABLE = "commands_available"  # Available commands list

    # Session info
    SESSION_INFO = "session_info"          # Session metadata (context usage etc.)
    CONFIG_UPDATE = "config_update"        # Config option update (model / thinking level etc.)

    # Control
    TURN_END = "turn_end"                  # Turn ended
    ERROR = "error"                        # Error
    CONFIRM_REQUEST = "confirm_request"    # User confirmation required


@dataclass
class AgentEvent:
    """Unified event structure emitted by providers.

    Attributes:
        type: Event type from AgentEventType enum.
        data: Event payload dict. Keys vary by type (e.g. "text" for TEXT_CHUNK,
            "name"/"id" for TOOL_CALL_START, "error" for ERROR).
    """
    type: AgentEventType
    data: dict[str, Any] = field(default_factory=dict)


# ── Provider lifecycle states ──


class ProviderLifecycleState(str, Enum):
    """Lifecycle states for CLI Provider initialization.

    State machine::

        uninitialized → checking_env → starting → ready
                                          ↓          ↓
                                    auth_required   failed
                                          ↓
                                        ready

    AUTH_REQUIRED is entered when an ACP operation returns error -32000.
    The provider stays in AUTH_REQUIRED until the user submits credentials
    (transitions to READY) or gives up (transitions to FAILED).
    """

    UNINITIALIZED = "uninitialized"
    CHECKING_ENV = "checking_env"
    STARTING = "starting"
    AUTH_REQUIRED = "auth_required"
    READY = "ready"
    FAILED = "failed"


@dataclass
class ProviderCapabilities:
    """Provider capability declaration, mirrors ACP AgentCapabilities.

    Populated during ``initialize()`` from the agent's response. Used by:
    - CLIManager: to decide which operations are available.
    - Frontend: to show/hide UI elements (image upload, session list, etc.).

    Structure mirrors ACP spec:
      - loadSession (top-level boolean)
      - promptCapabilities: image, audio, embeddedContext
      - sessionCapabilities: list, close, fork, resume
      - mcpCapabilities: http, sse
      - auth_methods: list of supported auth methods (env_var, terminal, agent)
      - available_modes: populated after new_session (e.g. code, ask, architect)
    """
    # Basic info
    name: str = ""
    version: str = ""
    protocol: str = "unknown"  # "acp" | "legacy"
    protocol_version: int = 1  # ACP protocol version negotiated during initialize

    # Top-level: session/load support
    supports_session_load: bool = False

    # promptCapabilities
    supports_image: bool = False
    supports_audio: bool = False
    supports_embedded_context: bool = False

    # sessionCapabilities
    supports_session_list: bool = False
    supports_session_close: bool = False
    supports_session_fork: bool = False
    supports_session_resume: bool = False

    # mcpCapabilities
    supports_mcp_http: bool = False
    supports_mcp_sse: bool = False

    # Auth methods advertised during initialize
    auth_methods: list[dict] = field(default_factory=list)

    # Available modes (populated after new_session)
    available_modes: list[dict] = field(default_factory=list)

    # Lifecycle state tracking
    lifecycle_state: ProviderLifecycleState = ProviderLifecycleState.UNINITIALIZED
    error_message: str = ""

    def to_capability_dict(self) -> dict:
        """Export capability fields as a flat dict for CLIInfo / cli.status payload.

        Returns:
            Dict with all boolean capability flags and available_modes list.
            Does NOT include name, version, protocol, auth_methods, or lifecycle state.
        """
        return {
            "supports_session_load": self.supports_session_load,
            "supports_image": self.supports_image,
            "supports_audio": self.supports_audio,
            "supports_embedded_context": self.supports_embedded_context,
            "supports_session_list": self.supports_session_list,
            "supports_session_close": self.supports_session_close,
            "supports_session_fork": self.supports_session_fork,
            "supports_session_resume": self.supports_session_resume,
            "supports_mcp_http": self.supports_mcp_http,
            "supports_mcp_sse": self.supports_mcp_sse,
            "available_modes": self.available_modes,
        }

    @property
    def is_resume_only(self) -> bool:
        """True if provider supports resume but NOT load (needs local history).

        Resume-only CLIs require local history persistence because they
        cannot replay history on reconnection. The Agent persists messages
        locally and serves them after a successful resume.
        """
        return self.supports_session_resume and not self.supports_session_load


class AgentProvider(ABC):
    """Abstract base class for AI Agent interaction.

    Defines the complete contract for ACP CLI providers. All methods map to
    ACP protocol operations. Abstract methods (``@abstractmethod``) must be
    implemented by every provider. Non-abstract methods have sensible defaults
    for agents that don't support the feature.

    Lifecycle: initialize → (authenticate) → new_session → prompt → cancel → shutdown
    """

    # Execution environment: "native" or "wsl". Set by subclass __init__
    # and may be overridden at runtime by ProviderRegistry.set_execution_env.
    _execution_env: str = "native"

    @property
    def execution_env(self) -> str:
        """The execution environment this provider runs in ("native" or "wsl")."""
        return self._execution_env

    @execution_env.setter
    def execution_env(self, value: str) -> None:
        self._execution_env = value

    # ── Lifecycle ──

    @abstractmethod
    async def initialize(self, cwd: str) -> ProviderCapabilities:
        """Start the agent process and complete the initialize handshake.

        Args:
            cwd: Working directory for the agent.

        Returns:
            Negotiated capabilities.
        """
        ...

    @abstractmethod
    async def shutdown(self):
        """Gracefully shut down the connection and kill the agent process."""
        ...

    async def authenticate(self, method_id: str, data: dict) -> bool:
        """Authenticate with the agent if required.

        Args:
            method_id: Auth method identifier from capabilities.
            data: Credentials dict (varies by auth type).

        Returns:
            True if authentication succeeded.
        """
        return True

    # ── Session management ──

    @abstractmethod
    async def new_session(self, cwd: str, mcp_servers: list[dict] | None = None) -> str:
        """Create a new session.

        Args:
            cwd: Working directory for the session.
            mcp_servers: Optional MCP server configs.

        Returns:
            The new session_id.
        """
        ...

    async def load_session(self, session_id: str) -> list[dict]:
        """Load an existing session and return replayed history.

        Args:
            session_id: Session to load.

        Returns:
            List of history message dicts, or [] if unsupported.
        """
        return []

    async def list_sessions(self) -> list[dict]:
        """List all sessions.

        Returns:
            List of session info dicts, or [] if unsupported.
        """
        return []

    async def close_session(self, session_id: str):
        """Close a session.

        Args:
            session_id: Session to close.
        """
        pass

    async def fork_session(self, session_id: str) -> str:
        """Fork a session into a new branch.

        Args:
            session_id: Session to fork.

        Returns:
            New session_id, or "" if unsupported.
        """
        return ""

    async def resume_session(self, session_id: str) -> bool:
        """Resume a session (restore server-side context without history replay).

        Used by the resume-first reconnection strategy: the Agent tries
        session/resume first (fast, no history transfer), then falls back
        to session/load if resume is unavailable or fails.

        Subclasses that support ACP session/resume should override this
        to call the underlying connection's resume_session method.

        Args:
            session_id: The session to resume.

        Returns:
            True if resume succeeded, False if unsupported or failed.
        """
        return False

    async def logout(self) -> bool:
        """Logout from the current authenticated state.

        After logout, new sessions will require re-authentication.
        Existing running sessions may continue until they end naturally.

        Subclasses that support ACP logout should override this to call
        the underlying connection's logout method.

        Returns:
            True if logout succeeded, False if unsupported or failed.
        """
        return False

    # ── Prompt ──

    @abstractmethod
    async def prompt(
        self,
        session_id: str,
        content: str,
        images: list[dict] | None = None,
        audio_files: list[dict] | None = None,
        resources: list[dict] | None = None,
    ) -> AsyncGenerator[AgentEvent, None]:
        """Send a prompt with optional multimodal content, stream back events.

        Args:
            session_id: Target session.
            content: Text content of the user message.
            images: Optional image attachments.
            audio_files: Optional audio attachments.
            resources: Optional resource/resource_link attachments.

        Yields:
            AgentEvent objects. Always ends with TURN_END.
        """
        ...

    @abstractmethod
    async def cancel(self, session_id: str):
        """Cancel ongoing operations for a session.

        Args:
            session_id: Session to cancel.
        """
        ...

    # ── Configuration ──

    async def set_model(self, session_id: str, model: str):
        """Switch the AI model for a session.

        Args:
            session_id: Target session.
            model: Model identifier string.
        """
        pass

    async def set_mode(self, session_id: str, mode_id: str):
        """Switch the agent mode for a session.

        Args:
            session_id: Target session.
            mode_id: Mode identifier (e.g. "code", "ask").
        """
        pass

    async def set_config_option(self, session_id: str, config_id: str, value: str | bool) -> list[dict]:
        """Set a configuration option and return the updated config list.

        Per ACP spec, the response contains the complete list of all config
        options with updated values.

        Args:
            session_id: Target session.
            config_id: Config option identifier (e.g. "model", "thinking_level").
            value: New value — string or boolean depending on the option type.

        Returns:
            Updated config options list (serialized dicts), or [] on failure.
        """
        return []

    def consume_pending_config(self) -> tuple[list[dict] | None, str]:
        """Consume and return pending config data from new_session response.

        ACP new_session returns configOptions (model, mode, thought_level, etc.)
        but these can't go through the event collector (cleared before each prompt).
        This method returns the pending data and clears it.

        Returns:
            Tuple of (config_options_list_or_None, initial_mode_id_or_empty).
        """
        return None, ""

    # ── State ──

    @property
    @abstractmethod
    def is_running(self) -> bool:
        """Whether the agent process is running and connected."""
        ...

    @property
    def capabilities(self) -> Optional[ProviderCapabilities]:
        """Negotiated capabilities (available after initialize)."""
        return None
