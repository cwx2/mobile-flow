"""WebSocket server (thin orchestration layer).

Module: server/
Responsibility:
    1. Start the WebSocket service and listen for mobile App connections.
    2. Manage client connections (pairing auth, connect / disconnect).
    3. Route incoming messages to the appropriate handler by MessageType.
    4. Watch the working directory for file changes and push events to the App.

Called by:
    - __main__.py creates and starts this server.

Dependencies:
    - handlers/ — message processors, split by domain.
    - services/ — business logic layer.
    - core/EventBus — decoupled event delivery.

Design decisions:
    - CHAT_SEND runs in a background task (asyncio.create_task) so it does not
      block the message loop.  Otherwise permission.response messages cannot be
      processed, causing a deadlock.
    - Simple flows like auth and heartbeat are handled inline rather than in
      separate handler classes.
"""

from __future__ import annotations

import asyncio
import base64
import gc
import json
import os
import secrets
import socket
import sys
from pathlib import Path

import websockets
from loguru import logger
from websockets.server import ServerConnection

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.errors import PayloadValidationError
from mobileflow_protocol.payloads.auth import (
    AuthConnectPayload,
    AuthPairPayload,
    AuthResultPayload,
    AuthSubmitPayload,
)
from mobileflow_protocol.payloads.cli import (
    CliAddPayload,
    CliCommandsPayload,
    CliInstallPayload,
    CliInstallProgressPayload,
    CliInstallResultPayload,
    CliListResultPayload,
    CliRemovePayload,
    CliRetryPayload,
    CliStatusPayload,
    CliSwitchPayload,
    CliUninstallPayload,
    CliUninstallResultPayload,
)
from mobileflow_protocol.payloads.state import (
    ConfigSetPayload,
    ModeSetPayload,
    StatePushPayload,
    StatusPongPayload,
)
from mobileflow_protocol.payloads.chat import (
    ChatErrorPayload,
    ChatReplayResultPayload,
    ChatStreamPayload,
)
from mobileflow_protocol.payloads.file import FileChangedPayload
from mobileflow_protocol.types import MessageType

from ..core.client_scope import ClientScope
from ..core.event_bus import EventBus
from ..core.events import Events
from ..core.scope_manager import ScopeManager
from ..core.identity_resolver import (
    LANIdentityStrategy,
    TunnelIdentityStrategy,
    RelayIdentityStrategy,
)
from ..crypto.crypto_module import CryptoModule
from ..plugins.registry import PluginRegistry
from ..services.cli_manager import CLIManager
from ..services.file_service import FileService
from ..services.hot_reload import HotReloadManager
from ..services.run_config import RunConfigurationExecutor, RunConfigurationStore
from ..services.git_state import GitStateManager
from ..services.refresh_scheduler import RefreshScheduler
from ..services.auto_fetcher import AutoFetcher
from ..services.project_manager import ProjectManager
from ..services.user_config import UserConfigManager
from ..services.wsl_agent_manager import WslAgentManager
from .wsl_proxy import WslProxy
from ..services.project_scanner import ProjectScanner
from ..terminal import TerminalManager
from ..core.config import AgentConfig
from .auth import AuthManager
from .connection_manager import (
    ConnectionMode,
    EncryptedConnection,
    ServerConnectionManager,
    VirtualConnection,
)
from .connection_protocol import ConnectionProtocol
from .handler_registry import HandlerRegistry
from .stream_replay import StreamReplay
from .handlers.chat_handler import ChatHandler
from .handlers.file_handler import FileHandler
from .handlers.permission_handler import PermissionHandler
from .handlers.plugin_handler import PluginHandler
from .handlers.project_handler import ProjectHandler
from .handlers.git_handler import GitHandler
from .handlers.terminal_handler import TerminalHandler
from .handlers.test_panel_handler import TestPanelHandler
from .handlers.run_config_handler import RunConfigHandler
from .interceptors import (
    AuthInterceptor,
    InterceptorChain,
    LogInterceptor,
    MessageContext,
)
from ..utils.i18n import t


from dataclasses import dataclass, field
import time as _time


@dataclass
class ClientInfo:
    """Per-connection metadata stored in WebSocketServer._clients.

    Replaces the bare ConnectionProtocol reference with a structured record
    that carries the connection mode, timestamps, and the actual transport.
    Handlers access the transport via ``client_info.conn`` which implements
    ConnectionProtocol (send() method).

    Attributes:
        conn: The connection adapter (ServerConnection, EncryptedConnection,
            or VirtualConnection). Implements ConnectionProtocol.
        mode: The connection mode this client connected through.
        connected_at: Unix timestamp when the client was registered.
    """

    conn: ConnectionProtocol
    mode: ConnectionMode
    connected_at: float = field(default_factory=_time.time)

    async def send(self, data: str) -> None:
        """Proxy send() to the underlying connection (ConnectionProtocol).

        This allows ClientInfo to be used as a drop-in replacement where
        ConnectionProtocol was expected, maintaining backward compatibility
        with handler signatures that call ws.send().

        Args:
            data: JSON string to send.
        """
        await self.conn.send(data)


class WebSocketServer:
    """Core WebSocket server that wires together services, handlers, and routing.

    Attributes:
        config: Agent configuration.
        auth: Authentication manager for pairing and sessions.
        event_bus: Global event bus for decoupled communication.
        project_manager: Manages project list and switching.
        file_service: File tree, read/write, and search operations.
        cli_manager: AI CLI lifecycle and session management.
        terminal_manager: PTY terminal session management.
        git_service: Git operations on the working directory.
        plugin_registry: Extension discovery and lifecycle.
    """

    def __init__(self, config: AgentConfig, log_buffer=None):
        self.config = config
        self.event_bus = EventBus()
        self._log_buffer = log_buffer
        self._is_wsl_child = config.wsl_child_mode

        # Connection management (needed in all modes)
        self._conn_manager = ServerConnectionManager()
        self._clients: dict[str, ClientInfo] = {}
        self._scopes: dict[str, ClientScope] = {}
        # Per-client stream replay buffers for disconnect recovery.
        # Created alongside the ClientScope, survives scope suspension.
        self._stream_replays: dict[str, StreamReplay] = {}
        self._permission_futures: dict[str, asyncio.Future] = {}
        self._permission_counter = 0

        # CLI + Terminal (needed in all modes)
        self.cli_manager = CLIManager(config, event_bus=self.event_bus)
        self.cli_manager._ws_broadcast = self._broadcast_to_client
        self.terminal_manager = TerminalManager(
            shutdown_timeout=config.lifecycle.terminal_shutdown_timeout,
        )

        if self._is_wsl_child:
            # WSL child mode: stripped-down, only CLI + terminal.
            # No auth (parent Agent handles it), no file/git/project services.
            logger.info("[WSL-Child] 精简模式初始化: 仅 CLI + 终端")
            self.auth = None
            self.project_manager = None
            self.project_scanner = None
            self.file_service = None
            self.git_service = None
            self.git_state = None
            self.refresh_scheduler = None
            self.auto_fetcher = None
            self.plugin_registry = None
        else:
            # Full mode: all services
            self.auth = AuthManager(config)
            self.project_manager = ProjectManager(config)
            self.project_scanner = ProjectScanner(config.project_scanner)
            self.file_service = FileService(config) if config.work_dir else None

            from ..services.git_service import GitService
            self.git_service = GitService(
                config.work_dir,
                command_timeout=config.git.command_timeout,
                discovery_timeout=config.git.discovery_timeout,
            )
            self.git_state = GitStateManager(
                git_service=self.git_service,
                event_bus=self.event_bus,
                status_limit=config.cache.status_limit,
            )
            self.refresh_scheduler = RefreshScheduler(
                git_state=self.git_state,
                file_service=self.file_service,
                operations=self.git_state.operations,
                event_bus=self.event_bus,
                debounce_delay=config.cache.debounce_delay,
                cooldown=config.cache.cooldown,
                auto_refresh=config.cache.auto_refresh,
            )
            self.auto_fetcher = AutoFetcher(
                git_service=self.git_service,
                operations=self.git_state.operations,
                event_bus=self.event_bus,
                enabled=config.cache.auto_fetch,
                period=config.cache.auto_fetch_period,
            )
            self.plugin_registry = PluginRegistry(
                ext_dir=Path.home() / ".mobileflow" / "extensions",
                provider_registry=self.cli_manager.registry,
            )

            # WSL Agent proxy — manages child Agent for WSL CLIs
            self._wsl_manager = WslAgentManager(
                work_dir=config.work_dir,
                port=config.wsl.child_port,
                startup_timeout=config.wsl.startup_timeout,
            )
            self._wsl_proxy = WslProxy(
                self._wsl_manager,
                broadcast_fn=self._broadcast_raw,
            )

        # Scope management (replaces inline _suspended, _scopes, _stream_replays logic)
        if not self._is_wsl_child:
            self.scope_manager = ScopeManager(
                config=config,
                cli_manager=self.cli_manager,
                cleanup_factory=self._register_scope_cleanups,
            )
            self.scope_manager.register_strategy(LANIdentityStrategy(auth_manager=self.auth))
            self.scope_manager.register_strategy(TunnelIdentityStrategy())
            self.scope_manager.register_strategy(RelayIdentityStrategy())
        else:
            # WSL child mode: simplified scope management (no auth, no identity strategies)
            self.scope_manager = ScopeManager(
                config=config,
                cli_manager=self.cli_manager,
                cleanup_factory=self._register_scope_cleanups,
            )

        # Handler instances (some may be None in wsl-child mode)
        self._chat = ChatHandler(self)
        self._terminal = TerminalHandler(self)
        self._permission = PermissionHandler(self)
        self._test_panel = TestPanelHandler(self)

        if not self._is_wsl_child:
            self._file = FileHandler(self)
            self._project = ProjectHandler(self)
            self._git = GitHandler(self)
            self._plugin = PluginHandler(self)
            self._permission.register_events()
            self.event_bus.on("state.changed", self._on_state_changed)
            self.event_bus.on("git.op.start", self._on_git_op_progress)
            self.event_bus.on("git.op.done", self._on_git_op_progress)
            self.event_bus.on(Events.CLI_COMMANDS_AVAILABLE, self._on_cli_commands_available)

            # Run Configuration system (store + executor + handler)
            self._run_config_store = RunConfigurationStore(config.work_dir or "")
            self._run_config_executor = RunConfigurationExecutor(config, self._test_panel.port_proxy)
            self._run_config = RunConfigHandler(
                self, self._run_config_store, self._run_config_executor,
            )
        else:
            self._file = None
            self._project = None
            self._git = None
            self._plugin = None
            self._run_config = None

        # Handler registry
        self._registry = HandlerRegistry()
        self._register_handlers()

        # Interceptor chain for cross-cutting concerns
        if self._is_wsl_child:
            # WSL child: no auth interceptor (parent handles auth).
            # Security assumption: child Agent only listens on localhost,
            # so only the parent Agent on the same machine can connect.
            # If WSL2 remote IP support is added later, auth must be added.
            self._interceptor_chain = InterceptorChain([
                LogInterceptor(),
            ])
        else:
            self._interceptor_chain = InterceptorChain([
                LogInterceptor(),
                AuthInterceptor(self),
            ])

        # Background task references
        self._file_watcher_task: asyncio.Task | None = None
        self._last_progress_busy: bool = False

        # Hot reload manager for Tunnel/Relay mode lifecycle
        self.hot_reload = HotReloadManager(self)
        # User config manager for Dashboard-editable settings
        self.user_config = UserConfigManager()

    @property
    def client_count(self) -> int:
        """Number of currently connected clients (thread-safe read)."""
        return len(self._clients)

    async def shutdown(self):
        """Gracefully shut down the server and all managed resources.

        Shutdown sequence (by dependency order, outer → inner):
        1. Cancel file watcher task (stop monitoring filesystem).
        2. Close all WebSocket client connections (notify App).
        3. Stop all terminal PTY sessions (kill shell processes).
        4. Clean up all CLI providers (close ACP sessions, kill CLI processes).
        5. Shut down plugin registry.

        Each step has a timeout from config.lifecycle to prevent hanging.
        Steps that fail or timeout are logged and skipped — the shutdown
        continues regardless so the Agent process can exit cleanly.
        """
        logger.info("🧹 Agent 开始优雅关闭...")
        lifecycle = self.config.lifecycle

        # 1. Cancel file watcher
        if self._file_watcher_task and not self._file_watcher_task.done():
            self._file_watcher_task.cancel()
            try:
                await self._file_watcher_task
            except asyncio.CancelledError:
                pass
            logger.debug("文件监听已停止")

        # 2. Close all WebSocket connections
        for client_id, client_info in list(self._clients.items()):
            try:
                conn = client_info.conn
                if hasattr(conn, 'close'):
                    await asyncio.wait_for(conn.close(), timeout=3)
            except Exception:
                pass
        self._clients.clear()
        logger.debug("所有 WebSocket 连接已关闭")

        # 2.5. Dispose all client scopes via ScopeManager
        # (handles both active and suspended scopes, cancels grace timers)
        await self.scope_manager.dispose_all()
        self._scopes.clear()

        # 3. Stop all terminal sessions
        #    Defensive: scope.dispose() already stops terminals for connected
        #    clients, but this catches any sessions not bound to a scope
        #    (e.g. created before auth completed).
        try:
            await asyncio.wait_for(
                self.terminal_manager.stop_all(),
                timeout=lifecycle.terminal_shutdown_timeout * 2,
            )
        except asyncio.TimeoutError:
            logger.warning("终端会话关闭超时")
        except Exception as e:
            logger.warning(f"终端会话关闭出错: {e}")

        # 4. Clean up all CLI providers
        #    Defensive: scope.dispose() already cleans up CLI for connected
        #    clients, but this catches any providers not bound to a scope.
        try:
            await asyncio.wait_for(
                self.cli_manager.cleanup_all(),
                timeout=lifecycle.shutdown_total_timeout,
            )
        except asyncio.TimeoutError:
            logger.warning("CLI 清理超时")
        except Exception as e:
            logger.warning(f"CLI 清理出错: {e}")

        # 5. Dispose refresh scheduler and git state throttlers
        #    These may have pending async tasks that block event loop exit.
        if self.refresh_scheduler:
            self.refresh_scheduler.dispose()
        if self.git_state:
            self.git_state.dispose()

        # 6. Plugin cleanup (skip in wsl-child mode)
        if not self._is_wsl_child and self.plugin_registry:
            try:
                self.plugin_registry.shutdown()
            except Exception as e:
                logger.debug(f"插件清理出错（可忽略）: {e}")

        # 6.5. Run Configuration executor cleanup (stop all running configs)
        run_config_executor = getattr(self, '_run_config_executor', None)
        if run_config_executor:
            try:
                await run_config_executor.cleanup()
            except Exception as e:
                logger.debug(f"运行配置清理出错（可忽略）: {e}")

        # 7. WSL proxy cleanup (stop child Agent)
        wsl_proxy = getattr(self, '_wsl_proxy', None)
        if wsl_proxy:
            try:
                await wsl_proxy.shutdown()
            except Exception as e:
                logger.debug(f"WSL 代理清理出错（可忽略）: {e}")

        # 8. Suppress noisy asyncio cleanup warnings on Windows.
        #    ProactorEventLoop's pipe transports print "I/O operation on
        #    closed pipe" errors in __del__ during garbage collection.
        #    These are harmless but confuse users. Redirect stderr briefly
        #    to suppress them, then force garbage collection while stderr
        #    is silenced.
        await asyncio.sleep(0.1)
        if sys.platform == "win32":
            old_stderr = sys.stderr
            try:
                sys.stderr = open(os.devnull, 'w')
                gc.collect()
                await asyncio.sleep(0.05)
            finally:
                sys.stderr.close()
                sys.stderr = old_stderr

        logger.info("✅ Agent 已优雅关闭")

    async def start(self):
        """Start the WebSocket server using the configured connection mode.

        In full mode: ensure password, init plugins, detect CLIs, start
        file watcher, init git cache, then start WebSocket server.

        In wsl-child mode: detect CLIs only, then start WebSocket server.
        No auth, no file watcher, no git, no plugins.
        """
        if getattr(self, '_is_wsl_child', False):
            # WSL child: minimal startup
            logger.info("[WSL-Child] 启动精简模式...")
            await self.cli_manager.detect_all()
            available = self.cli_manager.registry.list_available()
            if not self.config.default_cli or self.config.default_cli not in available:
                self.config.default_cli = available[0] if available else ""
            logger.info(f"[WSL-Child] 可用 CLI: {', '.join(available) or '无'}")
        else:
            # Full mode: complete startup sequence
            pair_token, is_new = self.auth.ensure_pair_token()
            self._print_connect_info(pair_token, show_password=is_new)
            self.plugin_registry.initialize()
            await self.cli_manager.detect_all()
            available = self.cli_manager.registry.list_available()
            if not self.config.default_cli or self.config.default_cli not in available:
                self.config.default_cli = available[0] if available else ""
            self._file_watcher_task = asyncio.create_task(self._watch_files())

            # Initialize git state cache (first full refresh)
            if self.config.work_dir:
                try:
                    await self.git_state.initialize()
                    logger.info("✅ Git 状态缓存已初始化")
                    self.auto_fetcher.start()
                except Exception as e:
                    logger.warning(f"Git 状态缓存初始化失败（非致命）: {e}")

            # Load run configurations from disk
            if self.config.work_dir:
                try:
                    self._run_config_store.load()
                    logger.info("✅ 运行配置已加载")
                except Exception as e:
                    logger.warning(f"运行配置加载失败（非致命）: {e}")

        mode = self.config.connection_mode
        ws_cfg = self.config.websocket
        conn_cfg = self.config.connection

        # Multi-mode parallel: start all available connection modes concurrently.
        # If connection_mode is explicitly set (legacy), only start that mode.
        # Otherwise, start all modes that have valid configuration.
        if mode and mode != "auto":
            # Legacy single-mode behavior (backward compatible)
            await self._start_single_mode(mode, ws_cfg, conn_cfg)
        else:
            # Auto mode: start all available modes in parallel
            await self._start_all_modes(ws_cfg, conn_cfg)

    async def _start_single_mode(self, mode: str, ws_cfg, conn_cfg):
        """Start a single connection mode (legacy behavior)."""
        if mode == "relay":
            await self._start_relay_mode(conn_cfg)
        elif mode == "tunnel":
            await self._start_tunnel_mode(ws_cfg)
        else:
            await self._start_lan_mode(ws_cfg)

    async def _start_all_modes(self, ws_cfg, conn_cfg):
        """Start all available connection modes in parallel.

        - LAN: always starts (port from config.port)
        - Tunnel: starts if TLS cert + key files exist on disk (port from config.tunnel_port)
        - Relay: starts if relay_url is configured

        Registers Tunnel and Relay tasks with HotReloadManager for
        later hot-reload via Dashboard config changes.
        """
        tasks = []

        # LAN mode: always available
        tasks.append(self._start_lan_mode(ws_cfg))
        # Set LAN status immediately (it will start successfully)
        self.hot_reload.set_lan_active(self.config.host, self.config.port)

        # Tunnel mode: only if TLS certificate files actually exist on disk
        if self.config.tunnel_tls_cert and self.config.tunnel_tls_key:
            from pathlib import Path
            cert_exists = Path(self.config.tunnel_tls_cert).is_file()
            key_exists = Path(self.config.tunnel_tls_key).is_file()
            if cert_exists and key_exists:
                tunnel_task = asyncio.create_task(self._start_tunnel_mode(ws_cfg))
                self.hot_reload.register_tunnel_task(tunnel_task)
                self.hot_reload.set_tunnel_active(self.config.tunnel_port)
                tasks.append(tunnel_task)
            else:
                missing = []
                if not cert_exists:
                    missing.append(f"cert={self.config.tunnel_tls_cert}")
                if not key_exists:
                    missing.append(f"key={self.config.tunnel_tls_key}")
                logger.warning(f"📡 Tunnel 模式跳过（证书文件不存在）: {', '.join(missing)}")
        else:
            logger.info("📡 Tunnel 模式未启动（未配置 TLS 证书）")

        # Relay mode: only if relay_url is configured
        if self.config.relay_url:
            relay_task = asyncio.create_task(self._start_relay_mode(conn_cfg))
            self.hot_reload.register_relay_task(relay_task)
            self.hot_reload.set_relay_active(self.config.relay_url)
            tasks.append(relay_task)
        else:
            logger.info("📡 Relay 模式未启动（未配置 relay_url）")

        # Wait for LAN (the only non-task item) — gather handles both
        # raw coroutines and tasks
        await asyncio.gather(*tasks)

    async def _start_lan_mode(self, ws_cfg):
        """Start the LAN WebSocket server."""
        logger.info(f"📡 WebSocket 监听 ws://{self.config.host}:{self.config.port}")
        logger.info(f"🌐 Dashboard http://localhost:{self.config.port}")
        dashboard_handler = self._create_dashboard_handler()
        await self._conn_manager.start_lan(
            host=self.config.host,
            port=self.config.port,
            handler=self._handle_connection,
            max_size=ws_cfg.max_message_size_mb * 1024 * 1024,
            ping_interval=ws_cfg.ping_interval,
            ping_timeout=ws_cfg.ping_timeout,
            close_timeout=ws_cfg.close_timeout,
            process_request=dashboard_handler,
        )

    async def _start_tunnel_mode(self, ws_cfg):
        """Start the Tunnel WSS server."""
        tunnel_port = self.config.tunnel_port
        logger.info(f"📡 Tunnel 模式启动: wss://{self.config.host}:{tunnel_port}")
        ssl_context = self._build_ssl_context()
        await self._conn_manager.start_tunnel(
            host=self.config.host,
            port=tunnel_port,
            handler=self._handle_connection,
            bearer_token=self.config.tunnel_bearer_token,
            ssl_context=ssl_context,
            max_size=ws_cfg.max_message_size_mb * 1024 * 1024,
        )

    async def _start_relay_mode(self, conn_cfg):
        """Start the Relay client connection."""
        logger.info(f"📡 Relay 模式启动: relay_url={self.config.relay_url}")
        device_id = self.config.ensure_device_id()
        relay_secret = CryptoModule.generate_secret()
        crypto = CryptoModule(relay_secret)

        from ..crypto.relay_pairing import encode_relay_pairing

        device_id_bytes = (
            bytes.fromhex(device_id)
            if len(device_id) == 32
            else device_id.encode("utf-8")[:16].ljust(16, b"\x00")
        )
        pairing_code = encode_relay_pairing(
            relay_url=self.config.relay_url,
            device_id=device_id_bytes,
            shared_secret=relay_secret,
        )
        logger.info(f"🔗 Relay 配对码: {pairing_code}")

        try:
            import qrcode
            qr = qrcode.QRCode(border=1)
            qr.add_data(pairing_code)
            qr.print_ascii(invert=True)
        except ImportError:
            logger.info("📱 安装 qrcode 包可显示 QR 码: pip install qrcode")

        await self._conn_manager.start_relay(
            relay_url=self.config.relay_url,
            device_id=device_id,
            crypto=crypto,
            on_raw_message=self._handle_relay_message,
            max_attempts=conn_cfg.relay_reconnect_max_attempts,
            initial_delay=conn_cfg.relay_reconnect_initial_delay,
            max_delay=conn_cfg.relay_reconnect_max_delay,
        )

    def _build_ssl_context(self):
        """Build an SSL context for Tunnel mode from config paths.

        Reads ``tunnel_tls_cert`` and ``tunnel_tls_key`` from AgentConfig.
        Returns None if either path is empty or the files don't exist.

        Returns:
            An ``ssl.SSLContext`` configured with the cert/key, or None.
        """
        import ssl
        cert_path = self.config.tunnel_tls_cert
        key_path = self.config.tunnel_tls_key
        if not cert_path or not key_path:
            logger.warning("Tunnel TLS 证书/密钥路径未配置，使用无 TLS 模式")
            return None
        try:
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ctx.load_cert_chain(cert_path, key_path)
            logger.info(f"Tunnel TLS 上下文已加载: cert={cert_path}")
            return ctx
        except Exception as e:
            logger.error(f"Tunnel TLS 上下文加载失败: {e}")
            return None

    def _create_dashboard_handler(self):
        """Create the HTTP request handler for the web dashboard.

        Returns a process_request callback that serves the dashboard
        SPA and API endpoints for non-WebSocket HTTP requests.
        """
        import socket as _socket
        from .dashboard_api import create_dashboard_handler

        def _get_status():
            return {
                "connected_clients": len(self._clients),
                "version": self._get_version(),
                "port": self.config.port,
                "work_dir": self.config.work_dir,
                "project_name": Path(self.config.work_dir).name if self.config.work_dir else "",
                "default_cli": self.config.default_cli,
                "active_modes": [m.value for m in self._conn_manager.active_modes],
            }

        def _get_connect_info():
            token, _ = self.auth.ensure_pair_token()
            try:
                s = _socket.socket(_socket.AF_INET, _socket.SOCK_DGRAM)
                s.connect(("8.8.8.8", 80))
                host = s.getsockname()[0]
                s.close()
            except Exception:
                host = "127.0.0.1"
            return {
                "host": host,
                "port": self.config.port,
                "password": token,
            }

        def _get_cli_list():
            adapters = self.cli_manager.list_adapters()
            result = []
            for a in adapters:
                result.append({
                    "name": a.name,
                    "display_name": a.display_name,
                    "installed": a.installed,
                    "can_install": a.can_install,
                    "install_hint": a.install_hint or "",
                })
            return result

        async def _install_cli(name: str) -> dict:
            return await self.cli_manager.registry.install_agent(name)

        async def _uninstall_cli(name: str) -> dict:
            return await self.cli_manager.registry.uninstall_agent(name)

        async def _test_cli(name: str) -> dict:
            """Test if a CLI is accessible by running env_check."""
            provider = self.cli_manager.registry.get_provider(name)
            if not provider:
                return {"success": False, "message": t("backend.cliNotFound", name=name)}
            try:
                ok, err = await provider.env_check()
                return {"success": ok, "message": err or t("backend.connectionSuccess")}
            except Exception as e:
                return {"success": False, "message": str(e)}

        async def _detect_cli():
            await self.cli_manager.detect_all()

        def _get_api_keys() -> list[dict]:
            """Get configured API keys (masked) from environment."""
            keys = []
            for name in ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GOOGLE_API_KEY", "CODEX_API_KEY"]:
                val = os.environ.get(name, "")
                if val:
                    masked = val[:4] + "****" + val[-4:] if len(val) > 8 else "****"
                    keys.append({"name": name, "value": masked, "configured": True})
                else:
                    keys.append({"name": name, "value": "", "configured": False})
            return keys

        def _save_api_key(name: str, value: str) -> bool:
            """Save an API key to the environment and .env file."""
            os.environ[name] = value
            # Also persist to .env file
            from pathlib import Path
            env_path = Path(self.config.data_dir) / ".env"
            try:
                lines = []
                found = False
                if env_path.exists():
                    lines = env_path.read_text(encoding="utf-8").splitlines()
                    for i, line in enumerate(lines):
                        if line.startswith(f"{name}="):
                            lines[i] = f"{name}={value}"
                            found = True
                            break
                if not found:
                    lines.append(f"{name}={value}")
                env_path.parent.mkdir(parents=True, exist_ok=True)
                env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
                logger.info(f"API Key 已保存: {name}")
                return True
            except Exception as e:
                logger.warning(f"API Key 保存失败: {e}")
                return False

        def _reset_password() -> str:
            """Reset the connection password."""
            token = self.auth.reset_pair_token()
            return token

        return create_dashboard_handler(
            get_status=_get_status,
            get_connect_info=_get_connect_info,
            get_cli_list=_get_cli_list,
            install_cli=_install_cli,
            uninstall_cli=_uninstall_cli,
            test_cli=_test_cli,
            detect_cli=_detect_cli,
            add_cli=lambda name, command, args, display_name: self.cli_manager.registry.add_custom_agent(name, command, args, display_name),
            remove_cli=lambda name: self.cli_manager.registry.remove_custom_agent(name),
            get_api_keys=_get_api_keys,
            save_api_key=_save_api_key,
            reset_password=_reset_password,
            get_logs=lambda since=0: self._log_buffer.since(since) if self._log_buffer else [],
            list_projects=lambda: self.project_manager.list_projects() if self.project_manager else [],
            add_project=lambda path, name: self.project_manager.add_project(path, name) if self.project_manager else False,
            switch_project=lambda path: self._dashboard_switch_project(path),
            remove_project=lambda path: self.project_manager.remove_project(path) if self.project_manager else False,
            browse_directory=lambda path: self.project_scanner.list_directory(path) if self.project_scanner else [],
            port_proxy=self._test_panel.port_proxy,
            run_config_store=getattr(self, '_run_config_store', None),
            run_config_executor=getattr(self, '_run_config_executor', None),
            user_config_manager=getattr(self, 'user_config', None),
            hot_reload_manager=getattr(self, 'hot_reload', None),
        )

    def _dashboard_switch_project(self, path: str) -> None:
        """Switch project from Dashboard HTTP API.

        Calls project_manager.switch_project and rebuilds dependent services
        (FileService, GitService). Does not send WebSocket notifications since
        this is an HTTP request — connected App clients will pick up the change
        on their next status poll or reconnect.

        Args:
            path: Absolute path to the project directory.
        """
        if not self.project_manager:
            return
        self.project_manager.switch_project(path)
        self.project_manager.apply_current(self)

    def _get_version(self) -> str:
        """Get the Agent version string."""
        try:
            from importlib.metadata import version
            return version("mobileflow-agent")
        except Exception:
            return "dev"

    # ── Connection management ──

    async def _handle_connection(self, websocket: ServerConnection):
        """Handle a single WebSocket client lifecycle (connect → messages → disconnect).

        Each connection is tagged with its mode by the ConnectionManager's handler
        wrapper (ws._mf_connection_mode). This tag is used to determine pre-auth
        behavior and is stored in ClientInfo for the connection's lifetime.

        For LAN mode, incoming messages may be encrypted after pairing. The
        ``decrypt_if_needed`` call transparently handles both plaintext
        (pre-pairing) and ciphertext (post-pairing) messages.

        Args:
            websocket: The incoming WebSocket connection (tagged with _mf_connection_mode).
        """
        client_id = secrets.token_hex(6)

        # Read connection mode from the tag set by ConnectionManager's handler wrapper.
        # WSL child mode overrides the transport-level tag.
        if getattr(self, '_is_wsl_child', False):
            conn_mode = ConnectionMode.LAN  # WSL child uses LAN semantics
        else:
            conn_mode = getattr(websocket, '_mf_connection_mode', ConnectionMode.LAN)

        logger.info(f"📱 新连接: {client_id}, mode={conn_mode.value}")

        # Pre-auth registration: modes where authentication happens BEFORE
        # the WebSocket connection is established (Bearer Token at HTTP level,
        # or trusted localhost). These skip the auth.pair/auth.connect handshake
        # and register the client + initialize CLI immediately.
        if getattr(self, '_is_wsl_child', False):
            self._clients[client_id] = ClientInfo(conn=websocket, mode=conn_mode)
            await self._register_preauthenticated_client(client_id, conn_mode)
        elif conn_mode == ConnectionMode.TUNNEL:
            self._clients[client_id] = ClientInfo(conn=websocket, mode=conn_mode)
            bearer = self.config.tunnel_bearer_token
            await self._register_preauthenticated_client(
                client_id, conn_mode, {"bearer_token": bearer} if bearer else None
            )
            logger.info(f"Tunnel 客户端已认证（Bearer Token）: {client_id}")

        try:
            async for raw in websocket:
                try:
                    # Decrypt if LAN encryption is active for this client
                    plaintext = self._conn_manager.decrypt_if_needed(client_id, raw)
                    msg = Message(**json.loads(plaintext))
                    await self._route(client_id, websocket, msg)
                except json.JSONDecodeError:
                    logger.warning(f"无效 JSON: {str(raw)[:100]}")
                except PayloadValidationError as e:
                    logger.warning(f"消息 payload 校验失败: client={client_id}, {e}")
                except Exception as e:
                    logger.error(f"处理消息出错: client={client_id}, error={e}", exc_info=True)
                    # Best-effort error response — don't let send failure crash the loop
                    try:
                        await websocket.send(Message.from_typed(
                            type=MessageType.CHAT_ERROR,
                            payload=ChatErrorPayload(error=t("backend.internalError")),
                        ).model_dump_json())
                    except Exception:
                        pass
        except websockets.ConnectionClosed as e:
            logger.info(f"Connection closed: {client_id} code={e.code} reason={e.reason}")
        finally:
            self._clients.pop(client_id, None)
            logger.info(f"📱 客户端断开: {client_id}, mode={conn_mode.value}")
            await self.scope_manager.unregister_client(client_id)

    async def _route(self, client_id: str, ws: ConnectionProtocol, msg: Message):
        """Route an incoming message through the interceptor chain.

        If the WSL proxy is active and the message type is CLI-related,
        forwards it to the WSL child Agent instead of handling locally.

        Args:
            client_id: Unique identifier of the sending client.
            ws: The client's connection.
            msg: The parsed protocol message.
        """
        # WSL proxy: forward CLI-related messages to child Agent
        msg_type_str = msg.type.value if hasattr(msg.type, 'value') else str(msg.type)
        wsl_proxy = getattr(self, '_wsl_proxy', None)
        if wsl_proxy and wsl_proxy.should_forward(msg_type_str):
            await wsl_proxy.forward(msg)
            return

        entry = self._registry.get(msg.type)
        if not entry:
            logger.warning(f"未知消息类型: {msg.type}")
            return

        ctx = MessageContext(
            client_id=client_id,
            ws=ws,
            msg=msg,
            handler_name=msg_type_str,
            requires_cli=entry.requires_cli,
            requires_project=entry.requires_project,
            is_background=entry.is_background,
            metadata={"_connection_mode": self._get_client_mode(client_id).value},
        )

        if entry.is_background:
            asyncio.create_task(
                self._interceptor_chain.execute(ctx, entry.handler)
            )
        else:
            await self._interceptor_chain.execute(ctx, entry.handler)

    # ── Handler registration ──

    def _register_handlers(self):
        """Register all message handlers with their metadata flags.

        requires_cli=True: handler needs an active CLI provider.
            AuthInterceptor checks auth state before dispatch.
        requires_project=True: handler needs a selected project (non-empty
            work_dir). AuthInterceptor rejects the request when no project
            is active.
        is_background=True: handler runs in asyncio.create_task
            to avoid blocking the message loop.

        Handlers that do NOT require CLI (requires_cli=False):
            - auth.pair, auth.connect: WebSocket auth, no CLI involved
            - cli.list, cli.switch, cli.install, cli.add, cli.remove: CLI management
            - cli.retry: re-initializes CLI, handles its own auth
            - auth.submit: delivers credentials, must never be blocked by auth check
            - status.ping: heartbeat
            - permission.response: permission callback, must not be blocked
            - file.*, git.*, terminal.*: local ops (no ACP, but require project)
            - project.*: project management (manages projects themselves)
            - plugin.*: plugin management

        Handlers that DO require CLI (requires_cli=True):
            - chat.send: sends prompt to AI CLI
            - chat.cancel: cancels AI operation
            - chat.history: loads session history from CLI
            - session.list, session.new, session.switch: session management
            - mode.set, config.set: ACP session configuration

        Handlers that DO require project (requires_project=True):
            - file.*: file operations need a working directory
            - git.*: git operations need a working directory
            - terminal.*: terminal sessions need a working directory
            - chat.*, session.*: AI operations need a project context
        """
        r = self._registry

        # Auth (no CLI needed)
        r.register(MessageType.AUTH_PAIR, self._handle_auth_pair)
        r.register(MessageType.AUTH_CONNECT, self._handle_auth_connect)

        # Chat (requires CLI, chat.send is background)
        r.register(MessageType.CHAT_SEND, self._chat.handle_chat_send,
                   requires_cli=True, requires_project=True, is_background=True)
        r.register(MessageType.CHAT_CANCEL, self._chat.handle_chat_cancel,
                   requires_cli=True, requires_project=True)
        # chat.history reads local files — does NOT need CLI provider ready
        r.register(MessageType.CHAT_HISTORY, self._chat.handle_chat_history,
                   requires_project=True)
        r.register(MessageType.CHAT_HISTORY_MORE, self._chat.handle_chat_history_more,
                   requires_project=True)
        # chat.replay — reconnect recovery, replays buffered stream chunks
        r.register(MessageType.CHAT_REPLAY, self._chat.handle_chat_replay,
                   requires_project=True)

        # Session management — list/new/switch read/write local data
        r.register(MessageType.SESSION_LIST, self._chat.handle_session_list,
                   requires_project=True)
        r.register(MessageType.SESSION_NEW, self._chat.handle_session_new,
                   requires_cli=True, requires_project=True)
        r.register(MessageType.SESSION_SWITCH, self._chat.handle_session_switch,
                   requires_cli=True, requires_project=True)
        r.register(MessageType.SESSION_CLOSE, self._chat.handle_session_close,
                   requires_cli=True, requires_project=True)

        # File operations (local, no CLI — requires project)
        # Skipped in wsl-child mode (parent Agent handles file operations)
        if not self._is_wsl_child:
            r.register(MessageType.FILE_TREE, self._file.handle_file_tree,
                       requires_project=True)
            r.register(MessageType.FILE_READ, self._file.handle_file_read,
                       requires_project=True)
            r.register(MessageType.FILE_WRITE, self._file.handle_file_write,
                       requires_project=True)
            r.register(MessageType.FILE_SEARCH, self._file.handle_file_search,
                       requires_project=True)
            r.register(MessageType.FILE_CREATE, self._file.handle_file_create,
                       requires_project=True)
            r.register(MessageType.FILE_RENAME, self._file.handle_file_rename,
                       requires_project=True)
            r.register(MessageType.FILE_DELETE, self._file.handle_file_delete,
                       requires_project=True)
            r.register(MessageType.DIFF_APPLY, self._file.handle_diff_apply,
                       requires_project=True)
            r.register(MessageType.DIFF_REJECT, self._file.handle_diff_reject,
                       requires_project=True)

        # Project (local, no CLI)
        # Skipped in wsl-child mode (parent Agent handles project management)
        if not self._is_wsl_child:
            r.register(MessageType.PROJECT_LIST, self._project.handle_project_list)
            r.register(MessageType.PROJECT_ADD, self._project.handle_project_add)
            r.register(MessageType.PROJECT_REMOVE, self._project.handle_project_remove)
            r.register(MessageType.PROJECT_SWITCH, self._project.handle_project_switch)
            r.register(MessageType.PROJECT_CURRENT, self._project.handle_project_current)
            r.register(MessageType.PROJECT_SEARCH, self._project.handle_project_search)

        # Terminal (local PTY, no CLI — requires project)
        r.register(MessageType.TERMINAL_START, self._terminal.handle_terminal_start,
                   requires_project=True)
        r.register(MessageType.TERMINAL_INPUT, self._terminal.handle_terminal_input,
                   requires_project=True)
        r.register(MessageType.TERMINAL_RESIZE, self._terminal.handle_terminal_resize,
                   requires_project=True)
        r.register(MessageType.TERMINAL_STOP, self._terminal.handle_terminal_stop,
                   requires_project=True)

        # Test Panel — script execution (local subprocess, no CLI — requires project)
        r.register(MessageType.SCRIPT_RUN, self._test_panel.handle_script_run,
                   requires_project=True, is_background=True)
        r.register(MessageType.SCRIPT_STOP, self._test_panel.handle_script_stop,
                   requires_project=True)

        # Test Panel — preview management (port proxy + dev server)
        r.register(MessageType.PREVIEW_START, self._test_panel.handle_preview_start,
                   requires_project=True, is_background=True)
        r.register(MessageType.PREVIEW_STOP, self._test_panel.handle_preview_stop,
                   requires_project=True)

        # Test Panel — API proxy (HTTP request forwarding)
        r.register(MessageType.API_REQUEST, self._test_panel.handle_api_request,
                   requires_project=True, is_background=True)

        # Test Panel — screenshot and visual diff (optional Playwright)
        r.register(MessageType.SCREENSHOT_CAPTURE, self._test_panel.handle_screenshot_capture,
                   requires_project=True, is_background=True)
        r.register(MessageType.VISUAL_DIFF_START, self._test_panel.handle_visual_diff_start,
                   requires_project=True, is_background=True)
        r.register(MessageType.VISUAL_DIFF_COMPARE, self._test_panel.handle_visual_diff_compare,
                   requires_project=True, is_background=True)

        # Test Panel — plugin queries (smart suggestions)
        r.register(MessageType.PREVIEW_DETECT, self._test_panel.handle_preview_detect,
                   requires_project=True)
        r.register(MessageType.RUNTIME_RESOLVE, self._test_panel.handle_runtime_resolve,
                   requires_project=True)

        # Run Configuration — CRUD and execution (requires project)
        # Skipped in wsl-child mode (parent Agent handles run configurations)
        if not self._is_wsl_child:
            r.register(MessageType.RUN_CONFIG_LIST, self._run_config.handle_run_config_list,
                       requires_project=True)
            r.register(MessageType.RUN_CONFIG_CREATE, self._run_config.handle_run_config_create,
                       requires_project=True)
            r.register(MessageType.RUN_CONFIG_UPDATE, self._run_config.handle_run_config_update,
                       requires_project=True)
            r.register(MessageType.RUN_CONFIG_DELETE, self._run_config.handle_run_config_delete,
                       requires_project=True)
            r.register(MessageType.RUN_CONFIG_SELECT, self._run_config.handle_run_config_select,
                       requires_project=True)
            r.register(MessageType.RUN_CONFIG_START, self._run_config.handle_run_config_start,
                       requires_project=True, is_background=True)
            r.register(MessageType.RUN_CONFIG_STOP, self._run_config.handle_run_config_stop,
                       requires_project=True)
            r.register(MessageType.RUN_CONFIG_RESTART, self._run_config.handle_run_config_restart,
                       requires_project=True, is_background=True)
            r.register(MessageType.RUN_CONFIG_STATUS, self._run_config.handle_run_config_status,
                       requires_project=True)

        # Permission (callback, must not be blocked)
        r.register(MessageType.PERMISSION_RESPONSE, self._permission.handle_permission_response)

        # Git (local, no CLI — requires project)
        # Skipped in wsl-child mode (parent Agent handles git operations)
        if not self._is_wsl_child:
            r.register(MessageType.GIT_STATUS, self._git.handle_git_status,
                       requires_project=True)
            r.register(MessageType.GIT_DIFF, self._git.handle_git_diff,
                       requires_project=True)
            r.register(MessageType.GIT_STAGE, self._git.handle_git_stage,
                       requires_project=True)
            r.register(MessageType.GIT_UNSTAGE, self._git.handle_git_unstage,
                       requires_project=True)
            r.register(MessageType.GIT_COMMIT, self._git.handle_git_commit,
                       requires_project=True)
            r.register(MessageType.GIT_PUSH, self._git.handle_git_push,
                       requires_project=True)
            r.register(MessageType.GIT_PULL, self._git.handle_git_pull,
                       requires_project=True)
            r.register(MessageType.GIT_BRANCHES, self._git.handle_git_branches,
                       requires_project=True)
            r.register(MessageType.GIT_CHECKOUT, self._git.handle_git_checkout,
                       requires_project=True)
            r.register(MessageType.GIT_LOG, self._git.handle_git_log,
                       requires_project=True)
            r.register(MessageType.GIT_LOG_SEARCH, self._git.handle_git_log_search,
                       requires_project=True)
            r.register(MessageType.GIT_LOG_AUTHORS, self._git.handle_git_log_authors,
                       requires_project=True)
            r.register(MessageType.GIT_SHOW, self._git.handle_git_show,
                       requires_project=True)
            r.register(MessageType.GIT_DIFF_COMMIT, self._git.handle_git_diff_commit,
                       requires_project=True)
            r.register(MessageType.GIT_DISCARD, self._git.handle_git_discard,
                       requires_project=True)
            r.register(MessageType.GIT_REPOS, self._git.handle_git_repos,
                       requires_project=True)
            r.register(MessageType.GIT_SWITCH_REPO, self._git.handle_git_switch_repo,
                       requires_project=True)
            r.register(MessageType.GIT_EXEC, self._git.handle_git_exec,
                       requires_project=True)

        # CLI management (no CLI auth needed — these manage CLI lifecycle)
        r.register(MessageType.CLI_LIST, self._handle_cli_list)
        r.register(MessageType.CLI_SWITCH, self._handle_cli_switch)
        r.register(MessageType.CLI_INSTALL, self._handle_cli_install)
        r.register(MessageType.CLI_UNINSTALL, self._handle_cli_uninstall)
        r.register(MessageType.CLI_ADD, self._handle_cli_add)
        r.register(MessageType.CLI_REMOVE, self._handle_cli_remove)
        r.register(MessageType.CLI_RETRY, self._handle_cli_retry)

        # Auth submit (MUST NOT be blocked by auth interceptor)
        r.register(MessageType.AUTH_SUBMIT, self._handle_auth_submit)

        # ACP session config (requires CLI)
        r.register(MessageType.MODE_SET, self._handle_mode_set, requires_cli=True)
        r.register(MessageType.CONFIG_SET, self._handle_config_set, requires_cli=True)

        # Heartbeat
        r.register(MessageType.STATUS_PING, self._handle_ping)

        # Plugins (no CLI)
        # Skipped in wsl-child mode (parent Agent handles plugins)
        if not self._is_wsl_child:
            r.register(MessageType.PLUGIN_LIST, self._plugin.handle_plugin_list)
            r.register(MessageType.PLUGIN_ENABLE, self._plugin.handle_plugin_enable)
            r.register(MessageType.PLUGIN_DISABLE, self._plugin.handle_plugin_disable)
            r.register(MessageType.PLUGIN_UNINSTALL, self._plugin.handle_plugin_uninstall)
            r.register(MessageType.PLUGIN_INSTALL, self._plugin.handle_plugin_install,
                       is_background=True)
            r.register(MessageType.PLUGIN_CONFIG_GET, self._plugin.handle_plugin_config_get)
            r.register(MessageType.PLUGIN_CONFIG_SET, self._plugin.handle_plugin_config_set)

    # ── Auth (simple enough to stay inline) ──

    async def _handle_relay_message(self, client_id: str, msg_dict: dict):
        """Route a decrypted Relay message through the standard pipeline.

        Creates a VirtualConnection for the client if not already tracked,
        then delegates to ``_route()`` like LAN/Tunnel connections. The
        VirtualConnection wraps the Relay WS client so handlers can call
        ``conn.send()`` transparently.

        If this is a new Relay client, registers it via ScopeManager with
        device_id credentials for identity-based scope resume.

        Args:
            client_id: Derived from Relay envelope ``from`` field (App's device_id).
            msg_dict: Decrypted message dict from the Relay envelope.
        """
        if client_id not in self._clients:
            vc = VirtualConnection(
                client_id,
                self._conn_manager._relay_ws,
                self._conn_manager._crypto,
                target_device_id=client_id,
            )
            self._clients[client_id] = ClientInfo(conn=vc, mode=ConnectionMode.RELAY)
            logger.info(f"📱 Relay 新客户端: {client_id[:16]}")

        # Register via ScopeManager if no scope exists yet
        if client_id not in self._scopes:
            result = await self.scope_manager.register_client(
                client_id, ConnectionMode.RELAY, {"device_id": client_id}
            )
            self._scopes[client_id] = result.scope
            if not result.resumed:
                await self._start_default_cli(client_id)
            else:
                cli_name = self.config.default_cli or ""
                if cli_name:
                    await self._push_cli_status_after_resume(client_id, cli_name)

        msg = Message(**msg_dict)
        await self._route(client_id, self._clients[client_id], msg)

    async def _handle_auth_pair(self, client_id, ws, msg):
        """Handle AUTH_PAIR: verify pairing code, generate secret, create session.

        After successful pairing:
        1. Generate a 32-byte shared secret for LAN message-level encryption.
        2. Create a session with the secret stored for reconnection.
        3. Send auth.result with session_token and Base64-encoded secret.
        4. Activate encryption for this client and replace the raw connection
           with an EncryptedConnection in ``_clients``.

        Brute-force protection: delegates to ``AuthManager.verify_pair_token()``
        which tracks per-source failure counts and enforces lockout.
        """
        try:
            payload = msg.typed_payload(AuthPairPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ auth.pair payload 校验失败: client={client_id}, {e}")
            await ws.send(Message.from_typed(
                type=MessageType.AUTH_RESULT,
                payload=AuthResultPayload(success=False, error=str(e)),
            ).model_dump_json())
            return

        success, error = self.auth.verify_pair_token(payload.token, source=client_id)

        if not success:
            logger.warning(f"❌ 配对失败: client={client_id}, error={error}")
            await ws.send(Message.from_typed(
                type=MessageType.AUTH_RESULT,
                payload=AuthResultPayload(success=False, error=error),
            ).model_dump_json())
            return

        # Generate shared secret for LAN encryption
        secret = os.urandom(32)
        session_token = self.auth.create_session(client_id, secret)
        self._clients[client_id] = ClientInfo(conn=ws, mode=ConnectionMode.LAN)
        logger.info(f"✅ 配对成功: {client_id}")

        # Register client via ScopeManager with LAN credentials
        result = await self.scope_manager.register_client(
            client_id, ConnectionMode.LAN, {"session_token": session_token}
        )
        self._scopes[client_id] = result.scope
        resumed = result.resumed
        cli_state = ""
        cli_name = self.config.default_cli or ""

        if resumed:
            # Transfer stream replay buffer
            if result.old_client_id:
                old_replay = self._stream_replays.pop(result.old_client_id, None)
                if old_replay:
                    self._stream_replays[client_id] = old_replay
                self.auth.update_session_client(session_token, client_id)
            # Determine current CLI state for the App
            session_key = (client_id, cli_name)
            provider = self.cli_manager._sessions.get(session_key)
            if provider and hasattr(provider, 'is_running') and provider.is_running:
                cli_state = "ready"
            logger.info(f"♻️ 配对恢复 scope: old={result.old_client_id} → {client_id}")

        # Send auth.result with secret BEFORE activating encryption
        # (this message is the last plaintext message)
        secret_b64 = base64.b64encode(secret).decode("ascii")
        await ws.send(Message.from_typed(
            type=MessageType.AUTH_RESULT,
            payload=AuthResultPayload(
                success=True,
                session_token=session_token,
                secret=secret_b64,
                client_id=client_id,
                resumed=resumed,
                cli_state=cli_state if resumed else "",
                cli_name=cli_name if resumed else "",
            ),
        ).model_dump_json())

        # Activate encryption for subsequent messages
        crypto = CryptoModule(secret)
        self._conn_manager.activate_encryption(client_id, crypto)
        self._clients[client_id] = ClientInfo(conn=EncryptedConnection(ws, crypto), mode=ConnectionMode.LAN)
        logger.info(f"🔒 LAN 加密已激活: client={client_id}")

        if not resumed:
            # No scope to resume — initialize fresh
            await self._start_default_cli(client_id)
        else:
            # Scope resumed — push current CLI status so App updates UI
            await self._push_cli_status_after_resume(client_id, cli_name)

    async def _handle_auth_connect(self, client_id, ws, msg):
        """Handle AUTH_CONNECT: verify an existing session token and re-activate encryption.

        Uses SessionVerifyResult (NamedTuple) from verify_session() to
        distinguish between "token not found" and "session expired", and
        to retrieve the stored shared secret and original client_id for
        scope resumption.

        Scope resumption flow:
        1. Verify session token → get original_client_id.
        2. Look up _suspended[original_client_id] for a grace-period scope.
        3. If found, cancel the grace timer, reset the scope, and remap
           CLI sessions from old → new client_id.
        4. If not found, create a fresh scope and initialize CLI.
        5. Send auth.result with resumed/cli_state so App knows what to do.
        """
        try:
            connect_payload = msg.typed_payload(AuthConnectPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ auth.connect payload 校验失败: client={client_id}, {e}")
            await ws.send(Message.from_typed(
                type=MessageType.AUTH_RESULT,
                payload=AuthResultPayload(success=False, error=str(e)),
            ).model_dump_json())
            return

        result = self.auth.verify_session(connect_payload.session_token)

        if result.success:
            self._clients[client_id] = ClientInfo(conn=ws, mode=ConnectionMode.LAN)
            logger.info(f"✅ 会话验证成功: {client_id}")

            # Re-activate encryption if secret is available
            if result.secret:
                crypto = CryptoModule(result.secret)
                self._conn_manager.activate_encryption(client_id, crypto)
                self._clients[client_id] = ClientInfo(conn=EncryptedConnection(ws, crypto), mode=ConnectionMode.LAN)
                logger.info(f"🔒 LAN 加密已重新激活: client={client_id}")

            # Register client via ScopeManager with LAN credentials for resume
            reg_result = await self.scope_manager.register_client(
                client_id, ConnectionMode.LAN, {"session_token": connect_payload.session_token}
            )
            self._scopes[client_id] = reg_result.scope
            resumed = reg_result.resumed
            cli_state = ""
            cli_name = self.config.default_cli or ""

            if resumed and reg_result.old_client_id:
                # Transfer stream replay buffer
                old_replay = self._stream_replays.pop(reg_result.old_client_id, None)
                if old_replay:
                    self._stream_replays[client_id] = old_replay
                self.auth.update_session_client(connect_payload.session_token, client_id)
                # Determine current CLI state
                session_key = (client_id, cli_name)
                provider = self.cli_manager._sessions.get(session_key)
                if provider and hasattr(provider, 'is_running') and provider.is_running:
                    cli_state = "ready"
                logger.info(f"♻️ 会话恢复: {reg_result.old_client_id} → {client_id}")

            # Build and send auth.result with resume status
            secret_b64 = (
                base64.b64encode(result.secret).decode("ascii")
                if result.secret else None
            )
            await ws.send(Message.from_typed(
                type=MessageType.AUTH_RESULT,
                payload=AuthResultPayload(
                    success=True,
                    session_token=connect_payload.session_token,
                    client_id=client_id,
                    resumed=resumed,
                    cli_state=cli_state if resumed else "",
                    cli_name=cli_name if resumed else "",
                    secret=secret_b64,
                ),
            ).model_dump_json())

            if not resumed:
                await self._start_default_cli(client_id)
            else:
                await self._push_cli_status_after_resume(client_id, cli_name)

            # Include streaming state in the auth.result payload so the
            # App knows whether to request chat.replay. This avoids a
            # separate chat.stream "status" hack message that could be
            # misrouted if _routeMessage order changes.
            replay = self._stream_replays.get(client_id)
            if replay and (replay.is_active or replay.is_finished):
                streaming_state = "streaming" if replay.is_active else "completed"
                # Re-send auth.result with streaming_state appended.
                # The App already processed the first auth.result for
                # connection setup; this field is checked separately.
                await ws.send(Message.from_typed(
                    type=MessageType.CHAT_REPLAY_RESULT,
                    payload=ChatReplayResultPayload(
                        chunks=[],
                        streaming=replay.is_active,
                        seq=replay.seq,
                        streaming_state=streaming_state,
                    ),
                ).model_dump_json())
        else:
            logger.warning(f"❌ 会话验证失败: client={client_id}, error={result.error_code}")
            await ws.send(Message.from_typed(
                type=MessageType.AUTH_RESULT,
                payload=AuthResultPayload(
                    success=False,
                    error=result.error_code,
                    should_repair=True,
                ),
            ).model_dump_json())

    async def _handle_cli_list(self, client_id, ws, msg):
        """Handle CLI_LIST: return all registered CLI adapters."""
        cli_list = self.cli_manager.list_adapters()
        await ws.send(Message.from_typed(
            type=MessageType.CLI_LIST_RESULT,
            payload=CliListResultPayload(
                adapters=[c.model_dump() for c in cli_list],
                default_cli=self.config.default_cli,
            ),
        ).model_dump_json())

    async def _handle_cli_switch(self, client_id, ws, msg):
        """Handle CLI_SWITCH: change the default CLI and trigger initialization.

        Shuts down the old CLI's provider (kills its ACP process) before
        starting the new one. If the new CLI runs in WSL, activates the
        WSL proxy to forward messages to the child Agent.
        """
        try:
            payload = msg.typed_payload(CliSwitchPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ cli.switch payload 校验失败: client={client_id}, {e}")
            return

        cli_name = payload.cli
        if not cli_name:
            logger.warning("cli.switch: 空的 CLI 名称，忽略")
            return
        old_cli = self.config.default_cli
        self.config.default_cli = cli_name
        logger.info(f"CLI 切换: {old_cli} → {cli_name}")

        # Clean up old CLI's provider FIRST to avoid zombie ACP processes.
        # This must happen before WSL proxy activation — otherwise the
        # early return would skip cleanup.
        if old_cli and old_cli != cli_name:
            old_key = (client_id, old_cli)
            old_provider = self.cli_manager._sessions.pop(old_key, None)
            self.cli_manager._session_ids.pop(old_key, None)
            self.cli_manager._provider_tasks.pop(old_key, None)
            if old_provider:
                # Cache capabilities before shutdown so the CLI still
                # reports its real capabilities in cli.list.result
                self.cli_manager.cache_capabilities(old_cli, old_provider)
                try:
                    await old_provider.shutdown()
                except Exception as e:
                    logger.debug(f"旧 CLI provider 关闭出错（可忽略）: {e}")

        # Determine if the new CLI runs in WSL
        new_env = self.cli_manager.registry.get_execution_env(cli_name)
        is_wsl_cli = new_env == "wsl"
        wsl_proxy = getattr(self, '_wsl_proxy', None)

        # Activate/deactivate WSL proxy based on CLI environment
        if wsl_proxy:
            if is_wsl_cli:
                logger.info(f"CLI {cli_name} 运行在 WSL，激活代理")
                activated = await wsl_proxy.activate()
                if activated:
                    # WSL CLI: child Agent handles everything, skip local init
                    return
                else:
                    # WSL proxy failed — fall back to native execution.
                    # Override execution_env so all subsequent operations
                    # (ACP initialize, terminal PTY) use native mode.
                    logger.warning(f"WSL 代理激活失败，回退到 native 执行: {cli_name}")
                    self.cli_manager.registry.set_execution_env(cli_name, "native")
            else:
                # Native CLI: deactivate proxy if it was active
                if wsl_proxy.is_active:
                    await wsl_proxy.deactivate()

        # Initialize the CLI locally (native CLIs only — WSL CLIs handled by proxy)
        if cli_name and self.config.work_dir:
            scope = self._scopes.get(client_id)
            task = asyncio.create_task(
                self.cli_manager._ensure_provider(client_id, cli_name)
            )
            if scope:
                scope.track_task(task)

    async def _handle_cli_install(self, client_id, ws, msg):
        """Handle CLI_INSTALL: install an Agent CLI with progress feedback.

        Passes a progress callback to install_agent so each package step
        is streamed to the App as a cli.install.progress message.
        """
        try:
            payload = msg.typed_payload(CliInstallPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ cli.install payload 校验失败: client={client_id}, {e}")
            return

        cli_name = payload.cli
        logger.info(f"📦 安装请求: {cli_name}")

        async def progress_cb(cli, step, total, package, label, status):
            """Stream install progress to the App."""
            await ws.send(Message.from_typed(
                type=MessageType.CLI_INSTALL_PROGRESS,
                payload=CliInstallProgressPayload(
                    cli=cli,
                    step=step,
                    total_steps=total,
                    package=package,
                    label=label,
                    status=status,
                ),
            ).model_dump_json())

        result = await self.cli_manager.registry.install_agent(cli_name, progress_cb=progress_cb)
        await ws.send(Message.from_typed(
            type=MessageType.CLI_INSTALL_RESULT,
            payload=CliInstallResultPayload(cli=cli_name, **result),
        ).model_dump_json())
        # Refresh the CLI list on the App side after successful install
        if result.get("success"):
            cli_list = self.cli_manager.list_adapters()
            await ws.send(Message.from_typed(
                type=MessageType.CLI_LIST_RESULT,
                payload=CliListResultPayload(
                    adapters=[c.model_dump() for c in cli_list],
                    default_cli=self.config.default_cli,
                ),
            ).model_dump_json())

    async def _handle_cli_uninstall(self, client_id, ws, msg):
        """Handle CLI_UNINSTALL: uninstall an Agent CLI with progress feedback.

        Stops any active terminal/ACP sessions for the CLI before uninstalling.
        If the uninstalled CLI was the default, switches to the next available one.
        """
        try:
            payload = msg.typed_payload(CliUninstallPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ cli.uninstall payload 校验失败: client={client_id}, {e}")
            return

        cli_name = payload.cli
        logger.info(f"🗑️ 卸载请求: {cli_name}")

        # Stop terminal if it's running this CLI
        await self.terminal_manager.stop_session(client_id)

        # Clean up ACP sessions for this CLI
        key = (client_id, cli_name)
        provider = self.cli_manager._sessions.pop(key, None)
        self.cli_manager._session_ids.pop(key, None)
        if provider:
            try:
                await provider.shutdown()
            except Exception as e:
                logger.debug(f"卸载前关闭 provider 出错（可忽略）: {e}")

        async def progress_cb(cli, step, total, package, label, status):
            """Stream uninstall progress to the App."""
            await ws.send(Message.from_typed(
                type=MessageType.CLI_INSTALL_PROGRESS,
                payload=CliInstallProgressPayload(
                    cli=cli,
                    step=step,
                    total_steps=total,
                    package=package,
                    label=label,
                    status=status,
                ),
            ).model_dump_json())

        result = await self.cli_manager.registry.uninstall_agent(cli_name, progress_cb=progress_cb)
        await ws.send(Message.from_typed(
            type=MessageType.CLI_UNINSTALL_RESULT,
            payload=CliUninstallResultPayload(cli=cli_name, **result),
        ).model_dump_json())

        # If uninstalled CLI was the default, switch to next available
        if result.get("success") and self.config.default_cli == cli_name:
            available = [i.name for i in self.cli_manager.registry._detected if i.available]
            self.config.default_cli = available[0] if available else ""
            logger.info(f"默认 CLI 已切换: {self.config.default_cli or '无'}")

        # Refresh CLI list
        cli_list = self.cli_manager.list_adapters()
        await ws.send(Message.from_typed(
            type=MessageType.CLI_LIST_RESULT,
            payload=CliListResultPayload(
                adapters=[c.model_dump() for c in cli_list],
                default_cli=self.config.default_cli,
            ),
        ).model_dump_json())

    async def _handle_cli_add(self, client_id, ws, msg):
        """Handle CLI_ADD: validate command, register custom Agent, refresh list.

        Validates the command is accessible before saving. For WSL paths,
        checks permissions and returns actionable error messages (e.g.
        "run sudo cp ... /usr/local/bin/") so the user can fix the issue
        before the agent is added.
        """
        try:
            payload = msg.typed_payload(CliAddPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ cli.add payload 校验失败: client={client_id}, {e}")
            return

        name = payload.name
        command = payload.command
        args = payload.args
        display_name = payload.display_name or name
        logger.info(f"➕ 添加自定义 Agent: {display_name} ({command})")

        # Validate command accessibility before saving
        validation = self.cli_manager.registry._validate_custom_command(command)
        if not validation["accessible"]:
            logger.warning(f"自定义 Agent 验证失败: {command}, {validation['message']}")
            result = {"success": False, "message": validation["message"]}
        else:
            result = self.cli_manager.registry.add_custom_agent(name, command, args, display_name)

        # Re-detect all CLIs (including the newly added one)
        if result.get("success"):
            await self.cli_manager.detect_all()
        # Send the updated adapter list
        cli_list = self.cli_manager.list_adapters()
        await ws.send(Message.from_typed(
            type=MessageType.CLI_LIST_RESULT,
            payload=CliListResultPayload(
                adapters=[c.model_dump() for c in cli_list],
                default_cli=self.config.default_cli,
                action_result=result,
            ),
        ).model_dump_json())

    async def _handle_cli_remove(self, client_id, ws, msg):
        """Handle CLI_REMOVE: unregister a custom Agent and refresh the adapter list."""
        try:
            payload = msg.typed_payload(CliRemovePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ cli.remove payload 校验失败: client={client_id}, {e}")
            return

        name = payload.name
        logger.info(f"➖ 移除自定义 Agent: {name}")
        result = self.cli_manager.registry.remove_custom_agent(name)
        # Send the updated adapter list
        cli_list = self.cli_manager.list_adapters()
        await ws.send(Message.from_typed(
            type=MessageType.CLI_LIST_RESULT,
            payload=CliListResultPayload(
                adapters=[c.model_dump() for c in cli_list],
                default_cli=self.config.default_cli,
                action_result=result,
            ),
        ).model_dump_json())

    async def _handle_cli_retry(self, client_id, ws, msg):
        """Handle CLI_RETRY: clean up and re-initialise the CLI session."""
        try:
            payload = msg.typed_payload(CliRetryPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ cli.retry payload 校验失败: client={client_id}, {e}")
            return

        cli_name = payload.cli or self.config.default_cli
        logger.info(f"🔄 CLI 重试请求: client={client_id}, cli={cli_name}")
        await self.cli_manager.handle_retry(client_id, cli_name)

    async def _handle_auth_submit(self, client_id, ws, msg):
        """Handle AUTH_SUBMIT: forward credentials to CLIManager for ACP authentication."""
        try:
            payload = msg.typed_payload(AuthSubmitPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ auth.submit payload 校验失败: client={client_id}, {e}")
            return
        cli_name = payload.cli or self.config.default_cli
        method_id = payload.method_id
        data = payload.data
        logger.info(f"🔑 认证提交: client={client_id}, cli={cli_name}, method={method_id}")
        await self.cli_manager.handle_auth_submit(client_id, cli_name, method_id, data)

    async def _handle_mode_set(self, client_id, ws, msg):
        """Handle MODE_SET: switch the ACP session mode."""
        p = msg.typed_payload(ModeSetPayload)
        cli_name = p.cli or self.config.default_cli
        mode_id = p.mode_id
        logger.info(f"🔄 模式切换: client={client_id}, cli={cli_name}, mode={mode_id}")
        await self.cli_manager.set_mode(client_id, cli_name, mode_id)

    async def _handle_config_set(self, client_id, ws, msg):
        """Handle CONFIG_SET: update an ACP configuration option."""
        p = msg.typed_payload(ConfigSetPayload)
        cli_name = p.cli or self.config.default_cli
        config_id = p.config_id
        value = p.value
        logger.info(f"⚙ 配置变更: client={client_id}, cli={cli_name}, config={config_id}, value={value}")
        await self.cli_manager.set_config_option(client_id, cli_name, config_id, value)

    async def _broadcast_to_client(self, client_id: str, message: Message):
        """Send a message to a specific client by its identifier.

        Args:
            client_id: Target client identifier.
            message: Protocol message to deliver.
        """
        client_info = self._clients.get(client_id)
        if client_info:
            try:
                await client_info.send(message.model_dump_json())
            except Exception as e:
                logger.warning(f"广播消息失败: client={client_id}, type={message.type}, error={e}")
        else:
            logger.debug(f"广播目标客户端不存在: client={client_id}")

    def _get_client_mode(self, client_id: str) -> ConnectionMode:
        """Get the connection mode for a specific client.

        Reads from ClientInfo if available, falls back to LAN.

        Args:
            client_id: The client identifier.

        Returns:
            The ConnectionMode for this client.
        """
        client_info = self._clients.get(client_id)
        if client_info:
            return client_info.mode
        return ConnectionMode.LAN

    async def _broadcast_raw(self, raw: str) -> None:
        """Broadcast a raw JSON string to all connected App clients.

        Used by WslProxy to relay messages from the child Agent without
        deserializing and re-serializing them.

        Args:
            raw: JSON-serialized message string.
        """
        for client_info in list(self._clients.values()):
            try:
                await client_info.send(raw)
            except Exception:
                pass

    async def _on_state_changed(self, data: dict) -> None:
        """Push state changes to all connected App clients.

        When GitStateManager updates its internal state, it emits
        "state.changed" events. This handler forwards them to all
        connected clients so the App can update its UI without polling.

        Args:
            data: {key: "git.status"|"git.branches"|..., data: <state_dict>}
        """
        key = data.get("key", "")
        state_data = data.get("data")
        if not key or state_data is None:
            return

        msg = Message.from_typed(
            MessageType.STATE_PUSH,
            StatePushPayload(key=key, data=state_data),
        )
        for client_info in list(self._clients.values()):
            try:
                await client_info.send(msg.model_dump_json())
            except Exception:
                pass

    async def _on_cli_commands_available(self, data: dict) -> None:
        """Forward CLI-advertised commands to all connected App clients.

        When a CLI advertises available slash commands via ACP
        AvailableCommandsUpdate, this handler pushes them to the App
        so the slash command menu can display them.

        Args:
            data: {cli_name: str, commands: [{name, description}, ...]}
        """
        cli_name = data.get("cli_name", "")
        commands = data.get("commands", [])
        if not cli_name:
            return

        logger.debug(f"CLI 命令推送: cli={cli_name}, count={len(commands)}")
        msg = Message.from_typed(
            MessageType.CLI_COMMANDS,
            CliCommandsPayload(cli=cli_name, commands=commands),
        )
        for client_info in list(self._clients.values()):
            try:
                await client_info.send(msg.model_dump_json())
            except Exception:
                pass

    async def _on_git_op_progress(self, data: dict) -> None:
        """Push operation progress to all connected App clients.

        Only pushes when the busy state actually changes, preventing
        rapid start/end events from causing UI flicker.

        Args:
            data: {kind: str, blocking: bool, read_only: bool, error: str|None}
        """
        is_busy = self.git_state.operations.should_show_progress()

        # Only push when busy state changes (prevents flicker on fast operations)
        if is_busy == self._last_progress_busy:
            return
        self._last_progress_busy = is_busy

        msg = Message.from_typed(
            MessageType.STATE_PUSH,
            StatePushPayload(
                key="git.progress",
                data={
                    "busy": is_busy,
                    "operation": data.get("kind", ""),
                },
            ),
        )
        for client_info in list(self._clients.values()):
            try:
                await client_info.send(msg.model_dump_json())
            except Exception:
                pass

    async def _handle_ping(self, client_id, ws, msg):
        """Handle STATUS_PING: reply with a PONG."""
        await ws.send(Message.from_typed(
            MessageType.STATUS_PONG, StatusPongPayload(),
        ).model_dump_json())

    async def _register_preauthenticated_client(self, client_id: str, mode: ConnectionMode, credentials: dict | None = None) -> None:
        """Register a pre-authenticated client via ScopeManager.

        For Tunnel mode, passes bearer_token for identity resolution.
        For WSL child mode, no credentials (no identity-based resume).

        Args:
            client_id: The pre-authenticated client's identifier.
            mode: The connection mode (Tunnel or LAN for WSL child).
            credentials: Mode-specific auth data for identity resolution.
        """
        result = await self.scope_manager.register_client(client_id, mode, credentials)
        self._scopes[client_id] = result.scope

        if result.resumed:
            # Transfer stream replay buffer
            if result.old_client_id:
                old_replay = self._stream_replays.pop(result.old_client_id, None)
                if old_replay:
                    self._stream_replays[client_id] = old_replay
            cli_name = self.config.default_cli or ""
            if cli_name:
                await self._push_cli_status_after_resume(client_id, cli_name)
        else:
            await self._start_default_cli(client_id)

    async def _start_default_cli(self, client_id: str) -> None:
        """Start the default CLI provider for a newly registered client.

        Called after scope creation (by ScopeManager). Only starts the CLI
        provider — scope creation and cleanup registration are handled by
        ScopeManager.

        Args:
            client_id: The authenticated client's identifier.
        """
        scope = self._scopes.get(client_id)
        cli_name = self.config.default_cli
        if cli_name and self.config.work_dir and scope:
            logger.info(f"客户端已认证，初始化默认 CLI: {cli_name}")
            task = asyncio.create_task(
                self.cli_manager._ensure_provider(client_id, cli_name)
            )
            scope.track_task(task)

    async def _register_scope_cleanups(self, client_id: str, scope: ClientScope) -> None:
        """Register service-specific cleanups on a new scope.

        Called by ScopeManager._create_scope() as the cleanup_factory callback.
        Registers terminal, permission, stream replay, and test panel cleanups.

        Args:
            client_id: The client's identifier.
            scope: The newly created ClientScope to register cleanups on.
        """
        # Terminal cleanup — cancel forward task and stop PTY session.
        async def _cleanup_terminal():
            await self._terminal._cancel_forward_task(client_id)
            await self.terminal_manager.stop_session(client_id)
            self._terminal._generations.pop(client_id, None)
        scope.on_dispose(_cleanup_terminal)

        # Permission future cleanup — cancel pending permission requests.
        def _cancel_permissions():
            for req_id, future in list(self._permission_futures.items()):
                if not future.done():
                    future.set_result({"outcome": {"outcome": "cancelled"}})
        scope.on_dispose(_cancel_permissions)

        # StreamReplay — create buffer for disconnect recovery.
        replay = StreamReplay(max_chunks=self.config.stream_replay.max_chunks)
        self._stream_replays[client_id] = replay

        def _cleanup_replay():
            self._stream_replays.pop(client_id, None)
        scope.on_dispose(_cleanup_replay)

        # Test Panel cleanup — stop running preview/script subprocesses.
        scope.on_dispose(lambda: self._test_panel.cleanup_client(client_id))

    def get_stream_replay(self, client_id: str) -> StreamReplay | None:
        """Get the StreamReplay buffer for a client.

        Args:
            client_id: The client's identifier.

        Returns:
            The StreamReplay instance, or None if no scope exists.
        """
        return self._stream_replays.get(client_id)

    async def _push_cli_status_after_resume(self, client_id: str, cli_name: str) -> None:
        """Push cli.status=ready to the App after scope resumption.

        When a scope is resumed, the CLI provider is already running but
        the App doesn't know that (it just reconnected). This method
        pushes a cli.status message so the App transitions from
        "connecting" spinner to the ready state immediately.

        Also sends a StreamReplay signal if there's buffered output.

        Args:
            client_id: The reconnected client's identifier.
            cli_name: The CLI adapter name.
        """
        client_info = self._clients.get(client_id)
        if not client_info:
            return

        # Push cli.status=ready so App stops showing spinner
        session_key = (client_id, cli_name)
        provider = self.cli_manager._sessions.get(session_key)
        caps = {}
        if provider and hasattr(provider, 'capabilities') and provider.capabilities:
            caps = provider.capabilities.to_capability_dict()

        try:
            await client_info.send(Message.from_typed(
                type=MessageType.CLI_STATUS,
                payload=CliStatusPayload(
                    cli=cli_name,
                    state="ready",
                    message=t("backend.agentReady"),
                    capabilities=caps,
                ),
            ).model_dump_json())
            logger.debug(f"恢复后推送 cli.status=ready: cli={cli_name}")
        except Exception:
            pass

        # If there's buffered stream output, signal the App to request replay
        replay = self._stream_replays.get(client_id)
        if replay and (replay.is_active or replay.is_finished):
            try:
                await client_info.send(Message.from_typed(
                    type=MessageType.CHAT_REPLAY_RESULT,
                    payload=ChatReplayResultPayload(
                        chunks=[],
                        streaming=replay.is_active,
                        seq=replay.seq,
                        streaming_state="streaming" if replay.is_active else "completed",
                    ),
                ).model_dump_json())
            except Exception:
                pass

    # ── File watcher ──

    async def _watch_files(self):
        """Watch the working directory for file changes and push events to connected clients.

        Filters out hidden directories, common noise directories (node_modules,
        __pycache__, etc.), temporary/backup files, and system-generated files
        to avoid flooding the App with irrelevant events.
        """
        from watchfiles import awatch, Change
        from pathlib import Path
        watch_path = Path(self.config.work_dir)
        if not watch_path.exists():
            logger.warning(f"👁️ 监听目录不存在，跳过: {watch_path}")
            return
        logger.info(f"👁️ 监听文件变化: {watch_path}")

        # Noise file extensions (IDE / editor / system temp files)
        _noise_suffixes = {'.swp', '.swo', '.tmp', '.log', '.lock', '.pyc', '.pyo',
                           '.vhdx', '.vmdk', '.qcow2', '.vdi', '.iso', '.img'}
        # Noise file names
        _noise_names = {'4913', '.DS_Store', 'Thumbs.db', 'desktop.ini'}
        # Noise directories (Docker, VMs, system caches — high-frequency writes)
        _noise_dirs = {'DockerDesktopWSL', 'docker-desktop-data', 'docker-desktop',
                       '.docker', 'Docker', 'Hyper-V', 'VirtualBox VMs'}

        try:
            async for changes in awatch(watch_path):
                for change_type, path_str in changes:
                    try:
                        rel = str(Path(path_str).relative_to(watch_path)).replace("\\", "/")
                    except ValueError:
                        continue
                    # Filter hidden directories and common noise directories
                    # Special case: .git directory changes ARE allowed through
                    # so we can detect commit/checkout/branch operations that
                    # modify .git/HEAD, .git/refs/, etc. We filter index.lock
                    # and watchman cookies as noise.
                    parts = rel.split('/')
                    is_dotgit_change = len(parts) >= 2 and parts[0] == '.git'

                    if is_dotgit_change:
                        # Allow .git first-level file changes and refs/ through,
                        # but filter index.lock (transient during git operations)
                        # and watchman cookie files (fsmonitor noise).
                        dotgit_file = parts[-1] if parts else ''
                        if dotgit_file == 'index.lock' or '.watchman-cookie-' in dotgit_file:
                            continue
                        # Filter deep .git subdirectories that are internal storage
                        # (objects/, pack/, logs/refs/ etc.) but allow refs/ through
                        # because checkout/branch operations modify refs/heads/ and
                        # fetch modifies refs/remotes/.
                        if len(parts) >= 2:
                            dotgit_subdir = parts[1]
                            # Allow: HEAD, COMMIT_EDITMSG, refs/*, MERGE_HEAD, etc.
                            # Filter: objects/, pack/, hooks/, info/, logs/
                            if dotgit_subdir in ('objects', 'pack', 'hooks', 'info', 'logs'):
                                continue
                    else:
                        # Non-.git paths: filter all hidden dirs and noise dirs
                        if any(p.startswith('.') or p in ('node_modules', '__pycache__', 'build', 'dist', '.venv', 'venv') or p in _noise_dirs for p in parts):
                            continue
                    # Filter noise files
                    filename = parts[-1] if parts else ''
                    if filename in _noise_names:
                        continue
                    suffix = Path(filename).suffix.lower()
                    if suffix in _noise_suffixes:
                        continue
                    # Filter backup files ending with ~
                    if filename.endswith('~'):
                        continue

                    change = {Change.added: "created", Change.modified: "modified", Change.deleted: "deleted"}.get(change_type, "modified")
                    logger.debug(f"📁 文件变化: {change} {rel}")

                    # During blocking operations (checkout, commit, push),
                    # suppress file.changed pushes to App to avoid event storms.
                    # The operation will trigger a full refresh when it completes.
                    if not self.git_state.operations.should_block():
                        msg = Message.from_typed(type=MessageType.FILE_CHANGED, payload=FileChangedPayload(path=rel, change=change))
                        for client_info in list(self._clients.values()):
                            try:
                                await client_info.send(msg.model_dump_json())
                            except Exception:
                                pass

                    # Always publish to EventBus — RefreshScheduler has its own
                    # idle check and debounce, so it handles the filtering itself.
                    await self.event_bus.emit(Events.FILE_CHANGED, {
                        "path": rel, "change": change
                    })
        except Exception as e:
            logger.warning(f"文件监听出错: {e}")

    def _print_connect_info(self, pair_token: str, show_password: bool = True):
        """Log the connection URL and password for the user.

        On first startup (show_password=True), prints the password in full.
        On subsequent startups, masks the password and hints how to view it.

        Args:
            pair_token: The connection password.
            show_password: Whether to show the full password (first time only).
        """
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except Exception:
            local_ip = "127.0.0.1"
        logger.info(f"🔗 连接地址: ws://{local_ip}:{self.config.port}")
        logger.info(f"🔑 连接密码: {pair_token}")
        if show_password:
            logger.info("📱 首次生成的连接密码，请妥善保管")
        logger.info("📱 在手机 App 中输入地址和密码连接")
