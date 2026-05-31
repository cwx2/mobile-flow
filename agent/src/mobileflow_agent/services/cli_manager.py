"""
CLI Manager

Pure ACP architecture. Uses ProviderRegistry to manage all CLI providers.
Provider lifecycle is split into two layers:
  - _ensure_provider: initialize ACP connection only (no session)
  - Callers decide when to create/load/list sessions
"""

from __future__ import annotations

import asyncio
import time
from typing import AsyncGenerator, Callable, Optional

from loguru import logger

from mobileflow_protocol.models import CLIInfo, StreamChunk, StreamChunkType

from ..providers.base import AgentEvent, AgentEventType, AgentProvider, ProviderLifecycleState
from ..providers.registry import ProviderRegistry, ACP_REGISTRY
from ..core.config import AgentConfig
from ..core.errors import AuthRequiredError, is_auth_error
from ..core.events import Events
from ..utils.path import win_to_wsl
from ..utils.i18n import t


class CLIManager:
    """CLI manager: manages ACP CLI providers via ProviderRegistry"""

    def __init__(self, config: AgentConfig, event_bus=None):
        self.config = config
        self.event_bus = event_bus
        self.registry = ProviderRegistry(
            event_bus=event_bus,
            process_terminate_timeout=config.lifecycle.process_terminate_timeout,
        )

        from .session_store import SessionStore
        self.session_store = SessionStore(
            config.ensure_data_dir(),
            max_history_messages=config.session_resume.max_history_messages,
        )

        # Active provider sessions
        self._sessions: dict[tuple[str, str], AgentProvider] = {}
        self._session_ids: dict[tuple[str, str], str] = {}

        # Singleton initialization tasks per (client_id, cli_name).
        # When _ensure_provider is called concurrently, only one init runs.
        self._provider_tasks: dict[tuple[str, str], asyncio.Task] = {}

        # Cached capabilities per cli_name. Populated when a provider
        # initializes successfully or before shutdown, so non-active CLIs
        # still report their last-known capabilities in cli.list.result.
        # In-memory only — lost on Agent restart. Repopulated when the
        # user switches to a CLI (triggering initialize).
        self._capabilities_cache: dict[str, dict] = {}

        # Background tasks per client_id (recovery monitors, progressive status).
        # Tracked so they can be cancelled on client disconnect.
        self._background_tasks: dict[str, list[asyncio.Task]] = {}

        # Session operation sequencer per key.
        # Serializes send_message, read_history, new_session, switch_session
        # on the same (client_id, cli_name) key.
        self._session_locks: dict[tuple[str, str], asyncio.Lock] = {}

        # WebSocket broadcast callback, set by WebSocketServer after construction.
        # Used by _push_status to send cli.status messages to connected clients.
        self._ws_broadcast: Callable | None = None

        # History cache for pagination — stores full history from ACP session/load
        # so the App can request pages without re-loading from ACP each time.
        # Key: (client_id, cli_name), Value: list of raw history dicts.
        # Cleared on session switch, new session, or CLI switch.
        # Capped at _MAX_HISTORY_CACHE_ENTRIES to prevent unbounded memory growth.
        self._history_cache: dict[tuple[str, str], list[dict]] = {}
        self._MAX_HISTORY_CACHE_ENTRIES = 10

    async def detect_all(self):
        """Detect all available CLIs"""
        await self.registry.detect_all()

    def _check_auth_error(self, e: Exception, cli_name: str, operation: str) -> None:
        """Check if an exception is an ACP auth error and raise AuthRequiredError.

        Called in except blocks to centralize auth error detection.
        If the error is NOT auth-related, does nothing (caller should re-raise).

        Args:
            e: The caught exception.
            cli_name: CLI adapter name (for error context).
            operation: Name of the operation that failed (for logging).

        Raises:
            AuthRequiredError: If the exception indicates auth is required.
        """
        if is_auth_error(e):
            logger.info(f"{operation} 需要认证: cli={cli_name}")
            raise AuthRequiredError(cli_name=cli_name, detail=str(e))

    def _cleanup_previous_empty_session(self, cli_name: str, cwd: str) -> None:
        """Remove the most recent empty session for a CLI + cwd combination.

        Called after new_session succeeds to prevent empty sessions from
        accumulating on every reconnect. Only removes sessions with no
        preview text (never had a user message). Sessions with history
        are preserved.

        Also checks WSL path format for backward compatibility with
        sessions stored before the path normalization fix.

        Args:
            cli_name: CLI adapter name.
            cwd: Normalized working directory path.
        """
        sessions = self.session_store.list_by_cwd(cwd, cli_name)
        # Backward compat: also check WSL path
        if not sessions:
            wsl_cwd = win_to_wsl(cwd)
            if wsl_cwd != cwd:
                sessions = self.session_store.list_by_cwd(wsl_cwd, cli_name)
        if not sessions:
            return
        # Only remove the most recent empty session (no preview = never used)
        latest = sessions[0]
        if not latest.get("preview", ""):
            self.session_store.remove(latest["id"])
            logger.debug(f"清理空会话: {latest['id'][:16]}... (cli={cli_name})")

    @staticmethod
    def _normalize_cwd(path: str, provider: AgentProvider) -> str:
        """Normalize a working directory path for session storage.

        Only converts Windows paths to WSL format when the CLI actually
        runs inside WSL. Native Windows CLIs keep their original paths
        so the App displays them correctly (e.g. ``E:\\workData`` instead
        of ``/mnt/e/workData``).

        Args:
            path: Working directory path (Windows or Unix format).
            provider: The ACP provider, used to check execution environment.

        Returns:
            Path in the format matching the provider's execution environment.
        """
        if provider.execution_env == "wsl":
            return win_to_wsl(path)
        return path

    def list_adapters(self) -> list[CLIInfo]:
        """List all CLIs with install info and capabilities from initialized providers."""
        result = []
        for info in self.registry.list_all():
            cli_name = info["name"]
            caps = self._get_cli_capabilities(cli_name)
            result.append(CLIInfo(
                name=cli_name,
                display_name=info["display_name"],
                installed=info["installed"],
                version=info.get("version"),
                install_hint=info.get("install_hint"),
                install_npm=info.get("install_npm"),
                is_custom=info.get("is_custom", False),
                can_install=info.get("can_install", False),
                **caps,
            ))
        return result

    def _get_cli_capabilities(self, cli_name: str) -> dict:
        """Extract capability dict from an initialized provider, or return cached/defaults.

        Checks running providers first for live data, then falls back to
        the capabilities cache (populated during previous initializations).
        Returns empty dict only if the CLI has never been initialized.
        """
        for key, provider in self._sessions.items():
            if key[1] == cli_name and provider.is_running:
                pc = provider.capabilities
                if pc:
                    caps = pc.to_capability_dict()
                    # Update cache with latest live data
                    self._capabilities_cache[cli_name] = caps
                    return caps
        # Fall back to cached capabilities from a previous session
        return self._capabilities_cache.get(cli_name, {})

    def cache_capabilities(self, cli_name: str, provider: AgentProvider) -> None:
        """Cache a provider's capabilities for later retrieval.

        Called before shutting down a provider so its capabilities remain
        available in cli.list.result even after the ACP process exits.
        Only caches if the provider has valid capabilities.

        Args:
            cli_name: CLI adapter name (e.g. "codex", "kiro").
            provider: The provider whose capabilities to cache.
        """
        pc = provider.capabilities
        if pc:
            self._capabilities_cache[cli_name] = pc.to_capability_dict()

    # ── Provider lifecycle ──

    async def _ensure_provider(
        self, client_id: str, cli_name: str, work_dir: Optional[str] = None,
    ) -> Optional[AgentProvider]:
        """Ensure provider is initialized (ACP process started + connected).

        Uses singleton pattern: concurrent callers share one init task via
        ``_provider_tasks``. Does NOT create or load any session — callers
        decide when to create/load/list sessions.

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name (e.g. "codex", "claude-code").
            work_dir: Working directory override. Defaults to config.work_dir.

        Returns:
            Initialized AgentProvider, or None if CLI is unavailable.
        """
        key = (client_id, cli_name)

        # Already have a running provider
        if key in self._sessions:
            provider = self._sessions[key]
            if provider.is_running:
                logger.debug(f"_ensure_provider: 复用已有 provider: {cli_name}")
                return provider
            else:
                # Provider stopped — clean up and re-init
                logger.warning(f"_ensure_provider: provider 已停止，重新初始化: {cli_name}")
                self._sessions.pop(key, None)
                self._session_ids.pop(key, None)

        # Singleton: if init in progress, wait for it
        if key in self._provider_tasks:
            task = self._provider_tasks[key]
            if not task.done():
                logger.debug(f"_ensure_provider: 等待正在进行的初始化: {cli_name}")
                return await task
            # Task done but provider not in _sessions — it failed last time, retry

        # Start new initialization
        logger.debug(f"_ensure_provider: 启动新的初始化: {cli_name}")
        task = asyncio.create_task(self._init_provider(client_id, cli_name, work_dir))
        self._provider_tasks[key] = task
        return await task

    async def _init_provider(
        self, client_id: str, cli_name: str, work_dir: Optional[str] = None,
    ) -> Optional[AgentProvider]:
        """Core provider lifecycle: env_check → initialize → wire auth → ready/failed.

        Three phases with status push at each transition:
        1. checking_env: validate CLI binary exists (env_check).
        2. starting: spawn ACP process and complete initialize handshake (with timeout).
        3. ready: wire auth resolver callback, attempt silent auth, push ready status.

        The auth resolver uses asyncio.Event to bridge the gap between
        ``_with_auth_retry()`` (which awaits credentials) and ``handle_auth_submit()``
        (which receives credentials from the frontend). This uses the
        callback injection pattern for separation of concerns.

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name (e.g. "codex", "claude-code").
            work_dir: Working directory override. Defaults to config.work_dir.

        Returns:
            Initialized AgentProvider, or None if any phase fails.
        """
        key = (client_id, cli_name)
        provider = self.registry.get_provider(cli_name)
        if not provider:
            msg = t("backend.noCliInstalled") if not cli_name else t("backend.cliNotFound", name=cli_name)
            logger.warning(f"_init_provider: CLI 不存在: {cli_name!r}")
            await self._push_status(key, "failed", msg, error=f"CLI not found: {cli_name!r}")
            return None

        target_dir = work_dir or self.config.work_dir

        # Sync execution_env from registry before any phase.
        # The registry may have overridden the env at runtime
        # (e.g. WSL proxy failed → fell back to native).
        # This is a secondary safeguard — the primary path is
        # set_execution_env() which also updates provider.execution_env
        # directly. This sync catches edge cases where the provider
        # object was recreated after the override was set.
        current_env = self.registry.get_execution_env(cli_name)
        if current_env and current_env != provider.execution_env:
            logger.info(f"执行环境已同步: {cli_name}, {provider.execution_env} → {current_env}")
            provider.execution_env = current_env

        # Phase 1: checking_env
        provider._lifecycle_state = ProviderLifecycleState.CHECKING_ENV
        await self._push_status(key, "checking_env", t("backend.checkingEnv"))
        ok, err = await provider.env_check()
        if not ok:
            provider._lifecycle_state = ProviderLifecycleState.FAILED
            provider._error_message = err
            await self._push_status(key, "failed", err, error=err)
            return None

        # Phase 2: starting (with timeout)
        await self._push_status(key, "starting", t("backend.startingAgent"))
        timeout = self.config.lifecycle.init_timeout_wsl if provider.execution_env == "wsl" else self.config.lifecycle.init_timeout_native

        # Start progressive status messages in background
        progressive_task = self._track_bg_task(client_id, self._progressive_status(key, provider))

        try:
            await asyncio.wait_for(provider.initialize(target_dir), timeout=timeout)
        except (asyncio.TimeoutError, Exception) as e:
            progressive_task.cancel()
            is_timeout = isinstance(e, asyncio.TimeoutError)
            error_detail = f"timeout_at=starting, waited={timeout}s" if is_timeout else str(e)
            logger.warning(f"_init_provider: initialize 失败: cli={cli_name}, error={error_detail}")

            # Determine if this CLI likely needs authentication.
            # Check static registry config since capabilities aren't available yet.
            from ..providers.registry import ACP_REGISTRY
            cli_config = ACP_REGISTRY.get(cli_name, {})
            has_auth = bool(cli_config.get("auth_command"))

            if is_timeout or has_auth:
                # Timeout or CLI has auth_command → likely needs authentication.
                # Push auth_required so user sees the login form.
                provider._lifecycle_state = ProviderLifecycleState.AUTH_REQUIRED
                self._sessions[key] = provider
                await self._push_status(key, "auth_required", t("backend.authRequired"))
                logger.info(f"_init_provider: 引导用户认证: {cli_name}")
                self._track_bg_task(client_id, self._track_recovery(key, provider, target_dir))
                return provider
            else:
                # No auth_command and not timeout → genuine startup failure
                provider._lifecycle_state = ProviderLifecycleState.FAILED
                msg = t("backend.startupFailed", error=str(e))
                provider._error_message = msg
                await self._push_status(key, "failed", msg, error=error_detail)
                return None

        progressive_task.cancel()

        # Phase 3: verify auth by attempting new_session
        # initialize() succeeding only means the ACP connection is established,
        # not that the user is authenticated. Some CLIs (e.g. Gemini) accept
        # the connection but reject operations without valid credentials.
        # We try new_session here to detect auth issues early — if it succeeds,
        # we keep the session for later use; if it fails with auth error, we
        # push auth_required immediately instead of letting the user discover
        # it when they try to send a message.
        self._sessions[key] = provider

        # Silent auth: check if env vars are already set (best-effort)
        silent_ok = False
        if hasattr(provider, 'try_silent_auth'):
            try:
                silent_ok = await provider.try_silent_auth()
            except Exception as e:
                logger.debug(f"静默认证出错（可忽略）: {e}")

        caps = provider.capabilities
        has_auth_methods = caps and caps.auth_methods and len(caps.auth_methods) > 0

        # Cache capabilities after initialize so non-active CLIs still
        # report them in cli.list. Capabilities are determined during the
        # ACP initialize handshake and don't change after that.
        self.cache_capabilities(cli_name, provider)

        if not silent_ok and has_auth_methods:
            # CLI declares auth methods and silent auth failed — likely needs auth.
            # Push auth_required directly to avoid ready→auth_required flicker.
            provider._lifecycle_state = ProviderLifecycleState.AUTH_REQUIRED
            await self._push_status(key, "auth_required", t("backend.authRequired"))
            logger.info(f"_init_provider: 静默认证失败，需要用户认证: {cli_name}")
        else:
            # Phase 3: create a session to verify auth and get config/mode.
            # Always uses new_session (not load_session) because config_options
            # and mode are only returned by new_session. To prevent empty
            # sessions from accumulating, we remove the previous session for
            # the same CLI + cwd if it has no history (empty preview).
            target_cwd = self._normalize_cwd(target_dir, provider)
            try:
                session_id = await asyncio.wait_for(
                    provider.new_session(target_dir), timeout=self.config.timeouts.new_session_verify,
                )
                # Clean up the previous empty session for this CLI + cwd
                # to prevent accumulation on every reconnect.
                self._cleanup_previous_empty_session(cli_name, target_cwd)

                self._session_ids[key] = session_id
                self.session_store.add(session_id, cli_name, target_cwd)
                await self._push_status(key, "ready", t("backend.agentReady"))
                await self._push_pending_config(key, provider)
                logger.info(f"_init_provider: 就绪，会话已创建: {cli_name}")
            except Exception as e:
                if is_auth_error(e):
                    provider._lifecycle_state = ProviderLifecycleState.AUTH_REQUIRED
                    await self._push_status(key, "auth_required", t("backend.authRequired"))
                    logger.info(f"_init_provider: new_session 需要认证: {cli_name}")
                    logger.info(f"_init_provider: provider 就绪: {cli_name}")
                    return provider
                else:
                    await self._push_status(key, "ready", t("backend.agentReady"))
                    logger.warning(f"_init_provider: new_session 出错但非认证问题: {cli_name}, error={e}")

        logger.info(f"_init_provider: provider 就绪: {cli_name}")
        return provider

    def _track_bg_task(self, client_id: str, coro) -> asyncio.Task:
        """Create and track a background task for a client.

        Tracked tasks are cancelled in cleanup_sessions() when the client
        disconnects, preventing zombie background loops.
        Unhandled exceptions are logged to prevent silent failures.

        Args:
            client_id: Owner client identifier.
            coro: Coroutine to wrap in a task.

        Returns:
            The created asyncio.Task.
        """
        task = asyncio.create_task(coro)
        task.add_done_callback(self._bg_task_done_callback)
        self._background_tasks.setdefault(client_id, []).append(task)
        return task

    @staticmethod
    def _bg_task_done_callback(task: asyncio.Task) -> None:
        """Log unhandled exceptions from background tasks."""
        if task.cancelled():
            return
        exc = task.exception()
        if exc:
            logger.error(f"后台任务异常: {type(exc).__name__}: {exc}")

    async def _progressive_status(self, key: tuple[str, str], provider: AgentProvider):
        """Upgrade status messages at 10s and 20s during starting phase."""
        try:
            await asyncio.sleep(10)
            if provider._lifecycle_state == ProviderLifecycleState.STARTING:
                await self._push_status(key, "starting", t(self.config.lifecycle.progressive_msg_10s))
            await asyncio.sleep(10)
            if provider._lifecycle_state == ProviderLifecycleState.STARTING:
                await self._push_status(key, "starting", t(self.config.lifecycle.progressive_msg_20s))
        except asyncio.CancelledError:
            pass

    async def _track_recovery(self, key: tuple[str, str], provider: AgentProvider, work_dir: str):
        """After timeout, keep monitoring. If env becomes ready, auto-recover.

        This task is created via _track_bg_task() which stores it in
        _background_tasks. On client disconnect, cleanup_sessions() cancels
        all tracked tasks — asyncio.sleep raises CancelledError, causing
        a clean exit without manual alive checks.
        """
        try:
            lc = self.config.lifecycle
            start = time.monotonic()
            while time.monotonic() - start < lc.recovery_max_duration:
                await asyncio.sleep(lc.recovery_poll_interval)
                ok, _ = await provider.env_check()
                if ok:
                    try:
                        await provider.initialize(work_dir)
                        self._sessions[key] = provider
                        elapsed = time.monotonic() - start
                        logger.info(f"超时后恢复成功: cli={key[1]}, 恢复耗时={elapsed:.1f}s")
                        await self._push_status(key, "ready", t("backend.agentReady"))
                        return
                    except Exception as e:
                        logger.debug(f"超时后恢复尝试失败: {e}")
            logger.warning(f"超时后恢复失败，放弃: cli={key[1]}")
        except asyncio.CancelledError:
            pass

    async def _push_status(self, key: tuple[str, str], state: str, message: str, error: str | None = None):
        """Broadcast cli.status message to connected App clients via WebSocket.

        Automatically includes capabilities when state is "ready" and
        auth_methods when state is "auth_required".

        Args:
            key: Tuple of (client_id, cli_name).
            state: Lifecycle state string (checking_env, starting, ready, failed, auth_required).
            message: User-facing status message (already translated via t()).
            error: Optional error detail string for debugging.
        """
        client_id, cli_name = key
        logger.info(f"CLI 状态变更: cli={cli_name}, state={state}, message={message}")
        if self._ws_broadcast:
            from mobileflow_protocol.envelope import Message
            from mobileflow_protocol.payloads.cli import CliStatusPayload
            from mobileflow_protocol.types import MessageType

            # Build optional fields incrementally
            capabilities = None
            auth_methods = None
            auth_type = None
            device_code_url = None
            device_code = None

            # Include capabilities when provider is ready
            if state == "ready":
                capabilities = self._get_cli_capabilities(cli_name)
            # Include auth methods when authentication is required
            if state == "auth_required":
                # Try to get auth_methods from provider capabilities (normal path)
                auth_methods_found = False
                for key2, provider in self._sessions.items():
                    if key2[1] == cli_name and provider.capabilities:
                        auth_methods = provider.capabilities.auth_methods
                        auth_methods_found = True
                        break

                # Fallback: build auth_methods from static ACP_REGISTRY config
                if not auth_methods_found:
                    cli_config = ACP_REGISTRY.get(cli_name, {})
                    auth_cmd = cli_config.get("auth_command", [])
                    if auth_cmd:
                        auth_methods = [
                            {"id": "terminal", "type": "terminal",
                             "name": t("backend.browserLogin"),
                             "description": t("backend.browserLoginDesc"),
                             "args": auth_cmd[1:]},
                        ]

                # Always check provider for device code info (set by _on_device_code
                # callback during terminal auth flow, independent of capabilities)
                for key2, prov in self._sessions.items():
                    if key2[1] == cli_name:
                        auth_type = getattr(prov, '_auth_type', None)
                        device_code_url = getattr(prov, '_device_code_url', None)
                        device_code = getattr(prov, '_device_code', None)
                        break

            status_payload = CliStatusPayload(
                cli=cli_name,
                state=state,
                message=message,
                error=error,
                capabilities=capabilities,
                auth_methods=auth_methods,
                auth_type=auth_type,
                device_code_url=device_code_url,
                device_code=device_code,
            )
            await self._ws_broadcast(client_id, Message.from_typed(
                type=MessageType.CLI_STATUS,
                payload=status_payload,
            ))

    async def _push_pending_config(self, key: tuple[str, str], provider: AgentProvider):
        """Push pending configOptions and initial mode from new_session response.

        ACP new_session returns configOptions (model, mode, thought_level, etc.)
        but these can't go through the event collector (cleared before each prompt).
        This method consumes the pending data via the provider's public API and
        sends it directly to the App as CHAT_STREAM chunks.

        Args:
            key: Tuple of (client_id, cli_name).
            provider: The provider that just created a session.
        """
        pending_opts, pending_mode = provider.consume_pending_config()

        if pending_opts:
            await self._push_config_chunk(key[0], pending_opts)
            logger.info(f"推送 configOptions 到 App: {len(pending_opts)} 项")

        if pending_mode:
            await self._push_stream_chunk(key[0], StreamChunkType.MODE_CHANGE, pending_mode)
            logger.info(f"推送初始模式到 App: {pending_mode}")

    async def _push_config_chunk(self, client_id: str, options: list[dict]):
        """Push a CONFIG_UPDATE stream chunk to the App.

        Shared by _push_pending_config (new_session) and set_config_option
        (user-triggered config change). Avoids duplicating the chunk
        construction + broadcast logic.

        Args:
            client_id: Target WebSocket client.
            options: Serialized config option dicts.
        """
        import json
        await self._push_stream_chunk(
            client_id, StreamChunkType.CONFIG_UPDATE,
            json.dumps(options, ensure_ascii=False, default=str),
        )

    async def _push_stream_chunk(self, client_id: str, chunk_type: StreamChunkType, content: str):
        """Send a single StreamChunk to the App outside of the prompt flow.

        Used for state-change notifications (config updates, mode changes)
        that originate from session creation or user actions, not from the
        AI response stream.

        Args:
            client_id: Target WebSocket client.
            chunk_type: StreamChunkType enum value.
            content: Chunk content string.
        """
        if not self._ws_broadcast:
            return
        from mobileflow_protocol.envelope import Message
        from mobileflow_protocol.payloads.chat import ChatStreamPayload
        from mobileflow_protocol.types import MessageType
        chunk = StreamChunk(type=chunk_type, content=content)
        await self._ws_broadcast(client_id, Message.from_typed(
            type=MessageType.CHAT_STREAM,
            payload=ChatStreamPayload(chunk=chunk.model_dump()),
        ))

    async def _with_session_lock(self, key: tuple[str, str], coro):
        """Serialize session operations per key to prevent race conditions.

        Ensures that concurrent calls to send_message, read_history,
        new_session, switch_session on the same (client_id, cli_name)
        key are executed sequentially.

        Args:
            key: Tuple of (client_id, cli_name).
            coro: Awaitable to execute under the lock.

        Returns:
            The return value of the awaitable.
        """
        # Use setdefault for atomic lock creation — prevents duplicate
        # locks if two coroutines reach this point in the same event loop tick.
        lock = self._session_locks.setdefault(key, asyncio.Lock())
        async with lock:
            return await coro

    async def handle_retry(self, client_id: str, cli_name: str):
        """Handle cli.retry: cleanup old provider and re-run full initialization.

        Called when the user taps "retry" on the frontend after a failure.
        Shuts down the old provider, clears all cached state, and starts fresh.

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name.

        Returns:
            Newly initialized AgentProvider, or None if init fails.
        """
        key = (client_id, cli_name)
        old = self._sessions.pop(key, None)
        self._session_ids.pop(key, None)
        self._provider_tasks.pop(key, None)
        if old:
            try:
                await old.shutdown()
            except Exception as e:
                logger.warning(f"重试清理旧 provider 出错: {e}")
        logger.info(f"CLI 重试初始化: {cli_name}")
        return await self._ensure_provider(client_id, cli_name)

    async def handle_auth_submit(self, client_id: str, cli_name: str, method_id: str, data: dict):
        """Handle auth.submit from frontend: dispatch based on method type.

        The frontend sends the user's chosen auth method. This handler
        dispatches to the appropriate flow:
        - env_var: set env vars + call authenticate
        - terminal: run CLI auth command (device code flow)
        - agent/empty: check registry for auth_command → device code,
          otherwise call authenticate

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name.
            method_id: Auth method identifier from capabilities.
            data: Credentials dict (env_var: var→value map; others: empty).
        """
        key = (client_id, cli_name)
        provider = self._sessions.get(key)
        if not provider:
            logger.warning(f"认证提交但 provider 不存在: {cli_name}")
            await self._push_status(key, "failed", t("backend.agentNotInitialized"))
            return

        # Find the method definition from capabilities
        caps = provider.capabilities
        methods = caps.auth_methods if caps else []
        method = next((m for m in methods if m.get("id") == method_id), None)
        method_type = method.get("type", "") if method else ""

        logger.info(f"认证提交: cli={cli_name}, method={method_id}, type={method_type!r}")

        # Dispatch based on method type
        if method_type == "env_var":
            await self._handle_env_var_auth(key, cli_name, provider, method_id, data)
        elif method_type == "terminal":
            # Terminal type: use args from the method definition
            args = method.get("args", []) if method else []
            await self._handle_device_code_auth(key, cli_name, provider, args)
        else:
            # Agent type (type="" or type="agent"): check registry for auth_command
            registry_config = self.registry._providers.get(cli_name)
            cli_info = None
            for name, info in ACP_REGISTRY.items():
                if name == cli_name:
                    cli_info = info
                    break
            auth_cmd = cli_info.get("auth_command", []) if cli_info else []

            if auth_cmd:
                # Registry has auth_command → run device code flow
                logger.info(f"使用 registry auth_command: {auth_cmd}")
                await self._handle_device_code_auth(key, cli_name, provider, auth_cmd[1:], command_override=auth_cmd[0])
            else:
                # No auth_command → call authenticate directly (may open browser on desktop)
                await self._handle_agent_auth(key, cli_name, provider, method_id)

    async def _handle_env_var_auth(
        self, key: tuple[str, str], cli_name: str,
        provider: AgentProvider, method_id: str, data: dict,
    ):
        """Handle env_var auth: set env vars, call authenticate, signal resolver."""
        await self._push_status(key, "starting", t("backend.verifyingApiKey"))
        try:
            if data:
                import os
                for var_name, var_value in data.items():
                    if var_name and var_value:
                        os.environ[var_name] = str(var_value)
                        logger.debug(f"设置环境变量: {var_name}={'*' * min(4, len(str(var_value)))}")

            success = await provider.authenticate(method_id, data)
            self._signal_auth_outcome(provider, key, cli_name, method_id, success)
        except Exception as e:
            logger.error(f"env_var 认证出错: {cli_name}, error={e}")
            self._signal_auth_outcome(provider, key, cli_name, method_id, False, error_msg=str(e))

    async def _handle_device_code_auth(
        self, key: tuple[str, str], cli_name: str,
        provider: AgentProvider, args: list[str],
        command_override: str | None = None,
    ):
        """Handle device code auth: run CLI auth command, push URL+code to frontend.

        Two sources of command+args:
        1. Registry auth_command (e.g. ["codex", "login", "--device-auth"]):
           command_override="codex", args=["login", "--device-auth"]
        2. ACP terminal method (e.g. args=["--setup"]):
           command_override=None, uses provider._command

        Args:
            key: (client_id, cli_name) tuple.
            cli_name: CLI adapter name.
            provider: The ACP provider instance.
            args: Command arguments for the auth command.
            command_override: Full path to auth CLI binary. If None, uses provider._command.
        """
        from .terminal_auth_helper import run_terminal_auth_flow

        effective_cmd = command_override or getattr(provider, '_command', '')
        if not effective_cmd or not args:
            logger.warning(f"device code 认证缺少命令或参数: cli={cli_name}")
            await self._push_status(key, "auth_required", t("backend.cannotStartBrowserLogin"))
            return

        method = {"args": args}
        success = await run_terminal_auth_flow(
            key=key, cli_name=cli_name, provider=provider,
            method=method, config=self.config, push_status=self._push_status,
            command_override=command_override,
        )
        self._signal_auth_outcome(provider, key, cli_name, "device_code", success)

    async def _handle_agent_auth(
        self, key: tuple[str, str], cli_name: str,
        provider: AgentProvider, method_id: str,
    ):
        """Handle agent auth: call authenticate directly (may open desktop browser)."""
        await self._push_status(key, "starting", t("backend.processingAuth"))
        try:
            timeout = self.config.lifecycle.auth_agent_timeout
            success = await asyncio.wait_for(
                provider.authenticate(method_id, {}), timeout=timeout,
            )
            self._signal_auth_outcome(provider, key, cli_name, method_id, success)
        except asyncio.TimeoutError:
            logger.warning(f"agent 认证超时: {cli_name}, timeout={timeout}s")
            self._signal_auth_outcome(provider, key, cli_name, method_id, False, error_msg=t("backend.authTimeout", timeout=str(timeout)))
        except Exception as e:
            logger.error(f"agent 认证出错: {cli_name}, error={e}")
            self._signal_auth_outcome(provider, key, cli_name, method_id, False, error_msg=str(e))

    def _signal_auth_outcome(
        self, provider: AgentProvider, key: tuple[str, str],
        cli_name: str, method_id: str, success: bool, error_msg: str = "",
    ) -> None:
        """Signal authentication outcome: update provider state and push status.

        Handles both success and failure cases. On success, transitions provider
        to READY and pushes "ready" status. On failure, transitions to
        AUTH_REQUIRED and pushes the error message.

        Args:
            provider: The ACP provider instance.
            key: (client_id, cli_name) tuple.
            cli_name: CLI adapter name (for logging).
            method_id: Auth method identifier (for logging).
            success: Whether authentication succeeded.
            error_msg: Error message (used only on failure).
        """
        if success:
            provider._lifecycle_state = ProviderLifecycleState.READY
            logger.info(f"认证成功: {cli_name}, method={method_id}")
            asyncio.create_task(
                self._push_status(key, "ready", t("backend.authSuccess"))
            )
        else:
            provider._lifecycle_state = ProviderLifecycleState.AUTH_REQUIRED
            msg = t("backend.authError", error=error_msg) if error_msg else t("backend.authFailed")
            logger.warning(f"认证失败: {cli_name}, method={method_id}, error={error_msg}")
            asyncio.create_task(
                self._push_status(key, "auth_required", msg)
            )

    async def set_mode(self, client_id: str, cli_name: str, mode_id: str):
        """Set session mode via ACP set_session_mode."""
        key = (client_id, cli_name)
        provider = self._sessions.get(key)
        session_id = self._session_ids.get(key, "")
        if not provider or not session_id:
            logger.warning(f"set_mode: provider 或 session 不存在: {cli_name}")
            return
        logger.info(f"切换模式: cli={cli_name}, mode={mode_id}")
        await provider.set_mode(session_id, mode_id)

    async def set_config_option(self, client_id: str, cli_name: str, config_id: str, value: str | bool):
        """Set config option via ACP set_config_option.

        The ACP response returns the full updated config list. We push it
        directly to the App as a CHAT_STREAM chunk (same path as
        _push_pending_config) so the UI refreshes immediately.
        """
        key = (client_id, cli_name)
        provider = self._sessions.get(key)
        session_id = self._session_ids.get(key, "")
        if not provider or not session_id:
            logger.warning(f"set_config_option: provider 或 session 不存在: {cli_name}")
            return
        logger.info(f"设置配置: cli={cli_name}, config={config_id}, value={value}")
        updated_opts = await provider.set_config_option(session_id, config_id, value)
        # Push updated config list to App
        if updated_opts:
            await self._push_config_chunk(client_id, updated_opts)

    async def on_token_changed(self, client_id: str, cli_name: str):
        """Handle external auth token change (e.g. account switch).

        If there's an active session, defers restart until session ends.
        If no active session, restarts the provider immediately to pick up
        the new credentials.

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name.
        """
        key = (client_id, cli_name)
        provider = self._sessions.get(key)
        session_id = self._session_ids.get(key)

        if provider and session_id:
            # Active session — defer restart until session ends
            logger.info(f"Token 变更，等待会话结束后重建: {cli_name}")
            if hasattr(provider, '_pending_token_refresh'):
                provider._pending_token_refresh = True
        elif provider:
            # No active session — restart immediately
            logger.info(f"Token 变更，立即重建: {cli_name}")
            await self._push_status(key, "starting", t("backend.reconnecting"))
            await provider.shutdown()
            self._sessions.pop(key, None)
            self._provider_tasks.pop(key, None)
            await self._ensure_provider(client_id, cli_name)

    async def _ensure_session(
        self, client_id: str, cli_name: str, work_dir: Optional[str] = None,
    ) -> Optional[AgentProvider]:
        """Ensure provider has an active session.

        If no session exists, creates a new one via ``provider.new_session()``.
        On ACP auth error (-32000), raises AuthRequiredError for the
        interceptor chain to handle.

        Does NOT restore old sessions — that's ``read_history()``'s job
        (triggered on app startup).

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name.
            work_dir: Working directory override.

        Returns:
            Provider with active session, or None if provider init fails.

        Raises:
            AuthRequiredError: If new_session fails with ACP -32000.
        """
        provider = await self._ensure_provider(client_id, cli_name, work_dir)
        if not provider:
            return None

        session_key = (client_id, cli_name)

        # Already have a session
        if session_key in self._session_ids:
            logger.debug(f"_ensure_session: 已有会话: {self._session_ids[session_key][:16]}...")
            return provider

        # Create new session
        target_dir = work_dir or self.config.work_dir
        logger.debug(f"_ensure_session: 创建新会话: {cli_name}")
        try:
            session_id = await provider.new_session(target_dir)
        except Exception as e:
            self._check_auth_error(e, cli_name, "new_session")
            raise

        self._session_ids[session_key] = session_id
        store_cwd = self._normalize_cwd(target_dir, provider)
        self.session_store.add(session_id, cli_name, store_cwd)
        await self._push_pending_config(session_key, provider)
        logger.info(f"_ensure_session: 新会话创建: {session_id[:16]}...")
        return provider

    # ── Message sending ──

    async def send_message(
        self,
        client_id: str,
        cli_name: str,
        message: str,
        context: Optional[dict] = None,
        work_dir: Optional[str] = None,
        images: Optional[list[dict]] = None,
        audio_files: Optional[list[dict]] = None,
        resources: Optional[list[dict]] = None,
    ) -> AsyncGenerator[StreamChunk, None]:
        """Send a message to the AI agent with auto-recovery and retry.

        Ensures session exists, checks provider health, sends prompt, and
        streams back response chunks. On connection failure, retries up to
        3 times with progressive backoff (1s, 2s, 3s).

        For resume-only CLIs (supports resume but NOT load), persists the
        user message and assistant response to local history after each
        successful prompt. This enables serving history after reconnection
        when session/resume succeeds.

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name.
            message: User message text.
            context: Optional context dict with active_file, selected_lines.
            work_dir: Working directory override.
            images: Optional image attachments for multimodal input.
            audio_files: Optional audio attachments for multimodal input.
            resources: Optional resource/resource_link attachments.

        Yields:
            StreamChunk objects (TEXT, THINKING, DIFF, TOOL_USE, ERROR, etc.).
        """
        import asyncio

        max_retries = 3
        for attempt in range(max_retries + 1):
            provider = await self._ensure_session(client_id, cli_name, work_dir)
            if not provider:
                yield StreamChunk(type=StreamChunkType.ERROR, content=t("backend.cliUnavailable", name=cli_name))
                return

            # Pre-prompt health check
            if hasattr(provider, 'is_healthy') and not provider.is_healthy:
                logger.info(f"🔄 ACP 连接不健康，恢复中 (attempt {attempt}/{max_retries})...")
                recovered = await self._recover_provider(client_id, cli_name, work_dir)
                if not recovered:
                    yield StreamChunk(type=StreamChunkType.ERROR, content=t("backend.agentConnectionFailed"))
                    return
                provider = self._sessions.get((client_id, cli_name))
                if not provider:
                    yield StreamChunk(type=StreamChunkType.ERROR, content=t("backend.providerLostAfterRecovery"))
                    return

            session_key = (client_id, cli_name)
            session_id = self._session_ids.get(session_key, "")
            full_message = self._build_message(message, context)

            if session_id and attempt == 0:
                self.session_store.update_preview(session_id, message)

            got_content = False
            # Collect assistant text for local history persistence (resume-only CLIs)
            assistant_text_parts: list[str] = []
            try:
                async for event in provider.prompt(session_id, full_message, images=images, audio_files=audio_files, resources=resources):
                    # Intercept COMMANDS_AVAILABLE events — these are not stream
                    # chunks but out-of-band notifications for the slash command menu.
                    if event.type == AgentEventType.COMMANDS_AVAILABLE:
                        if self.event_bus:
                            await self.event_bus.emit(Events.CLI_COMMANDS_AVAILABLE, {
                                "cli_name": cli_name,
                                "commands": event.data.get("commands", []),
                            })
                        continue
                    chunk = self._event_to_chunk(event)
                    if chunk:
                        if chunk.type != StreamChunkType.ERROR:
                            got_content = True
                        # Accumulate assistant text for history persistence
                        if chunk.type == StreamChunkType.TEXT:
                            assistant_text_parts.append(chunk.content)
                        yield chunk
            except Exception as e:
                # Auth errors during prompt propagate as AuthRequiredError
                # for the interceptor chain to handle
                self._check_auth_error(e, cli_name, "prompt")
                logger.error(f"Provider 通信出错 (attempt {attempt}): {e}")
                yield StreamChunk(type=StreamChunkType.ERROR, content=t("backend.communicationError", error=str(e)))

            # Post-prompt: check if recovery + retry is needed
            needs_retry = hasattr(provider, '_needs_recovery') and provider._needs_recovery
            if needs_retry and not got_content and attempt < max_retries:
                delay = attempt + 1
                logger.warning(f"⚠️ ACP session 异常，{delay}秒后重试 ({attempt + 1}/{max_retries})...")
                yield StreamChunk(type=StreamChunkType.STATUS, content=t("backend.retrying", attempt=str(attempt + 1), max=str(max_retries)))
                await asyncio.sleep(delay)
                continue

            if needs_retry and attempt >= max_retries:
                logger.error(f"❌ ACP 重试 {max_retries} 次仍失败")
                yield StreamChunk(type=StreamChunkType.ERROR, content=t("backend.retryFailed"))
                return

            # Post-prompt: persist messages for resume-only CLIs.
            # Only persist when we got actual content (successful prompt).
            if got_content and session_id and self._is_resume_only_cli(client_id, cli_name):
                self._persist_prompt_messages(
                    session_id, message, "".join(assistant_text_parts)
                )
            return

    async def _recover_provider(
        self, client_id: str, cli_name: str, work_dir: Optional[str] = None,
    ) -> bool:
        """Shutdown and rebuild the ACP provider + session after a failure.

        Cleans up the old provider (shutdown + remove from dicts), then
        rebuilds via ``_ensure_session()`` which handles both initialize
        and session creation.

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name.
            work_dir: Working directory override.

        Returns:
            True if recovery succeeded and a new session is active.
        """
        session_key = (client_id, cli_name)
        old_provider = self._sessions.pop(session_key, None)
        old_session_id = self._session_ids.pop(session_key, None)

        logger.info(f"🔧 开始恢复 ACP 连接: cli={cli_name}, old_session={old_session_id[:16] if old_session_id else 'None'}")

        if old_provider:
            proc_status = "unknown"
            if hasattr(old_provider, '_proc') and old_provider._proc:
                rc = getattr(old_provider._proc, 'returncode', None)
                proc_status = "alive" if rc is None else f"exited(code={rc})"
            logger.info(f"🔧 旧 provider 进程状态: {proc_status}")
            try:
                await old_provider.shutdown()
                logger.info("🔧 旧 provider 已关闭")
            except Exception as e:
                logger.warning(f"🔧 关闭旧 provider 出错: {e}")

        # Rebuild via _ensure_session (initialize + restore/new session)
        target_dir = work_dir or self.config.work_dir
        provider = await self._ensure_session(client_id, cli_name, target_dir)
        if provider:
            logger.info(f"✅ ACP 恢复成功: cli={cli_name}")
            return True
        else:
            logger.error(f"❌ ACP 恢复失败: cli={cli_name}")
            return False

    def _persist_prompt_messages(
        self, session_id: str, user_message: str, assistant_text: str,
    ) -> None:
        """Persist user message and assistant response to local history.

        Called after a successful prompt for resume-only CLIs (those that
        support session/resume but NOT session/load). This enables serving
        history from local storage after a successful resume on reconnection.

        Non-fatal: logs errors but never raises. History persistence is
        best-effort — losing it only means the user sees empty chat after
        the next reconnection.

        Args:
            session_id: The active session identifier.
            user_message: The user's original message text.
            assistant_text: Concatenated assistant text response.
        """
        try:
            self.session_store.append_message(session_id, {
                "role": "user",
                "type": "text",
                "content": user_message,
            })
            if assistant_text:
                self.session_store.append_message(session_id, {
                    "role": "assistant",
                    "type": "text",
                    "content": assistant_text,
                })
            logger.debug(
                f"本地历史已持久化: session={session_id[:16]}..., "
                f"user_len={len(user_message)}, assistant_len={len(assistant_text)}"
            )
        except Exception as e:
            logger.warning(f"本地历史持久化失败（非致命）: session={session_id[:16]}..., error={e}")

    # ── Event conversion ──

    @staticmethod
    def _event_to_chunk(event: AgentEvent) -> Optional[StreamChunk]:
        """AgentEvent → StreamChunk"""
        if event.type == AgentEventType.TEXT_CHUNK:
            return StreamChunk(type=StreamChunkType.TEXT, content=event.data.get("text", ""))

        if event.type == AgentEventType.THOUGHT_CHUNK:
            return StreamChunk(type=StreamChunkType.THINKING, content=event.data.get("text", ""))

        if event.type == AgentEventType.FILE_EDIT:
            logger.debug(f"FILE_EDIT → DIFF: path={event.data.get('path')}, old_len={len(event.data.get('full_old', ''))}, new_len={len(event.data.get('full_new', ''))}")
            return StreamChunk(
                type=StreamChunkType.DIFF,
                content="",
                file_path=event.data.get("path", ""),
                old_content=event.data.get("full_old", event.data.get("old", "")),
                new_content=event.data.get("full_new", event.data.get("new", "")),
            )

        if event.type == AgentEventType.TOOL_CALL_START:
            name = event.data.get("name", t("backend.toolCall"))
            kind = event.data.get("kind", "")
            tool_id = event.data.get("id", "")
            tool_input = event.data.get("tool_input", "")
            return StreamChunk(
                type=StreamChunkType.TOOL_USE, content=name,
                kind=kind, tool_input=tool_input, tool_id=tool_id,
                status="running",
                locations=event.data.get("locations"),
                terminal_id=event.data.get("terminal_id"),
                content_blocks=event.data.get("content_blocks"),
            )

        if event.type == AgentEventType.TOOL_CALL_UPDATE:
            tool_id = event.data.get("id", "")
            name = event.data.get("name", "")
            status = event.data.get("status", "")
            progress = event.data.get("progress", "")
            content_blocks = event.data.get("content_blocks")
            is_done = status in ("completed", "done", "success", "ToolCallStatus.COMPLETED")
            is_failed = status in ("failed", "error", "ToolCallStatus.FAILED")
            chunk_status = "failed" if is_failed else ("completed" if is_done else "running")
            return StreamChunk(
                type=StreamChunkType.TOOL_UPDATE, content=name,
                tool_id=tool_id, status=chunk_status,
                tool_input=progress if progress else None,
                content_blocks=content_blocks,
            )

        if event.type == AgentEventType.PLAN_UPDATE:
            entries = event.data.get("entries", [])
            lines = [t("backend.plan")]
            for e in entries:
                icon = "✅" if e.get("status") == "completed" else "⏳" if e.get("status") == "in_progress" else "⬜"
                lines.append(f"  {icon} {e.get('title', '')}")
            return StreamChunk(type=StreamChunkType.TEXT, content="\n".join(lines) + "\n")

        if event.type == AgentEventType.ERROR:
            return StreamChunk(type=StreamChunkType.ERROR, content=event.data.get("error", ""))

        if event.type == AgentEventType.MODE_CHANGE:
            return StreamChunk(
                type=StreamChunkType.MODE_CHANGE,
                content=event.data.get("mode_id", ""),
            )

        if event.type == AgentEventType.CONFIG_UPDATE:
            import json
            return StreamChunk(
                type=StreamChunkType.CONFIG_UPDATE,
                content=json.dumps(event.data.get("options", []), ensure_ascii=False, default=str),
            )

        if event.type == AgentEventType.SESSION_INFO:
            import json
            return StreamChunk(
                type=StreamChunkType.SESSION_INFO,
                content=json.dumps(event.data, ensure_ascii=False, default=str),
            )

        if event.type == AgentEventType.TURN_END:
            return None

        return None

    # ── Session management ──

    async def _load_session_history(
        self, client_id: str, cli_name: str, session_id: str,
    ) -> list[dict] | None:
        """Load a session and collect replayed history events.

        Shared by switch_session. On ACP auth error (-32000),
        raises AuthRequiredError for the interceptor chain to handle.

        Return value semantics (consistent with _load_session_history_with_timeout):
          - list (possibly empty): ACP responded normally.
          - None: transient failure — session may still be valid.

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name.
            session_id: The session to load.

        Returns:
            List of history message dicts on success, None on transient failure.

        Raises:
            AuthRequiredError: If load_session fails with ACP -32000.
        """
        provider = await self._ensure_provider(client_id, cli_name)
        if not provider:
            return []
        if not session_id:
            return []
        logger.debug(f"_load_session_history: 加载会话: cli={cli_name}, session={session_id[:16]}...")
        try:
            history = await provider.load_session(session_id)
            # load_session sets provider._session_id on success, leaves it
            # unchanged on failure (e.g. Resource not found). Check this to
            # distinguish "empty session" from "session doesn't exist".
            if getattr(provider, '_session_id', None) != session_id:
                # CLI reported the session doesn't exist — clean up stale record
                self.session_store.remove(session_id)
                logger.info(f"_load_session_history: 会话不存在，已清理: {session_id[:16]}...")
                return None
            self._session_ids[(client_id, cli_name)] = session_id
            logger.info(f"_load_session_history: cli={cli_name}, session={session_id[:16]}..., {len(history)} 条历史")
            return history
        except Exception as e:
            self._check_auth_error(e, cli_name, "load_session")
            logger.warning(
                f"_load_session_history: 暂时性错误: cli={cli_name}, "
                f"session={session_id[:16]}..., error={e}"
            )
            return None

    async def _try_resume_session(
        self, client_id: str, cli_name: str, session_id: str,
    ) -> bool:
        """Attempt to resume a session via ACP session/resume.

        Tries the fast resume path (no history replay). On success, sets
        the active session_id. On failure, returns False so the caller
        can fall back to session/load.

        Uses the configured session_resume.timeout to prevent hanging on
        unresponsive CLIs.

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name.
            session_id: The session to resume.

        Returns:
            True if resume succeeded, False otherwise.
        """
        provider = await self._ensure_provider(client_id, cli_name)
        if not provider:
            return False

        caps = provider.capabilities
        if not caps or not caps.supports_session_resume:
            logger.debug(f"_try_resume_session 跳过: cli={cli_name} 不支持 session/resume")
            return False

        resume_timeout = self.config.session_resume.timeout
        logger.debug(
            f"_try_resume_session: cli={cli_name}, session={session_id[:16]}..., "
            f"timeout={resume_timeout}s"
        )

        try:
            success = await asyncio.wait_for(
                provider.resume_session(session_id),
                timeout=resume_timeout,
            )
        except asyncio.TimeoutError:
            logger.warning(
                f"_try_resume_session: 超时: cli={cli_name}, "
                f"session={session_id[:16]}..., timeout={resume_timeout}s"
            )
            return False
        except Exception as e:
            logger.warning(
                f"_try_resume_session: 异常: cli={cli_name}, "
                f"session={session_id[:16]}..., error={e}"
            )
            return False

        if success:
            session_key = (client_id, cli_name)
            self._session_ids[session_key] = session_id
            logger.info(f"_try_resume_session: 恢复成功: cli={cli_name}, session={session_id[:16]}...")
            return True

        logger.debug(f"_try_resume_session: 恢复失败: cli={cli_name}, session={session_id[:16]}...")
        return False

    def _is_resume_only_cli(self, client_id: str, cli_name: str) -> bool:
        """Check if the CLI supports resume but NOT load (resume-only).

        Delegates to ProviderCapabilities.is_resume_only property which
        encapsulates the capability check logic.

        Args:
            client_id: WebSocket client identifier.
            cli_name: CLI adapter name.

        Returns:
            True if CLI supports resume but not load.
        """
        session_key = (client_id, cli_name)
        provider = self._sessions.get(session_key)
        if not provider:
            return False
        caps = provider.capabilities
        if not caps:
            return False
        return caps.is_resume_only

    async def read_history(self, cli_name: str, client_id: str, session_id: Optional[str] = None) -> dict:
        """Read chat history with resume-first strategy and load fallback.

        Implements the resume-first reconnection strategy:
          1. If CLI supports session/resume AND a previous session_id exists:
             try resume first (fast, no history transfer).
          2. On resume success: serve locally persisted history for resume-only
             CLIs, or empty history (App retains local). Set resumed=True.
          3. On resume failure: fall back to session/load (existing flow).
             Set resumed=False.
          4. If neither supported: create new session, resumed=False.

        Session deletion policy (prevents data loss from transient errors):
          - Timeout / network error / provider not ready → retry once
            after a short backoff. Session record is preserved.
          - ACP returns empty list (0 messages) → session exists but is
            empty (e.g. freshly created). Session record is preserved.
          - Only explicit caller action (session.close) deletes records.

        Returns:
            Dict with keys: messages (list), total (int), has_more (bool),
            resumed (bool).
        """
        session_key = (client_id, cli_name)

        async def _do_read():
            current_id = session_id or self._session_ids.get(session_key, "")
            target_id = current_id

            # If the current session is a freshly created empty one,
            # check SessionStore for a previous session with actual history.
            # This handles the common case where _init_provider created a
            # new session (for config/mode), but the user's last conversation
            # is in an older session.
            if target_id and not session_id:
                native_cwd = self.config.work_dir
                store_sessions = self.session_store.list_by_cwd(native_cwd, cli_name)
                if not store_sessions:
                    wsl_cwd = win_to_wsl(native_cwd)
                    if wsl_cwd != native_cwd:
                        store_sessions = self.session_store.list_by_cwd(wsl_cwd, cli_name)
                # Find the most recent session with history (non-empty preview)
                for s in store_sessions:
                    if s.get("preview", "") and s["id"] != target_id:
                        target_id = s["id"]
                        logger.debug(f"read_history: 切换到有历史的旧会话: {target_id[:16]}...")
                        break

            if not target_id:
                native_cwd = self.config.work_dir
                target_id = self.session_store.get_latest(native_cwd, cli_name) or ""
                if not target_id:
                    wsl_cwd = win_to_wsl(native_cwd)
                    if wsl_cwd != native_cwd:
                        target_id = self.session_store.get_latest(wsl_cwd, cli_name) or ""
            if not target_id:
                logger.debug(f"read_history: 没有可用的会话: cli={cli_name}")
                return {"messages": [], "total": 0, "has_more": False, "resumed": False}

            # ── Resume-first strategy ──
            # Try session/resume before session/load for faster reconnection.
            # Resume restores server-side context without replaying history.
            resumed = await self._try_resume_session(client_id, cli_name, target_id)
            if resumed:
                # Resume succeeded — serve locally persisted history for
                # resume-only CLIs (those that can't replay via load).
                if self._is_resume_only_cli(client_id, cli_name):
                    local_history = self.session_store.load_history(target_id)
                    logger.info(
                        f"read_history: resume 成功 (resume-only CLI), "
                        f"本地历史 {len(local_history)} 条: cli={cli_name}"
                    )
                    result = self._cache_and_paginate(session_key, local_history)
                    result["resumed"] = True
                    return result
                else:
                    # CLI supports both resume and load — App retains local
                    # messages, no history transfer needed.
                    logger.info(
                        f"read_history: resume 成功, App 保留本地消息: cli={cli_name}"
                    )
                    return {"messages": [], "total": 0, "has_more": False, "resumed": True}

            # ── Fall back to session/load (existing flow) ──
            load_timeout = self.config.timeouts.session_load

            # First attempt
            history = await self._load_session_history_with_timeout(
                client_id, cli_name, target_id, timeout=load_timeout
            )

            # None = session not found or transient failure.
            # If we were trying a historical session, fall back to the
            # current (new) session instead of retrying the dead one.
            if history is None and target_id != current_id and current_id:
                logger.info(f"read_history: 旧会话不可用，回退到当前会话: {current_id[:16]}...")
                target_id = current_id
                history = await self._load_session_history_with_timeout(
                    client_id, cli_name, target_id, timeout=load_timeout
                )

            # None after fallback = transient failure → retry once
            if history is None:
                logger.info(
                    f"read_history: 加载失败，2s 后重试: "
                    f"cli={cli_name}, session={target_id[:16]}..."
                )
                await asyncio.sleep(2.0)
                history = await self._load_session_history_with_timeout(
                    client_id, cli_name, target_id, timeout=load_timeout
                )

            if history is None:
                logger.warning(
                    f"read_history: 重试后仍失败，返回空结果: "
                    f"cli={cli_name}, session={target_id[:16]}..."
                )
                history = []

            result = self._cache_and_paginate(session_key, history)
            result["resumed"] = False
            return result

        return await self._with_session_lock(session_key, _do_read())

    async def _load_session_history_with_timeout(
        self, client_id: str, cli_name: str, session_id: str, timeout: float = 0
    ) -> list | None:
        """Load session history with a timeout on the ACP call only.

        Provider initialization is NOT subject to this timeout — it has
        its own timeout in _init_provider. This prevents slow CLI cold
        starts (e.g. Qoder ~3s) from being killed by the history load
        timeout, which caused the cold-start race condition.

        Return value semantics (important for caller's delete decision):
          - list (possibly empty): ACP responded normally. The session
            exists and was loaded. An empty list means the session has
            no messages yet (e.g. freshly created).
          - None: transient failure (timeout, network error, provider
            not ready). The session may still be valid — caller must
            NOT delete it from the store.

        Args:
            client_id: The requesting client identifier.
            cli_name: The CLI provider name.
            session_id: The session to load.
            timeout: Maximum seconds for the load_session ACP call.
                     Defaults to config.timeouts.session_load.

        Returns:
            List of history messages on success (may be empty),
            or None on transient failure (timeout, exception).

        Raises:
            AuthRequiredError: If ACP returns auth error (-32000).
        """
        effective_timeout = timeout or self.config.timeouts.session_load
        # Phase 1: ensure provider is ready (no timeout — _init_provider
        # manages its own lifecycle timeouts)
        provider = await self._ensure_provider(client_id, cli_name)
        if not provider:
            # Provider not available (CLI not installed/configured).
            # Return empty list (not None) — retrying won't help.
            logger.debug(f"_load_session_history: provider 不可用: cli={cli_name}")
            return []
        if not session_id:
            return []
        # Phase 2: load session with timeout (pure ACP RPC, should be fast
        # once provider is ready)
        logger.debug(f"_load_session_history: 加载会话: cli={cli_name}, session={session_id[:16]}...")
        try:
            history = await asyncio.wait_for(
                provider.load_session(session_id),
                timeout=effective_timeout,
            )
            self._session_ids[(client_id, cli_name)] = session_id
            logger.info(f"_load_session_history: cli={cli_name}, session={session_id[:16]}..., {len(history)} 条历史")
            return history
        except asyncio.TimeoutError:
            logger.warning(
                f"_load_session_history: 加载超时: cli={cli_name}, "
                f"session={session_id[:16]}..., timeout={effective_timeout}s"
            )
            return None
        except Exception as e:
            self._check_auth_error(e, cli_name, "load_session")
            logger.warning(
                f"_load_session_history: 暂时性错误: cli={cli_name}, "
                f"session={session_id[:16]}..., error={e}"
            )
            return None

    async def read_history_page(self, cli_name: str, client_id: str, offset: int, limit: int) -> dict:
        """Read a page of older history from the in-memory cache.

        Called when the App scrolls to the top and needs more messages.
        Respects both item count limit and byte size limit — whichever
        is hit first ends the page. This prevents oversized payloads
        when messages contain large tool call results.

        Args:
            cli_name: CLI adapter name.
            client_id: WebSocket client identifier.
            offset: Number of messages already loaded by the App (from the end).
            limit: Maximum number of messages to return in this page.

        Returns:
            Dict with keys: messages (list), total (int), has_more (bool).
        """
        session_key = (client_id, cli_name)
        cache = self._history_cache.get(session_key, [])
        total = len(cache)

        if offset >= total:
            return {"messages": [], "total": total, "has_more": False}

        end_idx = total - offset
        start_idx = max(0, end_idx - limit)
        max_bytes = self.config.history.page_max_bytes

        # Walk backward from end_idx, accumulating bytes until limit is hit
        page = []
        byte_count = 0
        for i in range(end_idx - 1, start_idx - 1, -1):
            item = cache[i]
            item_bytes = len(item.get("content", "").encode("utf-8", errors="ignore"))
            if page and byte_count + item_bytes > max_bytes:
                # Byte limit reached — stop before this item
                start_idx = i + 1
                break
            page.insert(0, item)
            byte_count += item_bytes

        has_more = start_idx > 0
        logger.info(f"read_history_page: offset={offset}, 返回 {len(page)} 条 "
                     f"({byte_count // 1024}KB), has_more={has_more}")
        return {"messages": page, "total": total, "has_more": has_more}

    def _cache_and_paginate(self, key: tuple[str, str], history: list[dict]) -> dict:
        """Cache full history and return the last page.

        Stores the complete history in _history_cache for subsequent
        read_history_page calls. Returns only the last page worth of items,
        respecting both item count and byte size limits.

        Args:
            key: (client_id, cli_name) tuple.
            history: Full history list from ACP session/load.

        Returns:
            Dict with keys: messages (list), total (int), has_more (bool).
        """
        page_size = self.config.history.page_size
        max_bytes = self.config.history.page_max_bytes
        total = len(history)

        if total <= page_size:
            self._history_cache.pop(key, None)
            return {"messages": history, "total": total, "has_more": False}

        # Cache full history, then take the last page respecting byte limit
        self._history_cache[key] = history
        # Evict oldest entries if cache exceeds max size
        if len(self._history_cache) > self._MAX_HISTORY_CACHE_ENTRIES:
            oldest_key = next(iter(self._history_cache))
            self._history_cache.pop(oldest_key, None)
            logger.debug(f"历史缓存淘汰: evicted={oldest_key[1]}, size={len(self._history_cache)}")
        page = []
        byte_count = 0
        for i in range(total - 1, max(0, total - page_size) - 1, -1):
            item = history[i]
            item_bytes = len(item.get("content", "").encode("utf-8", errors="ignore"))
            if page and byte_count + item_bytes > max_bytes:
                break
            page.insert(0, item)
            byte_count += item_bytes

        logger.info(f"历史分页: total={total}, 发送最后 {len(page)} 条 "
                     f"({byte_count // 1024}KB), 缓存 {total - len(page)} 条")
        return {"messages": page, "total": total, "has_more": len(page) < total}

    async def list_sessions(self, cli_name: str, client_id: str) -> list[dict]:
        """List sessions: prefer ACP session/list, fallback to SessionStore.

        On ACP auth error (-32000), raises AuthRequiredError for the
        interceptor chain to handle.

        Args:
            cli_name: CLI adapter name.
            client_id: WebSocket client identifier.

        Returns:
            List of session dicts.

        Raises:
            AuthRequiredError: If list_sessions fails with ACP -32000.
        """
        session_key = (client_id, cli_name)

        async def _do_list():
            provider = await self._ensure_provider(client_id, cli_name)

            if provider and hasattr(provider, 'list_sessions'):
                cwd = self.config.work_dir
                logger.debug(f"list_sessions: 尝试 ACP session/list: cli={cli_name}, cwd={cwd}")
                try:
                    acp_sessions = await provider.list_sessions(cwd=cwd)
                except Exception as e:
                    self._check_auth_error(e, cli_name, "list_sessions")
                    raise
                if acp_sessions:
                    logger.debug(f"list_sessions: ACP 返回 {len(acp_sessions)} 个会话")
                    return acp_sessions
            # Try native path first, then WSL format for backward compatibility
            native_cwd = self.config.work_dir
            store_sessions = self.session_store.list_by_cwd(native_cwd, cli_name)
            if not store_sessions:
                wsl_cwd = win_to_wsl(native_cwd)
                if wsl_cwd != native_cwd:
                    store_sessions = self.session_store.list_by_cwd(wsl_cwd, cli_name)
            logger.debug(f"list_sessions: SessionStore 返回 {len(store_sessions)} 个会话, cwd={native_cwd!r}")
            return store_sessions

        return await self._with_session_lock(session_key, _do_list())

    async def new_session(self, cli_name: str, client_id: str) -> bool:
        """Create a new session.

        On ACP auth error (-32000), raises AuthRequiredError for the
        interceptor chain to handle.

        Args:
            cli_name: CLI adapter name.
            client_id: WebSocket client identifier.

        Returns:
            True if session was created successfully.

        Raises:
            AuthRequiredError: If new_session fails with ACP -32000.
        """
        session_key = (client_id, cli_name)

        async def _do_new():
            provider = await self._ensure_provider(client_id, cli_name)
            if not provider:
                return False
            target_dir = self.config.work_dir
            logger.debug(f"new_session: 创建新会话: {cli_name}")
            try:
                session_id = await provider.new_session(target_dir)
            except Exception as e:
                self._check_auth_error(e, cli_name, "new_session")
                raise
            self._session_ids[session_key] = session_id
            store_cwd = self._normalize_cwd(target_dir, provider)
            self.session_store.add(session_id, cli_name, store_cwd)
            self._history_cache.pop(session_key, None)  # Clear old session cache
            await self._push_pending_config(session_key, provider)
            logger.info(f"new_session: 新会话: {session_id[:16]}...")
            return True

        return await self._with_session_lock(session_key, _do_new())

    async def switch_session(self, cli_name: str, client_id: str, session_id: str) -> dict:
        """Switch to a specific session. Returns paginated history.

        If the session fails to load (transient error), returns empty
        history without deleting the session record.
        """
        session_key = (client_id, cli_name)

        async def _do_switch():
            history = await self._load_session_history(client_id, cli_name, session_id)
            # None = transient failure → treat as empty for this request
            if history is None:
                logger.warning(
                    f"switch_session: 加载失败，返回空历史: "
                    f"cli={cli_name}, session={session_id[:16]}..."
                )
                history = []
            return self._cache_and_paginate(session_key, history)

        return await self._with_session_lock(session_key, _do_switch())

    async def close_session(self, cli_name: str, client_id: str, session_id: str) -> None:
        """Close (delete) a session.

        Calls ACP close_session if the CLI supports it, then removes
        the session from SessionStore and any locally persisted history.

        Args:
            cli_name: CLI adapter name.
            client_id: WebSocket client identifier.
            session_id: The session to close.
        """
        session_key = (client_id, cli_name)
        provider = self._sessions.get(session_key)

        # Call ACP close_session if supported
        if provider:
            try:
                if hasattr(provider, 'close_session'):
                    await provider.close_session(session_id)
                    logger.info(f"ACP close_session 成功: {session_id[:16]}...")
            except Exception as e:
                logger.debug(f"ACP close_session 出错（可忽略）: {e}")

        # Remove from local SessionStore (metadata + persisted history)
        self.session_store.remove(session_id)
        self.session_store.remove_history(session_id)
        logger.info(f"会话已删除: {session_id[:16]}...")

        # If the closed session was the active one, clear it
        if self._session_ids.get(session_key) == session_id:
            self._session_ids.pop(session_key, None)

    def _build_message(self, message: str, context: Optional[dict] = None) -> str:
        if not context:
            return message
        parts = []
        if context.get("active_file"):
            parts.append(f"[当前文件: {context['active_file']}]")
        if context.get("selected_lines"):
            lines = context["selected_lines"]
            parts.append(f"[选中行: {lines[0]}-{lines[-1]}]")
        if parts:
            return " ".join(parts) + "\n" + message
        return message

    async def cancel_current(self, cli_name: str, client_id: str):
        """Cancel current prompt"""
        session_key = (client_id, cli_name)
        provider = self._sessions.get(session_key)
        session_id = self._session_ids.get(session_key, "")
        if provider and session_id:
            logger.info(f"取消当前请求: {cli_name}, session={session_id[:16]}...")
            await provider.cancel(session_id)

    def remap_client(self, old_client_id: str, new_client_id: str) -> None:
        """Remap all session state from old_client_id to new_client_id.

        Called when a client reconnects within the grace period and gets a
        new WebSocket-level client_id. Moves providers, session_ids, history
        cache, and background tasks so the existing ACP process continues
        serving the reconnected client.

        Args:
            old_client_id: The client_id from the previous connection.
            new_client_id: The client_id for the new connection.
        """
        remapped = 0
        for key in [k for k in self._sessions if k[0] == old_client_id]:
            cli_name = key[1]
            new_key = (new_client_id, cli_name)
            self._sessions[new_key] = self._sessions.pop(key)
            if key in self._session_ids:
                self._session_ids[new_key] = self._session_ids.pop(key)
            if key in self._history_cache:
                self._history_cache[new_key] = self._history_cache.pop(key)
            if key in self._provider_tasks:
                self._provider_tasks[new_key] = self._provider_tasks.pop(key)
            remapped += 1
        # Remap background tasks
        if old_client_id in self._background_tasks:
            self._background_tasks[new_client_id] = self._background_tasks.pop(old_client_id)
        if remapped:
            logger.info(f"CLI remap: {old_client_id} → {new_client_id}, {remapped} provider(s)")

    async def cleanup_sessions(self, client_id: str):
        """Clean up sessions for a disconnected client.

        Cancels background tasks (recovery monitors, progressive status),
        then shuts down each provider with a timeout. If shutdown fails or
        times out, the provider's process is force-killed.
        """
        # Cancel background tasks (recovery, progressive status)
        bg_tasks = self._background_tasks.pop(client_id, [])
        for task in bg_tasks:
            if not task.done():
                task.cancel()
        for task in bg_tasks:
            if not task.done():
                try:
                    await task
                except (asyncio.CancelledError, Exception):
                    pass

        keys = [k for k in self._sessions if k[0] == client_id]
        timeout = self.config.lifecycle.provider_shutdown_timeout
        for key in keys:
            provider = self._sessions.pop(key)
            self._session_ids.pop(key, None)
            self._history_cache.pop(key, None)
            self._session_locks.pop(key, None)
            try:
                await asyncio.wait_for(provider.shutdown(), timeout=timeout)
            except asyncio.TimeoutError:
                logger.warning(f"清理会话超时 ({timeout}s): cli={key[1]}")
            except Exception as e:
                logger.warning(f"清理会话出错: {e}")

    async def cleanup_all(self):
        """Graceful shutdown: close sessions → ACP connections → kill processes.

        Called during Agent shutdown. Each provider gets a configurable timeout
        to shut down gracefully. Providers that don't respond in time are
        force-killed. All internal state (sessions, caches, locks) is cleared.
        """
        timeout = self.config.lifecycle.provider_shutdown_timeout
        logger.info(f"开始清理所有 CLI: {len(self._sessions)} 个 provider")
        for key, provider in list(self._sessions.items()):
            session_id = self._session_ids.get(key)
            # Try to close the ACP session first
            try:
                if session_id and hasattr(provider, 'close_session'):
                    await asyncio.wait_for(provider.close_session(session_id), timeout=5)
            except Exception as e:
                logger.debug(f"关闭会话出错（可忽略）: {e}")
            # Shut down the provider (kills the CLI process)
            try:
                await asyncio.wait_for(provider.shutdown(), timeout=timeout)
            except asyncio.TimeoutError:
                logger.warning(f"关闭 provider 超时 ({timeout}s): cli={key[1]}")
            except Exception as e:
                logger.warning(f"关闭 provider 出错: {e}")
        self._sessions.clear()
        self._session_ids.clear()
        self._provider_tasks.clear()
        self._session_locks.clear()
        self._history_cache.clear()
        # Cancel all background tasks (recovery, progressive status)
        for tasks in self._background_tasks.values():
            for task in tasks:
                if not task.done():
                    task.cancel()
        self._background_tasks.clear()
        logger.info("所有 CLI 已清理完毕")
