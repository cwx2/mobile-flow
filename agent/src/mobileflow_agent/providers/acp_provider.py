"""
ACP Provider：通过官方 agent-client-protocol SDK 与 AI CLI 交互
职责：生命周期管理（启动/连接/会话/prompt/关闭）
具体的 Client 回调实现在 acp_client.py
事件转换逻辑在 acp_converter.py
"""

from __future__ import annotations

import asyncio
from typing import Any, AsyncGenerator, Optional

from loguru import logger

from .acp_client import ACPClientImpl, ACPEventCollector
from .acp_converter import serialize_config_options
from .base import (
    AgentEvent,
    AgentEventType,
    AgentProvider,
    ProviderCapabilities,
    ProviderLifecycleState,
)
from ..utils.path import win_to_wsl
from ..utils.command import which


class ACPProvider(AgentProvider):
    """
    ACP Provider：配置驱动，只需要 command + args
    通用实现，兼容所有 ACP CLI（Kiro、Codex、Claude Code 等）

    Public API (inherited from AgentProvider):
        detect, env_check, initialize, shutdown, authenticate,
        new_session, list_sessions, load_session, prompt,
        cancel, set_model, set_mode, is_running, capabilities

    Private helpers:
        _build_prompt_blocks, _consume_events, _handle_task_done,
        _is_connection_lost, _parse_capabilities, _parse_auth_method
    """

    def __init__(
        self,
        command: str,
        args: list[str],
        env: dict[str, str] | None = None,
        execution_env: str = "native",
        display_name: str = "",
        event_bus=None,
        install_hint: str = "",
        process_terminate_timeout: float = 5.0,
    ):
        """Initialize ACP Provider.

        Args:
            command: CLI executable name or path (e.g. "codex-acp", "claude").
            args: Command-line arguments passed to the CLI process.
            env: Extra environment variables merged on top of SDK defaults.
            execution_env: Runtime environment — "native" or "wsl".
            display_name: Human-readable name shown in status messages.
            event_bus: Application EventBus for broadcasting provider events.
            install_hint: User-facing install instructions when CLI is not found.
            process_terminate_timeout: Seconds to wait after SIGTERM before
                force-killing the CLI process during shutdown.
        """
        self._command = command
        self._args = args
        self._env = env or {}
        self._execution_env = execution_env
        self._display_name = display_name
        self._event_bus = event_bus
        self._install_hint = install_hint
        self._process_terminate_timeout = process_terminate_timeout
        self._conn = None
        self._proc = None
        self._collector = ACPEventCollector()
        self._client_impl = ACPClientImpl(self._collector, event_bus=event_bus)
        self._session_id: Optional[str] = None
        self._ctx_manager = None
        self._capabilities: Optional[ProviderCapabilities] = None
        self._needs_recovery = False
        self._last_cwd: str = ""
        self._lifecycle_state: ProviderLifecycleState = ProviderLifecycleState.UNINITIALIZED
        self._error_message: str = ""

        # Pending config data from new_session response.
        # Stored here because the event collector queue gets cleared before
        # each prompt — events put during new_session would be lost.
        # cli_manager reads and clears these after session creation.
        self._pending_config_options: list[dict] | None = None
        self._pending_initial_mode: str = ""

    # ── Guard helpers ──

    def _ensure_connection(self, operation: str) -> bool:
        """Guard: verify ACP connection exists.

        Logs a debug message and returns False if connection is unavailable.
        Used by session methods to avoid repeating the same guard check.

        Args:
            operation: Name of the calling operation (for log message).

        Returns:
            True if connection is available, False otherwise.
        """
        if not self._conn:
            logger.debug(f"{operation} 跳过: conn 不存在")
            return False
        return True

    def _ensure_capability(self, capability: str, operation: str) -> bool:
        """Guard: verify connection and a specific capability are available.

        Checks both connection existence and the named capability flag.
        Logs debug messages for each failure condition.

        Args:
            capability: Attribute name on ProviderCapabilities (e.g. 'supports_session_list').
            operation: Name of the calling operation (for log message).

        Returns:
            True if both connection and capability are available.
        """
        if not self._ensure_connection(operation):
            return False
        if not self._capabilities:
            logger.debug(f"{operation} 跳过: capabilities 未初始化")
            return False
        if not getattr(self._capabilities, capability, False):
            logger.debug(f"{operation} 跳过: {capability}=False")
            return False
        return True

    # ── 检测 ──

    # ── Lifecycle (public) ──

    async def detect(self) -> bool:
        """Detect whether the CLI binary is available in the system.

        For WSL environment, runs ``which`` inside WSL bash.
        For native environment, uses ``utils.command.which()``.

        Returns:
            True if the CLI command is found and executable, False otherwise.
        """
        logger.debug(f"CLI 检测: command={self._command!r}, env={self._execution_env}")
        if self._execution_env == "wsl":
            try:
                check = f"test -x {self._command}" if "/" in self._command else f"which {self._command}"
                proc = await asyncio.create_subprocess_exec(
                    "wsl", "bash", "-lc", f"{check} 2>/dev/null && echo ok",
                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
                )
                stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=5)
                return "ok" in stdout.decode()
            except Exception:
                return False
        return which(self._command) is not None

    # ── 生命周期 ──

    async def env_check(self) -> tuple[bool, str]:
        """Pre-flight environment check before spawning the CLI process.

        Validates that the runtime environment is ready:
        - WSL: verifies ``wsl bash -lc "echo ok"`` succeeds.
        - Native: verifies CLI binary exists in PATH via ``which()``.

        All subprocess calls have a 10-second timeout to avoid hanging.

        Returns:
            Tuple of (success, error_message). On success, error_message is "".
            On failure, error_message is a user-friendly Chinese string.
        """
        logger.debug(f"环境预检: command={self._command!r}, env={self._execution_env}")
        try:
            if self._execution_env == "wsl":
                # Verify WSL is installed and operational
                proc = await asyncio.create_subprocess_exec(
                    "wsl", "bash", "-lc", "echo ok",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=10)
                if "ok" not in stdout.decode():
                    msg = "WSL 未安装或无法启动，请在 PowerShell 中运行 wsl --install"
                    logger.warning(f"环境预检失败: {msg}")
                    return (False, msg)
            else:
                # Native: verify CLI binary exists in PATH
                resolved = which(self._command)
                if not resolved:
                    hint = self._install_hint or f"请检查安装"
                    msg = f"未找到 {self._display_name or self._command}，{hint}"
                    logger.warning(f"环境预检失败: {msg}")
                    return (False, msg)

            logger.info(f"环境预检通过: {self._display_name or self._command}")
            return (True, "")

        except asyncio.TimeoutError:
            msg = "环境检查超时，请检查系统状态"
            logger.warning(f"环境预检超时: command={self._command!r}")
            return (False, msg)
        except Exception as e:
            msg = f"环境检查失败: {e}"
            logger.error(f"环境预检异常: {e}")
            return (False, msg)

    async def initialize(self, cwd: str) -> ProviderCapabilities:
        """Start the ACP Agent subprocess and complete the initialize handshake.

        Spawns the CLI process via ``acp.spawn_agent_process()``, then calls
        ``connection.initialize()`` to negotiate protocol version and discover
        agent capabilities (session support, multimodal, MCP, auth methods).

        Uses ``default_environment()`` from ACP SDK as base env, merged with
        user-provided overrides. Handles WSL path translation and Windows
        .cmd/.bat wrapper detection.

        Args:
            cwd: Working directory for the agent process. On WSL, automatically
                converted to WSL path format via ``win_to_wsl()``.

        Returns:
            ProviderCapabilities with all negotiated capabilities.

        Raises:
            Exception: On any startup or handshake failure. Lifecycle state
                is set to FAILED and error_message is populated.
        """
        from acp import spawn_agent_process, default_environment, PROTOCOL_VERSION

        self._lifecycle_state = ProviderLifecycleState.STARTING
        self._error_message = ""

        try:
            self._client_impl.set_work_dir(cwd)
            self._last_cwd = cwd
            logger.info(f"ACP 启动: {self._command} {' '.join(self._args)}")

            # Build environment: SDK defaults + user overrides
            env = {**default_environment(), **self._env}

            if self._execution_env == "wsl":
                wsl_cwd = win_to_wsl(cwd)
                inner = f'cd "{wsl_cwd}" && {self._command} {" ".join(self._args)}'
                cmd, cmd_args = "wsl", ["bash", "-lc", inner]
            else:
                resolved = which(self._command) or self._command
                if resolved.lower().endswith((".cmd", ".bat")):
                    cmd = "cmd"
                    cmd_args = ["/c", resolved, *self._args]
                else:
                    cmd, cmd_args = resolved, self._args

            self._ctx_manager = spawn_agent_process(
                self._client_impl, cmd, *cmd_args,
                env=env,
                cwd=cwd if self._execution_env != "wsl" else None,
                transport_kwargs={"limit": 10 * 1024 * 1024},
            )
            self._conn, self._proc = await self._ctx_manager.__aenter__()

            from mobileflow_agent import __app_name__, __version__
            init_result = await self._conn.initialize(
                protocol_version=PROTOCOL_VERSION,
                client_info={"name": __app_name__, "version": __version__},
                _meta={"client_type": "mobile", "platform": "phone"},
            )
            self._capabilities = self._parse_capabilities(init_result)

            self._lifecycle_state = ProviderLifecycleState.READY
            logger.info(f"ACP 连接成功: {self._capabilities.name} {self._capabilities.version}")
            self._needs_recovery = False
            return self._capabilities

        except Exception as e:
            self._lifecycle_state = ProviderLifecycleState.FAILED
            self._error_message = str(e)
            logger.error(f"ACP 初始化失败: {e}")
            raise

    async def shutdown(self):
        """Gracefully shut down the ACP connection and kill the subprocess.

        Shutdown sequence:
        1. Reset lifecycle state to UNINITIALIZED immediately.
        2. Call ``conn.close()`` to notify the agent (3s timeout).
        3. Call ``ctx_manager.__aexit__()`` to clean up transport (10s timeout).
        4. If __aexit__ times out, force-kill via graceful_terminate.
        5. Always verify the process is dead before releasing references.

        This method never raises — all errors are logged and swallowed.
        """
        # Reset lifecycle state immediately on shutdown entry
        self._lifecycle_state = ProviderLifecycleState.UNINITIALIZED
        logger.info("ACP 开始关闭，生命周期状态已重置为 UNINITIALIZED")

        # Graceful close: notify agent via ACP close()
        if self._conn:
            try:
                await asyncio.wait_for(self._conn.close(), timeout=3)
                logger.debug("ACP conn.close() 完成")
            except Exception as e:
                logger.debug(f"ACP conn.close() 出错（可忽略）: {e}")

        if self._ctx_manager:
            try:
                # Wrap __aexit__ with 10s timeout to prevent hanging
                await asyncio.wait_for(
                    self._ctx_manager.__aexit__(None, None, None), timeout=10
                )
                logger.info("ACP __aexit__ 正常完成")
            except asyncio.TimeoutError:
                logger.warning("ACP __aexit__ 超时（10秒）")
            except Exception as e:
                logger.warning(f"ACP 关闭出错: {e}")

        # Always verify the process is dead — even if __aexit__ succeeded,
        # the child process may still be alive on some platforms (Windows).
        if self._proc and self._proc.returncode is None:
            from ..utils.process import graceful_terminate
            label = self._display_name or self._command
            await graceful_terminate(self._proc, timeout=self._process_terminate_timeout, label=f"ACP {label}")

        self._conn = None
        self._proc = None
        self._ctx_manager = None
        logger.info("ACP 连接已关闭，资源已释放")

    async def authenticate(self, method_id: str, data: dict) -> bool:
        """Call ACP authenticate with the given method and credentials.

        This is the low-level authenticate call. For the full auth flow with
        retry logic, see ``_with_auth_retry()``.

        Args:
            method_id: Auth method identifier from capabilities (e.g. "env_key").
            data: Credentials dict — for env_var type, maps var names to values.

        Returns:
            True if authentication succeeded, False on any error.
        """
        if not self._ensure_connection("authenticate"):
            return False
        logger.debug(f"ACP 认证请求: method={method_id}, data_keys={list(data.keys())}")
        try:
            await self._conn.authenticate(method_id=method_id, data=data)
            logger.info(f"ACP 认证成功: method={method_id}")
            return True
        except Exception as e:
            logger.error(f"ACP 认证失败: method={method_id}, error={e}")
            return False

    async def try_silent_auth(self) -> bool:
        """Proactive silent authentication.

        After initialize, checks if any auth_method of type "env_var" has all
        its required environment variables already set. If so, calls
        ``conn.authenticate()`` silently without any user interaction.

        This is best-effort: failures are logged at DEBUG level and ignored.
        Most users who have already configured their API keys will never see
        the auth prompt thanks to this layer.

        Returns:
            True if silent auth succeeded for at least one method, False otherwise.
        """
        if not self._capabilities or not self._capabilities.auth_methods:
            logger.debug("静默认证跳过: 无 auth_methods")
            return False
        if not self._ensure_connection("try_silent_auth"):
            return False

        logger.debug(f"静默认证检查: {len(self._capabilities.auth_methods)} 个认证方法")
        import os
        for method in self._capabilities.auth_methods:
            if method.get("type") != "env_var":
                continue
            env_vars = method.get("vars", [])
            if not env_vars:
                continue

            # Check if all required env vars are set
            all_set = True
            auth_data = {}
            for var in env_vars:
                name = var.get("name", "")
                optional = var.get("optional", False)
                value = os.environ.get(name, "")
                if value:
                    auth_data[name] = value
                elif not optional:
                    all_set = False
                    break

            if not all_set:
                logger.debug(f"静默认证跳过: method={method.get('id')}, 缺少必要环境变量")
                continue

            # All required vars present — try silent authenticate
            method_id = method.get("id", "")
            logger.info(f"尝试静默认证: method={method_id}")
            try:
                await self._conn.authenticate(method_id=method_id, data=auth_data)
                logger.info(f"静默认证成功: method={method_id}")
                return True
            except Exception as e:
                logger.debug(f"静默认证失败（可忽略）: method={method_id}, error={e}")

        # Layer 2: ACP probe — check if the CLI already has valid credentials
        # from a previous session (e.g., OAuth token in ~/.codex/auth.json).
        # list_sessions is read-only with no side effects, unlike new_session
        # which would create an unwanted empty session.
        if hasattr(self, 'list_sessions'):
            logger.debug("静默认证: 尝试 ACP probe (list_sessions)")
            try:
                import asyncio
                await asyncio.wait_for(self.list_sessions(), timeout=5)
                logger.info("静默认证成功: ACP probe (list_sessions) 通过，已有有效凭证")
                return True
            except Exception as e:
                logger.debug(f"静默认证: ACP probe 失败（需要用户认证）: {e}")

        return False

    # ── 会话管理 ──

    # ── Session management (public) ──

    async def new_session(self, cwd: str, mcp_servers: list[dict] | None = None) -> str:
        """Create a new ACP session.

        Auth errors (-32000) are NOT caught here — they propagate to the
        caller (cli_manager._ensure_session), which raises AuthRequiredError
        for the interceptor chain to handle.

        Also extracts available modes from the session response and stores them
        in capabilities for the frontend mode selector.

        Args:
            cwd: Working directory for the session. WSL paths are auto-converted.
            mcp_servers: Optional list of MCP server configs to pass to the agent.

        Returns:
            The new session_id string.

        Raises:
            acp.RequestError: If session creation fails (including auth errors).
        """
        logger.debug(f"new_session: cwd={cwd!r}, mcp_servers={len(mcp_servers or [])}")
        if self._execution_env == "wsl":
            cwd = win_to_wsl(cwd)

        session = await self._conn.new_session(cwd=cwd, mcp_servers=mcp_servers or [])
        self._session_id = session.session_id
        logger.info(f"ACP 新会话: {self._session_id}")

        # ── configOptions (new API, supersedes modes) ──
        # Per ACP spec: if configOptions is present, use it exclusively.
        # Config options with category "mode" replace the old modes API;
        # category "model" provides model selection; etc.
        # Stored on provider attributes — cli_manager reads and pushes to App.
        config_opts_raw = getattr(session, "config_options", None)
        self._pending_config_options = None
        self._pending_initial_mode = ""
        if config_opts_raw:
            options = serialize_config_options(config_opts_raw)
            logger.info(f"ACP 会话 configOptions: {len(options)} 项")
            self._pending_config_options = options
            # Also extract available_modes from category="mode" options
            # for backward compatibility with the ModeSelector UI
            if self._capabilities:
                for opt in options:
                    if opt.get("category") == "mode" and opt.get("type") == "select":
                        self._capabilities.available_modes = [
                            {"id": v.get("value", ""), "name": v.get("name", "")}
                            for v in opt.get("options", [])
                        ]
                        current_mode = opt.get("current_value", "")
                        if current_mode:
                            self._pending_initial_mode = str(current_mode)
                            logger.debug(f"ACP configOptions 初始模式: {current_mode}")
                        break
        else:
            # ── Legacy modes API (for older Agents that don't support configOptions yet) ──
            modes = getattr(session, "modes", None)
            if modes and self._capabilities:
                available = getattr(modes, "available_modes", [])
                self._capabilities.available_modes = [
                    {"id": getattr(m, "id", ""), "name": getattr(m, "name", "")}
                    for m in available
                ]
                current = getattr(modes, "current", None) or getattr(modes, "default", None)
                if current:
                    current_id = getattr(current, "id", "") if not isinstance(current, str) else current
                    if current_id:
                        self._pending_initial_mode = current_id
                        logger.debug(f"ACP 会话默认模式 (旧API): {current_id}")
        return self._session_id

    async def list_sessions(self, cwd: str = "") -> list[dict]:
        """List all sessions via ACP session/list.

        Auth errors (-32000) propagate to the caller for the interceptor
        chain to handle.

        Returns parsed session list with session_id, title, cwd, updated_at.
        Skips silently if the agent doesn't support session listing.

        Args:
            cwd: Working directory filter. WSL paths are auto-converted.

        Returns:
            List of session dicts, or empty list on error/unsupported.
        """
        if not self._ensure_capability("supports_session_list", "list_sessions"):
            return []

        if self._execution_env == "wsl" and cwd:
            cwd = win_to_wsl(cwd)

        try:
            logger.debug(f"ACP session/list 请求: cwd={cwd!r}")
            result = await asyncio.wait_for(
                self._conn.list_sessions(cwd=cwd or None), timeout=10
            )
            sessions = getattr(result, "sessions", []) or []
            parsed = [
                {
                    "session_id": getattr(s, "session_id", getattr(s, "sessionId", "")),
                    "title": getattr(s, "title", "") or "",
                    "cwd": getattr(s, "cwd", "") or "",
                    "updated_at": getattr(s, "updated_at", getattr(s, "updatedAt", "")) or "",
                }
                for s in sessions
            ]
            logger.debug(f"ACP session/list 返回 {len(parsed)} 个会话: {[s['session_id'][:8] + '...' for s in parsed]}")
            return parsed
        except Exception as e:
            logger.debug(f"ACP session/list 失败: {e}")
            return []

    async def close_session(self, session_id: str):
        """Close a session via ACP session/close if the agent supports it.

        Args:
            session_id: The session to close.
        """
        if not self._ensure_capability("supports_session_close", "close_session"):
            return
        try:
            await self._conn.close_session(session_id=session_id)
            logger.info(f"ACP session/close 成功: {session_id[:16]}...")
        except Exception as e:
            logger.warning(f"ACP session/close 失败: {e}")

    async def load_session(self, session_id: str) -> list[dict]:
        """Load an existing session and collect replayed history events.

        Calls ACP session/load, then drains the event collector queue to
        reconstruct the conversation history. Events are merged by role/type:
        consecutive text chunks from the same role are concatenated.

        Auth errors (-32000) propagate to the caller for the interceptor
        chain to handle.

        Args:
            session_id: The session to load. Empty string returns [].

        Returns:
            List of history message dicts with keys: role, type, content, data.
            Returns [] on error or if session/load is not supported.
        """
        if not session_id:
            return []
        if not self._ensure_capability("supports_session_load", "load_session"):
            logger.debug("ACP session/load 不可用")
            return []

        try:
            cwd = self._client_impl._work_dir
            if self._execution_env == "wsl" and cwd:
                cwd = win_to_wsl(cwd)

            # Clear collector before load to only get replay events
            self._collector.clear()

            await asyncio.wait_for(
                self._conn.load_session(session_id=session_id, cwd=cwd or ""), timeout=15
            )
        except Exception as e:
            logger.warning(f"ACP session/load 失败: {e}")
            return []

        self._session_id = session_id
        logger.info(f"ACP session/load 成功: {session_id[:16]}...")

        # Collect replayed history events from collector queue
        history: list[dict] = []
        idle_count = 0
        max_idle = 3  # stop after 3 consecutive empty reads (300ms idle)
        while idle_count < max_idle:
            try:
                event = await asyncio.wait_for(self._collector.events.get(), timeout=0.1)
                idle_count = 0
                if event.type == AgentEventType.TEXT_CHUNK:
                    text = event.data.get("text", "")
                    if text:
                        if history and history[-1].get("role") == "assistant" and history[-1].get("type") == "text":
                            history[-1]["content"] += text
                        else:
                            history.append({"role": "assistant", "type": "text", "content": text})
                elif event.type == AgentEventType.USER_MESSAGE:
                    text = event.data.get("text", "")
                    if text:
                        if history and history[-1].get("role") == "user" and history[-1].get("type") == "text":
                            history[-1]["content"] += text
                        else:
                            history.append({"role": "user", "type": "text", "content": text})
                elif event.type == AgentEventType.THOUGHT_CHUNK:
                    text = event.data.get("text", "")
                    if text:
                        if history and history[-1].get("role") == "assistant" and history[-1].get("type") == "thought":
                            history[-1]["content"] += text
                        else:
                            history.append({"role": "assistant", "type": "thought", "content": text})
                elif event.type == AgentEventType.TOOL_CALL_START:
                    history.append({"role": "assistant", "type": "tool_use", "content": event.data.get("name", ""), "data": event.data})
                elif event.type == AgentEventType.TOOL_CALL_UPDATE:
                    history.append({"role": "assistant", "type": "tool_update", "content": event.data.get("name", ""), "data": event.data})
                elif event.type == AgentEventType.TURN_END:
                    break
            except asyncio.TimeoutError:
                idle_count += 1

        logger.info(f"session/load 回放收集: {len(history)} 条历史消息")
        return history

    async def resume_session(self, session_id: str) -> bool:
        """Resume an existing session without history replay.

        Calls ACP session/resume to restore server-side context. Does NOT
        return history messages — the caller is responsible for serving
        history from local persistence or telling the App to retain its
        local messages.

        Uses the same cwd pattern as load_session. The timeout is kept short
        (5s default) because resume should be fast — no history replay involved.
        If the ACP SDK doesn't expose a resume_session method, catches
        AttributeError and returns False gracefully.

        Args:
            session_id: The session to resume.

        Returns:
            True if resume succeeded, False on error or unsupported.
        """
        logger.debug(
            f"resume_session: session_id={session_id[:16]}..., "
            f"supports_resume={getattr(self._capabilities, 'supports_session_resume', None)}, "
            f"conn={bool(self._conn)}"
        )

        # Guard: capability not supported or no connection
        if not self._ensure_capability("supports_session_resume", "resume_session"):
            return False

        try:
            cwd = self._client_impl._work_dir
            if self._execution_env == "wsl" and cwd:
                cwd = win_to_wsl(cwd)

            logger.debug(f"ACP session/resume 请求: session_id={session_id[:16]}..., cwd={cwd!r}")

            # ACP SDK may not have resume_session yet — catch AttributeError
            await asyncio.wait_for(
                self._conn.resume_session(session_id=session_id, cwd=cwd or ""),
                timeout=5.0,
            )

            self._session_id = session_id
            logger.info(f"ACP session/resume 成功: {session_id[:16]}...")
            return True

        except (AttributeError, asyncio.TimeoutError) as e:
            logger.warning(f"ACP session/resume 失败: session_id={session_id[:16]}..., error={type(e).__name__}: {e}")
            return False
        except Exception as e:
            logger.warning(f"ACP session/resume 失败: session_id={session_id[:16]}..., error={e}")
            return False

    async def logout(self) -> bool:
        """Logout from the current authenticated state.

        Calls ACP logout to invalidate the current credentials. After logout,
        new sessions will require re-authentication. No guarantee about
        behavior of already running sessions.

        Never raises — all errors are logged and swallowed, returning False.
        If the ACP SDK doesn't expose a logout method, catches AttributeError
        and returns False gracefully.

        Returns:
            True if logout succeeded, False on error or unsupported.
        """
        if not self._ensure_connection("logout"):
            return False

        try:
            await self._conn.logout()
            logger.info("ACP logout 成功")
            return True
        except AttributeError:
            # ACP SDK doesn't have logout method yet
            logger.warning("ACP logout 不可用: SDK 未实现 logout 方法")
            return False
        except Exception as e:
            logger.warning(f"ACP logout 失败: {e}")
            return False

    # ── 对话 ──

    # ── Prompt (public + private helpers) ──

    async def prompt(
        self,
        session_id: str,
        content: str,
        images: list[dict] | None = None,
        audio_files: list[dict] | None = None,
        resources: list[dict] | None = None,
    ) -> AsyncGenerator[AgentEvent, None]:
        """Send a prompt with optional multimodal attachments, stream back events.

        Builds ACP ContentBlock array from text + images + audio + resources,
        then starts a prompt task and consumes events from the collector queue
        until TURN_END or task completion.

        Args:
            session_id: Active session to send the prompt to.
            content: Text content of the user message.
            images: Optional list of image dicts with "data" (bytes) and "mime_type".
            audio_files: Optional list of audio dicts with "data" and "mime_type".
            resources: Optional list of resource/resource_link dicts.

        Yields:
            AgentEvent objects (TEXT_CHUNK, TOOL_CALL_START, TURN_END, etc.).
            Always ends with TURN_END, even on error.
        """
        logger.info(f"ACP prompt start: session={session_id}, content={content[:80]}...")
        self._collector.clear()

        prompt_blocks = self._build_prompt_blocks(content, images, audio_files, resources)
        prompt_task = asyncio.create_task(
            self._conn.prompt(session_id=session_id, prompt=prompt_blocks)
        )

        try:
            async for event in self._consume_events(prompt_task):
                yield event
        except Exception as e:
            import traceback
            logger.error(f"ACP prompt error: {e}\n{traceback.format_exc()}")
            self._needs_recovery = True
            yield AgentEvent(type=AgentEventType.ERROR, data={"error": str(e)})
            yield AgentEvent(type=AgentEventType.TURN_END, data={})

    def _build_prompt_blocks(
        self,
        content: str,
        images: list[dict] | None,
        audio_files: list[dict] | None,
        resources: list[dict] | None,
    ) -> list:
        """Build ACP ContentBlock array from text + multimodal attachments.

        Uses official ACP SDK helpers: ``text_block()``, ``image_block()``,
        ``audio_block()``, ``resource_block()``, ``resource_link_block()``.
        Binary data is base64-encoded before passing to SDK.

        Args:
            content: Text content (always included as first block).
            images: Image attachments with "data" (bytes) and "mime_type".
            audio_files: Audio attachments with "data" (bytes/str) and "mime_type".
            resources: Resource/resource_link attachments with "type", "uri", etc.

        Returns:
            List of ACP ContentBlock objects ready for ``conn.prompt()``.
        """
        import base64
        from acp import (
            text_block, image_block, audio_block,
            resource_block, resource_link_block, embedded_text_resource,
        )

        blocks = [text_block(content)]

        if images:
            for img in images:
                data = img["data"]
                mime = img.get("mime_type", "image/png")
                blocks.append(image_block(
                    data=base64.b64encode(data).decode(),
                    mime_type=mime,
                ))

        if audio_files:
            for af in audio_files:
                data = af["data"]
                mime = af.get("mime_type", "audio/wav")
                encoded = base64.b64encode(data).decode() if isinstance(data, bytes) else data
                blocks.append(audio_block(data=encoded, mime_type=mime))

        if resources:
            for res in resources:
                res_type = res.get("type", "")
                if res_type == "resource":
                    resource_contents = embedded_text_resource(
                        uri=res.get("uri", ""),
                        text=res.get("content", ""),
                        mime_type=res.get("mime_type") or None,
                    )
                    blocks.append(resource_block(resource_contents))
                elif res_type == "resource_link":
                    blocks.append(resource_link_block(
                        name=res.get("name", ""),
                        uri=res.get("uri", ""),
                        mime_type=res.get("mime_type") or None,
                    ))

        if len(blocks) > 1:
            logger.info(f"ACP prompt 附件: {len(blocks) - 1} 个 ContentBlock")
        return blocks

    async def _consume_events(self, prompt_task: asyncio.Task) -> AsyncGenerator[AgentEvent, None]:
        """Consume events from the collector queue until TURN_END or task completion.

        Polls the collector queue with 1-second timeout. When the queue is empty
        and the prompt task is done, checks for exceptions. Also detects
        connection loss (reader EOF) and triggers recovery.

        Args:
            prompt_task: The asyncio.Task running ``conn.prompt()``.

        Yields:
            AgentEvent objects. Always ends with TURN_END.
        """
        event_count = 0
        while True:
            try:
                event = await asyncio.wait_for(self._collector.events.get(), timeout=1.0)
                event_count += 1
                if event_count <= 3 or event.type in (AgentEventType.TURN_END, AgentEventType.ERROR):
                    logger.info(f"ACP event #{event_count}: {event.type.value}")
                yield event
                if event.type == AgentEventType.TURN_END:
                    logger.info(f"ACP prompt done: {event_count} events total")
                    return
            except asyncio.TimeoutError:
                if prompt_task.done():
                    for ev in self._handle_task_done(prompt_task, event_count):
                        yield ev
                    return
                if self._is_connection_lost():
                    logger.error("ACP 连接丢失 (reader EOF)")
                    self._needs_recovery = True
                    yield AgentEvent(type=AgentEventType.ERROR, data={"error": "ACP connection lost"})
                    yield AgentEvent(type=AgentEventType.TURN_END, data={})
                    return

    def _handle_task_done(self, prompt_task: asyncio.Task, event_count: int) -> list[AgentEvent]:
        """Handle prompt_task completion: check for exceptions or zero-event anomaly.

        Args:
            prompt_task: The completed asyncio.Task to inspect.
            event_count: Number of events consumed so far (0 = anomaly).

        Returns:
            List of final events to yield (ERROR + TURN_END on exception,
            just TURN_END on normal completion).
        """
        exc = prompt_task.exception()
        if exc:
            import traceback
            tb = ''.join(traceback.format_exception(type(exc), exc, exc.__traceback__))
            logger.error(f"ACP prompt exception: {exc}\n{tb}")
            self._needs_recovery = True
            return [
                AgentEvent(type=AgentEventType.ERROR, data={"error": str(exc)}),
                AgentEvent(type=AgentEventType.TURN_END, data={}),
            ]
        if event_count == 0:
            logger.warning("ACP prompt 返回 0 events，标记需要恢复")
            self._needs_recovery = True
        else:
            logger.info(f"ACP prompt task done (no error), {event_count} events")
        return [AgentEvent(type=AgentEventType.TURN_END, data={})]

    def _is_connection_lost(self) -> bool:
        """Check if the ACP stdio connection has been lost (reader at EOF).

        Returns:
            True if the underlying reader has reached EOF, indicating the
            agent process has exited or the pipe is broken.
        """
        if self._conn and hasattr(self._conn, '_reader'):
            reader = self._conn._reader
            return reader is not None and reader.at_eof()
        return False

    # ── Configuration (public) ──

    async def cancel(self, session_id: str):
        """Cancel ongoing operations for a session.

        Args:
            session_id: The session whose operations should be cancelled.
        """
        if self._conn:
            try:
                await self._conn.cancel(session_id=session_id)
            except Exception as e:
                logger.warning(f"ACP cancel 失败: {e}")

    # ── 配置 ──

    async def set_model(self, session_id: str, model: str):
        """Switch the AI model for a session via ACP set_session_model.

        Args:
            session_id: Target session.
            model: Model identifier string (e.g. "gpt-4", "claude-3-opus").
        """
        if self._conn:
            try:
                await self._conn.set_session_model(model_id=model, session_id=session_id)
            except Exception as e:
                logger.warning(f"ACP set_session_model 失败: {e}")

    async def set_mode(self, session_id: str, mode_id: str):
        """Switch the agent mode for a session via ACP set_session_mode.

        Args:
            session_id: Target session.
            mode_id: Mode identifier (e.g. "code", "ask", "architect").
        """
        if self._conn:
            try:
                await self._conn.set_session_mode(mode_id=mode_id, session_id=session_id)
            except Exception as e:
                logger.warning(f"ACP set_session_mode 失败: {e}")

    async def set_config_option(self, session_id: str, config_id: str, value: str | bool) -> list[dict]:
        """Set a configuration option via ACP set_config_option.

        Per ACP spec, the response contains the complete list of all config
        options with updated values. Returns the serialized list so the caller
        (cli_manager) can push it to the App directly.

        Args:
            session_id: Target session.
            config_id: Config option identifier (e.g. "model", "thinking_level").
            value: New value — string or boolean depending on the option type.

        Returns:
            Updated config options list (serialized dicts), or [] on failure.
        """
        if self._conn:
            try:
                resp = await self._conn.set_config_option(
                    config_id=config_id, session_id=session_id, value=value,
                )
                # ACP spec: response returns full config list
                resp_opts = getattr(resp, "config_options", None)
                if resp_opts:
                    options = serialize_config_options(resp_opts)
                    logger.info(f"set_config_option 响应: {len(options)} 项配置已更新")
                    return options
            except Exception as e:
                logger.warning(f"ACP set_config_option 失败: {e}")
        return []

    def consume_pending_config(self) -> tuple[list[dict] | None, str]:
        """Consume and return pending config data from new_session response.

        Returns the stored configOptions and initial mode, then clears them.
        Called by cli_manager after session creation to push data to the App.

        Returns:
            Tuple of (config_options_list_or_None, initial_mode_id_or_empty).
        """
        opts = self._pending_config_options
        mode = self._pending_initial_mode
        self._pending_config_options = None
        self._pending_initial_mode = ""
        return opts, mode

    # ── 状态 ──

    # ── State (public properties) ──

    @property
    def is_running(self) -> bool:
        return self._conn is not None

    @property
    def is_healthy(self) -> bool:
        """Check if the ACP connection is alive and usable.

        Returns False if: no connection, no process, needs recovery,
        or subprocess has exited (returncode is not None).
        """
        if not self._conn or not self._proc:
            return False
        if self._needs_recovery:
            return False
        # Check if subprocess is still alive
        if hasattr(self._proc, 'returncode') and self._proc.returncode is not None:
            return False
        return True

    def set_permission_policy(self, policy: str):
        self._client_impl._permission_policy = policy

    @property
    def capabilities(self) -> Optional[ProviderCapabilities]:
        return self._capabilities

    # ── 内部方法 ──

    # ── Private: capability parsing ──

    def _parse_capabilities(self, init_result: Any) -> ProviderCapabilities:
        """Parse the ACP initialize response into ProviderCapabilities.

        Extracts agent_info (name, version), agent_capabilities (session,
        prompt, MCP support), and auth_methods from the SDK response object.
        Uses a ``_get()`` helper for safe nested attribute access.

        Args:
            init_result: The InitializeResult from ``conn.initialize()``.

        Returns:
            Fully populated ProviderCapabilities dataclass.
        """
        # Protocol version check
        proto_ver = getattr(init_result, "protocol_version", 1) or 1
        if proto_ver > 1:
            logger.warning(f"ACP 协议版本不匹配: Agent 返回 v{proto_ver}，我们支持 v1，部分功能可能不可用")

        ai = getattr(init_result, "agent_info", None)
        ac = getattr(init_result, "agent_capabilities", None)
        auth_raw = getattr(init_result, "auth_methods", None) or []

        # Helper: safely read a nested attribute chain
        def _get(obj, *attrs, default=False):
            for attr in attrs:
                if obj is None:
                    return default
                obj = getattr(obj, attr, None)
            return bool(obj) if obj is not None else default

        # Agent info
        name = str(getattr(ai, "name", "") or "") if ai else ""
        title = str(getattr(ai, "title", "") or "") if ai else ""
        version = str(getattr(ai, "version", "") or "") if ai else ""

        # Auth methods
        auth_methods = [self._parse_auth_method(m) for m in auth_raw]
        if auth_methods:
            logger.info(f"ACP auth_methods ({len(auth_methods)}): {auth_methods}")

        logger.debug(f"ACP 能力: load={_get(ac, 'load_session')}, list={_get(ac, 'session_capabilities', 'list')}, image={_get(ac, 'prompt_capabilities', 'image')}")

        return ProviderCapabilities(
            name=title or name or self._display_name,
            version=version,
            protocol="acp",
            protocol_version=proto_ver,
            supports_session_load=_get(ac, "load_session"),
            supports_session_list=_get(ac, "session_capabilities", "list"),
            supports_session_close=_get(ac, "session_capabilities", "close"),
            supports_session_fork=_get(ac, "session_capabilities", "fork"),
            supports_session_resume=_get(ac, "session_capabilities", "resume"),
            supports_image=_get(ac, "prompt_capabilities", "image"),
            supports_audio=_get(ac, "prompt_capabilities", "audio"),
            supports_embedded_context=_get(ac, "prompt_capabilities", "embedded_context"),
            supports_mcp_http=_get(ac, "mcp_capabilities", "http"),
            supports_mcp_sse=_get(ac, "mcp_capabilities", "sse"),
            auth_methods=auth_methods,
        )

    @staticmethod
    def _parse_auth_method(m: Any) -> dict:
        """Parse a single ACP auth method object into a plain dict.

        Handles all ACP auth method types: EnvVar (with vars list),
        Terminal, and Agent. Extracts id, name, type, description,
        optional link, and vars with their metadata.

        Args:
            m: ACP auth method SDK object (has attributes like id, name, type, vars).

        Returns:
            Dict with keys: id, name, type, description, and optionally
            link (str) and vars (list of dicts with name, label, secret, optional).
        """
        method: dict = {
            "id": str(getattr(m, "id", "")),
            "name": str(getattr(m, "name", "")),
            "type": str(getattr(m, "type", "")),
            "description": str(getattr(m, "description", "") or ""),
        }
        link = getattr(m, "link", None)
        if link:
            method["link"] = str(link)
        vars_raw = getattr(m, "vars", None)
        if vars_raw and isinstance(vars_raw, list):
            method["vars"] = [
                {
                    "name": str(getattr(v, "name", "")),
                    "label": str(getattr(v, "label", "") or ""),
                    "secret": bool(getattr(v, "secret", True)),
                    "optional": bool(getattr(v, "optional", False)),
                }
                for v in vars_raw
            ]
        return method
