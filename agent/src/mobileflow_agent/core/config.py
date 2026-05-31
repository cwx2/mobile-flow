"""
Agent configuration management.

Loading priority (low → high):
  1. Code defaults (fallback)
  2. config/default.json (base config, committed)
  3. config/{env}.json (environment override, committed)
  4. .env file (local secrets, not committed)
  5. MOBILEFLOW_* environment variables (deployment override)

Set MOBILEFLOW_ENV to switch environments: development (default) / production.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Optional

from pydantic import Field
from pydantic_settings import BaseSettings
from loguru import logger

from ..utils.json_file import load_json_file


def _find_project_root() -> Path:
    """Find the agent project root directory.

    In development: walks up from this file to find pyproject.toml.
    In PyInstaller bundle: uses sys._MEIPASS (the temp extraction directory).
    """
    # PyInstaller bundle: config files are extracted to sys._MEIPASS
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        return Path(sys._MEIPASS)

    # Development: walk up to find pyproject.toml
    current = Path(__file__).resolve().parent
    for _ in range(10):
        if (current / "pyproject.toml").exists():
            return current
        current = current.parent
    return Path.cwd()


def _load_json_config(path: Path) -> dict[str, Any]:
    """Load a JSON config file, return empty dict on any error."""
    data = load_json_file(path, default={})
    if isinstance(data, dict):
        if data:
            logger.trace(f"配置已加载: {path}")
        return data
    return {}


def _deep_merge(base: dict, override: dict) -> dict:
    """Deep merge two dicts. override values win, nested dicts are merged recursively."""
    result = base.copy()
    for key, value in override.items():
        if key.startswith("_"):
            continue  # skip comment fields
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def _find_env_file() -> Path | None:
    """Find .env file: check project root first, then cwd."""
    for base in [_find_project_root(), Path.cwd()]:
        env_path = base / ".env"
        if env_path.is_file():
            return env_path
    return None


def _load_layered_config() -> dict[str, Any]:
    """Load config/default.json → config/{env}.json, deep-merged."""
    root = _find_project_root()
    config_dir = root / "config"

    # Layer 1: default.json
    base = _load_json_config(config_dir / "default.json")

    # Layer 2: environment-specific override
    env = os.environ.get("MOBILEFLOW_ENV", "development")
    env_config = _load_json_config(config_dir / f"{env}.json")
    if env_config:
        base = _deep_merge(base, env_config)
        logger.trace(f"环境配置已合并: {env}")

    # Strip _comment keys recursively
    return _strip_comments(base)


def _strip_comments(d: dict) -> dict:
    """Recursively remove keys starting with _ (comment fields) from a dict."""
    result = {}
    for k, v in d.items():
        if k.startswith("_"):
            continue
        result[k] = _strip_comments(v) if isinstance(v, dict) else v
    return result


# ── Sub-config models ──


class SecurityConfig(BaseSettings):
    """Security policy configuration."""

    # Session timeout (seconds)
    session_timeout: int = 3600


class WebSocketConfig(BaseSettings):
    """WebSocket server tuning parameters."""

    # Max incoming message size (MB)
    max_message_size_mb: int = 10
    # Ping interval (seconds)
    ping_interval: int = 30
    # Ping timeout (seconds)
    ping_timeout: int = 60
    # Close handshake timeout (seconds)
    close_timeout: int = 10


class LifecycleConfig(BaseSettings):
    """CLI provider lifecycle timeouts and recovery settings."""

    # Init timeout for native environment (seconds)
    init_timeout_native: int = 30
    # Init timeout for WSL environment (seconds)
    init_timeout_wsl: int = 60
    # Auth wait timeout: how long to wait for user to submit credentials (seconds)
    auth_wait_timeout: int = 300
    # Auth device code timeout: how long to wait for device code flow completion (seconds).
    # Set to 600s (10 min) to accommodate slow browser logins on mobile.
    auth_device_code_timeout: int = 600
    # Auth verification poll interval: how often to probe ACP for auth success
    # when the CLI process hangs after user completes browser login (seconds).
    auth_verification_poll_interval: int = 10
    # Auth agent timeout: how long to wait for agent-type auth to complete (seconds)
    auth_agent_timeout: int = 30
    # Recovery poll interval (seconds)
    recovery_poll_interval: int = 10
    # Max recovery tracking duration (seconds)
    recovery_max_duration: int = 300
    # Progressive status messages shown during slow startup (i18n keys)
    progressive_msg_10s: str = "backend.startupSlow10s"
    progressive_msg_20s: str = "backend.startupSlow20s"

    # Graceful shutdown timeouts (seconds)
    shutdown_total_timeout: int = 30       # Total time allowed for full shutdown
    provider_shutdown_timeout: int = 10    # Per-provider ACP shutdown
    terminal_shutdown_timeout: int = 5     # Per-terminal session stop
    process_terminate_timeout: int = 5     # SIGTERM → wait before SIGKILL


class GitConfig(BaseSettings):
    """Git command execution settings."""

    # Default timeout for git commands (seconds)
    command_timeout: int = 30
    # Timeout for git discovery operations (seconds)
    discovery_timeout: int = 5
    # Number of commits per page in git log pagination
    log_page_size: int = 50


class AttachmentConfig(BaseSettings):
    """File attachment size limits for multimodal input."""

    # Max image file size (MB)
    max_image_size_mb: int = 5
    # Max audio file size (MB)
    max_audio_size_mb: int = 10


class ContextConfig(BaseSettings):
    """Context reference resolution settings.

    Controls how context references (files, folders, git diffs, terminal output,
    etc.) are resolved and included in AI prompts. Token budget prevents
    oversized prompts; per-reference limits keep individual items reasonable.
    """

    # Max estimated tokens for all context in one prompt
    token_budget: int = 30000
    # Characters per token for estimation (GPT-4 average ~4)
    chars_per_token: float = 4.0
    # Max folder tree depth for folder references
    max_folder_depth: int = 3
    # Max file size in bytes for inclusion (files larger are truncated)
    max_file_size: int = 512_000  # 500 KB
    # Max number of context references per message
    max_references: int = 10
    # Max terminal output lines for terminal references
    max_terminal_lines: int = 50


class ProjectScannerConfig(BaseSettings):
    """Project scanner configuration for search and browse.

    Controls how the ProjectScanner service discovers project directories
    on the filesystem. All values are configurable via config/default.json
    under the ``project_scanner`` section.
    """

    # Root directories to search (empty = auto-detect based on OS)
    search_roots: list[str] = []
    # Maximum directory traversal depth from each search root
    max_depth: int = 3
    # Search timeout in seconds (partial results returned on timeout)
    search_timeout: float = 5.0
    # Maximum number of search results to return
    max_results: int = 20
    # Maximum recent projects to return in the picker
    recent_projects_limit: int = 10


class ConnectionConfig(BaseSettings):
    """Connection mode and transport-specific settings.

    Controls reconnection behaviour for Relay and Tunnel modes,
    and brute-force protection thresholds for pairing authentication.
    All values are configurable via config/default.json or env vars.
    """

    # Relay reconnect: exponential backoff 1s→2s→4s→5s cap
    relay_reconnect_max_attempts: int = 10
    relay_reconnect_initial_delay: float = 1.0
    relay_reconnect_max_delay: float = 5.0

    # Brute-force protection for pairing code verification
    pair_max_failures: int = 3
    pair_lockout_seconds: int = 60

    # Tunnel reconnect: linear backoff
    tunnel_reconnect_max_attempts: int = 5
    tunnel_reconnect_delay: float = 2.0

    # Disconnect grace period (seconds): keep ACP processes alive after
    # client disconnects, allowing seamless reconnection within this window.
    # Set to 0 to disable (immediate cleanup on disconnect).
    disconnect_grace_period: int = 600


class StreamReplayConfig(BaseSettings):
    """Stream replay buffer settings for disconnect recovery.

    Controls the per-client ring buffer that stores streaming chunks
    during an AI turn, enabling reconnecting clients to catch up on
    missed output without interrupting the AI operation.
    """

    # Maximum number of chunks to buffer per client per turn.
    # 500 chunks ≈ 10-20 minutes of typical AI output at ~500KB.
    # Oldest chunks are silently dropped when the buffer is full;
    # the App can fall back to chat.history for the complete conversation.
    max_chunks: int = 500


class TimeoutsConfig(BaseSettings):
    """Miscellaneous timeout values for operations not covered by lifecycle/git configs.

    These were previously hardcoded in various modules. Centralising them here
    makes tuning easier across environments (e.g. slower CI machines).
    """

    # Timeout for checking if a process is alive via tasklist (Windows only, seconds)
    process_alive_check: float = 3
    # Timeout for taskkill /F /T on Windows (seconds)
    process_kill: float = 5
    # Timeout for ripgrep process cleanup after search completes (seconds)
    file_search: float = 2
    # Timeout for ripgrep chunk read during streaming search (seconds)
    file_search_cancel: float = 0.5
    # Timeout for waiting for user permission response (seconds)
    permission_response: float = 120
    # Timeout for new_session verification during provider init (seconds)
    new_session_verify: float = 15
    # Timeout for ACP session/load call during history retrieval (seconds).
    # Only covers the load_session RPC, NOT provider initialization.
    session_load: float = 10


class HistoryConfig(BaseSettings):
    """Chat history pagination settings.

    Controls how many messages are sent to the App per page when loading
    session history. The Agent caches the full history in memory and
    serves pages on demand via chat.history.more requests.

    Two limits work together: page_size (max items) and page_max_bytes
    (max payload size). Whichever limit is hit first ends the page.
    This prevents large tool call results from creating oversized payloads
    that are slow to transmit over remote connections.
    """

    # Maximum number of messages per page
    page_size: int = 30
    # Maximum approximate payload size per page (bytes).
    # Measured by summing the 'content' field lengths of each message.
    # 64KB keeps each page fast even on Relay/Tunnel connections.
    page_max_bytes: int = 65536


class CacheConfig(BaseSettings):
    """Cache layer settings for operation-driven state refresh.

    Controls how the RefreshScheduler responds to file system events.
    """

    # Enable/disable auto-refresh on file system events
    auto_refresh: bool = True
    # Seconds to wait after last FS event before triggering refresh (debounce)
    debounce_delay: float = 1.0
    # Seconds to wait after refresh before allowing next (cooldown)
    cooldown: float = 5.0
    # Max changed files before marking repo as "huge" and disabling auto-refresh
    status_limit: int = 5000
    # Enable periodic git fetch (default false — opt-in for multi-dev workflows)
    auto_fetch: bool = False
    # Seconds between auto-fetch cycles (default 180)
    auto_fetch_period: int = 180


class PreviewConfig(BaseSettings):
    """Preview proxy configuration.

    Controls the reverse proxy that forwards dev server content to the
    phone's WebView. All values were previously hardcoded in port_proxy.py
    and executor.py.
    """

    # Health check polling interval (seconds)
    health_check_interval: float = 2.0
    # Health check single-probe timeout (seconds)
    health_check_probe_timeout: int = 10
    # Proxy request forwarding timeout (seconds)
    proxy_request_timeout: int = 60
    # Max body size for URL rewriting (MB). Bodies larger than this
    # skip rewriting to prevent memory exhaustion on huge files.
    max_rewrite_body_size_mb: int = 50
    # HTTPS interceptor port for catching https:// API requests
    https_interceptor_port: int = 443
    # Number of health check polls before logging a warning
    health_check_warning_threshold: int = 30


class SessionResumeConfig(BaseSettings):
    """Session resume behavior configuration.

    Controls the ACP session/resume feature which enables fast reconnection
    by restoring server-side session context without replaying full history.
    Local history persistence is used for resume-only CLIs (those that support
    resume but not load).
    """

    # Timeout for the session/resume ACP call (seconds).
    # Shorter than session/load timeout because resume should be fast (no history replay).
    timeout: float = 5.0
    # Max messages to persist locally per session (for resume-only CLIs).
    # Older messages are dropped when this cap is exceeded.
    max_history_messages: int = 200


class WslConfig(BaseSettings):
    """WSL child Agent settings.

    Controls the child Agent process that runs inside WSL for executing
    WSL-installed CLIs natively.
    """

    # Port for the WSL child Agent's WebSocket server
    child_port: int = 9601
    # Timeout for child Agent startup (seconds)
    startup_timeout: float = 30.0


# ── Main config ──


class AgentConfig(BaseSettings):
    """Agent main configuration.

    Sources (low → high priority):
      1. Field defaults in this class
      2. config/default.json
      3. config/{MOBILEFLOW_ENV}.json
      4. .env file
      5. MOBILEFLOW_* environment variables
    """

    model_config = {
        "env_prefix": "MOBILEFLOW_",
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }

    # Network
    host: str = "0.0.0.0"
    port: int = 9600

    # Log level (DEBUG / INFO / WARNING / ERROR)
    log_level: str = "INFO"

    # Connection mode (lan / relay / tunnel)
    connection_mode: str = "lan"

    # Relay Server config (used when connection_mode=relay)
    relay_url: str = ""

    # Device ID (auto-generated on first start, used for Relay routing)
    device_id: str = ""

    # Working directory (empty = current directory)
    work_dir: str = Field(default="")

    # WSL child Agent mode (set by --mode wsl-child, not from config file).
    # When True, the Agent runs in a stripped-down mode inside WSL:
    # only CLI management + terminal PTY, no file/git/project services.
    wsl_child_mode: bool = False

    # Default CLI (empty = auto-select first installed)
    default_cli: str = ""

    # Pairing token (auto-generated on first start)
    pair_token: Optional[str] = None

    # Tunnel mode config
    tunnel_bearer_token: str = ""
    tunnel_tls_cert: str = ""
    tunnel_tls_key: str = ""

    # Sub-configs
    security: SecurityConfig = Field(default_factory=SecurityConfig)
    websocket: WebSocketConfig = Field(default_factory=WebSocketConfig)
    lifecycle: LifecycleConfig = Field(default_factory=LifecycleConfig)
    git: GitConfig = Field(default_factory=GitConfig)
    attachments: AttachmentConfig = Field(default_factory=AttachmentConfig)
    context: ContextConfig = Field(default_factory=ContextConfig)
    project_scanner: ProjectScannerConfig = Field(default_factory=ProjectScannerConfig)
    connection: ConnectionConfig = Field(default_factory=ConnectionConfig)
    history: HistoryConfig = Field(default_factory=HistoryConfig)
    timeouts: TimeoutsConfig = Field(default_factory=TimeoutsConfig)
    cache: CacheConfig = Field(default_factory=CacheConfig)
    wsl: WslConfig = Field(default_factory=WslConfig)
    stream_replay: StreamReplayConfig = Field(default_factory=StreamReplayConfig)
    preview: PreviewConfig = Field(default_factory=PreviewConfig)
    session_resume: SessionResumeConfig = Field(default_factory=SessionResumeConfig)

    # Data directory
    data_dir: Path = Field(
        default_factory=lambda: Path.home() / ".mobileflow"
    )

    def __init__(self, **kwargs):
        # Load layered JSON config as base values
        json_defaults = _load_layered_config()

        # JSON values are overridden by kwargs (CLI args, env vars, .env)
        merged = {**json_defaults, **kwargs}
        super().__init__(**merged)

        env = os.environ.get("MOBILEFLOW_ENV", "development")
        logger.trace(f"配置初始化完成: env={env}, port={self.port}, log_level={self.log_level}")

    def ensure_data_dir(self) -> Path:
        """Ensure data directory exists."""
        self.data_dir.mkdir(parents=True, exist_ok=True)
        return self.data_dir

    def ensure_device_id(self) -> str:
        """Ensure device_id exists (auto-generate on first call)."""
        if not self.device_id:
            import secrets
            self.device_id = secrets.token_hex(16)
            logger.debug(f"生成 device_id: {self.device_id}")
        return self.device_id
