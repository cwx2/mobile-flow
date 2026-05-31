"""
MobileFlow Agent CLI entry point.

Supported commands:
  start     — Start the Agent (LAN/Relay/Tunnel mode)
  pair      — Generate pairing code, wait for phone to scan
  daemon    — Background process management (start/stop/status/install/uninstall)
  serve     — Tunnel mode: start TLS-enabled WebSocket server
  devices   — Device management (list/revoke)
  status    — Show Agent status

Usage: python -m mobileflow_agent <command> [options]
"""

import argparse
import asyncio
import os
import sys

from loguru import logger

from .server.websocket import WebSocketServer
from .core.config import AgentConfig


def _cleanup_pyinstaller_env():
    """Clean up environment variables polluted by PyInstaller bundling.

    PyInstaller prepends its _MEIPASS temp directory to PATH and alters
    the DLL search order. When the Agent spawns child processes (cmd.exe,
    git, wsl, npm), Windows loads DLLs from _MEIPASS instead of System32,
    causing 0xc0000142 (DLL initialization failed) errors.

    This function removes _MEIPASS entries from PATH at startup so all
    child processes use the original system DLL search order.
    """
    if not getattr(sys, 'frozen', False):
        return  # Not running from PyInstaller bundle

    meipass = getattr(sys, '_MEIPASS', '')
    if not meipass:
        return

    # Clean PATH: remove all entries that start with _MEIPASS
    original_path = os.environ.get('PATH', '')
    cleaned_parts = [
        p for p in original_path.split(os.pathsep)
        if not p.startswith(meipass)
    ]
    os.environ['PATH'] = os.pathsep.join(cleaned_parts)

    # Reset DLL search directory to system default (Windows only).
    # PyInstaller calls SetDllDirectory(_MEIPASS) which overrides the
    # default DLL search order for all child processes.
    if sys.platform == 'win32':
        try:
            import ctypes
            ctypes.windll.kernel32.SetDllDirectoryW(None)
        except Exception:
            pass  # Non-critical — PATH cleanup alone usually suffices


def _suppress_subprocess_windows():
    """Prevent child processes from flashing console windows on Windows.

    When the Agent runs as a GUI app (console=False in PyInstaller),
    every subprocess.run/Popen/create_subprocess call spawns a visible
    console window that immediately closes. This looks like malware.

    Fix: monkey-patch subprocess.Popen to inject CREATE_NO_WINDOW
    (0x08000000) into creationflags on Windows when no console is attached.
    Only applies to PyInstaller frozen builds with console=False.
    """
    if sys.platform != 'win32':
        return
    if not getattr(sys, 'frozen', False):
        return

    import subprocess
    _original_init = subprocess.Popen.__init__

    def _patched_init(self, *args, **kwargs):
        # Only inject if caller didn't explicitly set creationflags
        if 'creationflags' not in kwargs or kwargs['creationflags'] == 0:
            kwargs['creationflags'] = kwargs.get('creationflags', 0) | 0x08000000
        _original_init(self, *args, **kwargs)

    subprocess.Popen.__init__ = _patched_init


def main() -> None:
    """Parse CLI arguments and dispatch to the appropriate handler.

    Config loading priority: code defaults → JSON config → .env → env vars → CLI args.
    CLI args (--port, --host, etc.) override everything.
    """
    # Fix PyInstaller DLL search order before any subprocess is spawned
    _cleanup_pyinstaller_env()
    # Prevent console window flashing for child processes (Windows GUI mode)
    _suppress_subprocess_windows()
    parser = argparse.ArgumentParser(description="MobileFlow Desktop Agent")
    sub = parser.add_subparsers(dest="command", help="command")

    # start command
    start_p = sub.add_parser("start", help="start the Agent")
    start_p.add_argument("--port", type=int, default=None)
    start_p.add_argument("--host", type=str, default=None)
    start_p.add_argument("--work-dir", type=str, default=None)
    start_p.add_argument("--mode", choices=["lan", "relay", "tunnel", "wsl-child"],
                         default=None, help="connection mode (wsl-child: WSL child Agent mode)")
    start_p.add_argument("--relay-url", type=str, default=None,
                         help="Relay Server URL (relay mode)")
    start_p.add_argument("--tray", action="store_true",
                         help="start in system tray mode (no terminal window)")
    start_p.add_argument("--debug", action="store_true")

    # pair command
    pair_p = sub.add_parser("pair", help="generate pairing code")
    pair_p.add_argument("--relay-url", type=str, default=None)
    pair_p.add_argument("--debug", action="store_true")

    # daemon command
    daemon_p = sub.add_parser("daemon", help="daemon management")
    daemon_sub = daemon_p.add_subparsers(dest="daemon_cmd")
    daemon_sub.add_parser("start", help="start daemon")
    daemon_sub.add_parser("stop", help="stop daemon")
    daemon_sub.add_parser("status", help="show status")
    daemon_sub.add_parser("install", help="install as system service")
    daemon_sub.add_parser("uninstall", help="uninstall system service")

    # serve command (tunnel mode)
    serve_p = sub.add_parser("serve", help="tunnel mode")
    serve_p.add_argument("--port", type=int, default=8765)
    serve_p.add_argument("--token", type=str, default=None, help="Bearer Token")
    serve_p.add_argument("--tls-cert", type=str, default=None)
    serve_p.add_argument("--tls-key", type=str, default=None)
    serve_p.add_argument("--debug", action="store_true")

    # devices command
    devices_p = sub.add_parser("devices", help="device management")
    devices_sub = devices_p.add_subparsers(dest="devices_cmd")
    devices_sub.add_parser("list", help="list paired devices")
    revoke_p = devices_sub.add_parser("revoke", help="revoke a device")
    revoke_p.add_argument("device_id", help="device ID")

    # status command
    sub.add_parser("status", help="show Agent status")

    # password command
    sub.add_parser("password", help="show current connection password")

    # reset-password command
    sub.add_parser("reset-password", help="reset connection password")

    args = parser.parse_args()

    if not args.command:
        # When running from PyInstaller bundle with no arguments,
        # default to tray mode (double-click to start)
        if getattr(sys, 'frozen', False):
            args = parser.parse_args(['start', '--tray'])
        else:
            parser.print_help()
            return

    # Load configuration
    config = AgentConfig()
    debug = getattr(args, 'debug', False)

    # Apply CLI arguments
    if hasattr(args, 'port') and args.port:
        config.port = args.port
    if hasattr(args, 'host') and args.host:
        config.host = args.host
    if hasattr(args, 'work_dir') and args.work_dir:
        config.work_dir = args.work_dir
    if hasattr(args, 'mode') and args.mode:
        if args.mode == 'wsl-child':
            config.wsl_child_mode = True
        else:
            config.connection_mode = args.mode
    if hasattr(args, 'relay_url') and args.relay_url:
        config.relay_url = args.relay_url

    # Configure logging
    logger.remove()
    level = "DEBUG" if debug else (config.log_level or "INFO")
    log_format = "{time:HH:mm:ss} | {level:<7} | {message}"
    color_format = "<green>{time:HH:mm:ss}</green> | <level>{level:<7}</level> | {message}"

    if sys.stdout is not None:
        # Terminal available: log to stdout with colors
        logger.add(sys.stdout, level=level, format=color_format)

    if getattr(sys, 'frozen', False):
        # Packaged mode: also log to file for troubleshooting
        log_dir = config.ensure_data_dir() / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        logger.add(str(log_dir / "agent.log"), level=level,
                   rotation="10 MB", format=log_format)

    # Dashboard log buffer — captures logs for the web management panel.
    # Registered as a global so the dashboard API can access it.
    from .dashboard.log_buffer import LogBuffer
    _log_buffer = LogBuffer(maxlen=500)
    logger.add(_log_buffer.sink, level=level, format=log_format)

    if args.command == "start":
        # Tray mode: system tray icon, no terminal window
        if getattr(args, 'tray', False):
            logger.info("🚀 MobileFlow Agent 启动中（托盘模式）...")
            from .tray import start_with_tray
            start_with_tray(config, log_buffer=_log_buffer)
            return

        # Terminal mode: stdin listener + watchdog
        logger.info("🚀 MobileFlow Agent 启动中...")
        server = WebSocketServer(config, log_buffer=_log_buffer)

        # Shutdown event: set by stdin listener or Ctrl+C
        import threading
        import os as _os
        _shutting_down = threading.Event()

        def _stdin_listener():
            """Listen for 'q' or 'quit' on stdin to trigger graceful shutdown."""
            try:
                while True:
                    line = input().strip().lower()
                    if line in ('q', 'quit', 'exit', 'stop'):
                        logger.info("👋 收到退出命令")
                        _shutting_down.set()
                        return
            except (EOFError, KeyboardInterrupt):
                pass

        # Watchdog: force exit after shutdown_total_timeout + 5s grace
        def _watchdog():
            _shutting_down.wait()
            import time
            grace = config.lifecycle.shutdown_total_timeout + 5
            time.sleep(grace)
            logger.warning(f"关闭超时 ({grace}s)，强制退出")
            _os._exit(1)

        # Start background threads
        stdin_thread = threading.Thread(target=_stdin_listener, daemon=True)
        stdin_thread.start()
        watchdog_thread = threading.Thread(target=_watchdog, daemon=True)
        watchdog_thread.start()

        logger.info("💡 输入 q 退出")

        async def _run_with_shutdown():
            """Run the server and handle graceful shutdown on exit."""
            try:
                await server.start()
            except asyncio.CancelledError:
                pass
            finally:
                await server.shutdown()

        try:
            asyncio.run(_run_with_shutdown())
        except KeyboardInterrupt:
            logger.info("👋 收到 Ctrl+C，正在关闭...")
            # asyncio.run already exited — run shutdown in a new loop
            asyncio.run(server.shutdown())
        finally:
            _shutting_down.set()

    elif args.command == "pair":
        _handle_pair(config, args)

    elif args.command == "daemon":
        _handle_daemon(config, args)

    elif args.command == "serve":
        _handle_serve(config, args, log_buffer=_log_buffer)

    elif args.command == "devices":
        _handle_devices(config, args)

    elif args.command == "status":
        _handle_status(config)

    elif args.command == "password":
        from .server.auth import AuthManager
        auth = AuthManager(config)
        token, _ = auth.ensure_pair_token()
        logger.info(f"🔑 连接密码: {token}")

    elif args.command == "reset-password":
        from .server.auth import AuthManager
        auth = AuthManager(config)
        new_token = auth.reset_pair_token()
        logger.info(f"🔑 新连接密码: {new_token}")
        logger.info("⚠️ 旧密码已失效，请在 App 中使用新密码重新连接")

    else:
        parser.print_help()


def _handle_pair(config: AgentConfig, args) -> None:
    """Handle the ``pair`` command: generate pairing code and wait for phone scan.

    Generates a shared secret, derives a short 6-char pairing code, saves the
    pending secret to KeyStore, and optionally displays a QR code.

    Args:
        config: Agent configuration.
        args: Parsed CLI arguments (may contain relay_url).
    """
    from .crypto.crypto_module import CryptoModule
    from .crypto.key_store import KeyStore

    secret = CryptoModule.generate_secret()
    crypto = CryptoModule(secret)

    # Generate pairing info
    # TODO: migrate to relay.mobileflow.dev when DNS is configured
    relay_url = args.relay_url or config.relay_url or "wss://relay.mobileflow.dev"
    device_id = config.ensure_device_id()
    b64url_secret = CryptoModule.secret_to_base64url(secret)
    pair_url = f"mobileflow://pair/{relay_url}/{b64url_secret}"

    logger.info(f"🔑 配对信息:")
    logger.info(f"   Device ID: {device_id}")
    logger.info(f"   Relay URL: {relay_url}")
    logger.info(f"   配对链接: {pair_url}")

    # Generate QR code (if qrcode package is available)
    try:
        import qrcode
        qr = qrcode.QRCode(border=1)
        qr.add_data(pair_url)
        qr.print_ascii(tty=True)
    except ImportError:
        logger.info("   （安装 qrcode 包可显示 QR 码: pip install qrcode）")

    # Generate short pairing code
    import hashlib
    short_code = hashlib.sha256(secret).hexdigest()[:6].upper()
    logger.info(f"   短配对码: {short_code}")
    logger.info("📱 在手机 App 中扫码或输入配对码连接")

    # Save secret (actual device info saved after App confirms pairing)
    key_store = KeyStore(data_dir=config.data_dir)
    key_store.save_secret(f"pending:{short_code}", secret)
    logger.info("⏳ 等待手机连接...")


def _handle_daemon(config: AgentConfig, args) -> None:
    """Handle the ``daemon`` command: start/stop/status/install/uninstall.

    Args:
        config: Agent configuration.
        args: Parsed CLI arguments with daemon_cmd sub-command.
    """
    cmd = args.daemon_cmd
    if not cmd:
        logger.info("用法: mobileflow-agent daemon [start|stop|status|install|uninstall]")
        return

    if cmd == "status":
        from .daemon.state import read_daemon_state
        state = read_daemon_state(config.data_dir)
        if state:
            logger.info(f"🟢 Daemon 运行中")
            logger.info(f"   PID: {state.get('pid', '?')}")
            logger.info(f"   端口: {state.get('http_port', '?')}")
            logger.info(f"   启动时间: {state.get('start_time', '?')}")
            logger.info(f"   上次心跳: {state.get('last_heartbeat', '?')}")
        else:
            logger.info("🔴 Daemon 未运行")

    elif cmd == "start":
        from .daemon.manager import DaemonManager
        daemon = DaemonManager(config)
        try:
            asyncio.run(daemon.start())
        except KeyboardInterrupt:
            logger.info("👋 Daemon 已停止")

    elif cmd == "stop":
        from .daemon.manager import DaemonManager
        daemon = DaemonManager(config)
        asyncio.run(daemon.stop())

    elif cmd in ("install", "uninstall"):
        from .daemon.install import install_service, uninstall_service
        if cmd == "install":
            if install_service(config.data_dir):
                logger.info("✅ 系统服务已安装（开机自启）")
            else:
                logger.error("❌ 系统服务安装失败")
        else:
            if uninstall_service():
                logger.info("✅ 系统服务已卸载")
            else:
                logger.error("❌ 系统服务卸载失败")


def _handle_serve(config: AgentConfig, args, log_buffer=None) -> None:
    """Handle the ``serve`` command: start in Tunnel mode with TLS.

    Args:
        config: Agent configuration (connection_mode set to "tunnel").
        args: Parsed CLI arguments with port, token, tls-cert, tls-key.
        log_buffer: Optional LogBuffer for dashboard log streaming.
    """
    config.connection_mode = "tunnel"
    config.port = args.port
    if args.token:
        config.tunnel_bearer_token = args.token
    if args.tls_cert:
        config.tunnel_tls_cert = args.tls_cert
    if args.tls_key:
        config.tunnel_tls_key = args.tls_key

    logger.info(f"🚀 Tunnel 模式启动: wss://0.0.0.0:{config.port}")
    server = WebSocketServer(config, log_buffer=log_buffer)

    async def _run_with_shutdown():
        try:
            await server.start()
        except asyncio.CancelledError:
            pass
        finally:
            await server.shutdown()

    try:
        asyncio.run(_run_with_shutdown())
    except KeyboardInterrupt:
        logger.info("👋 Agent 已停止")
        asyncio.run(server.shutdown())


def _handle_devices(config: AgentConfig, args) -> None:
    """Handle the ``devices`` command: list or revoke paired devices.

    Args:
        config: Agent configuration.
        args: Parsed CLI arguments with devices_cmd and optional device_id.
    """
    from .crypto.key_store import KeyStore

    key_store = KeyStore(data_dir=config.data_dir)
    cmd = args.devices_cmd

    if cmd == "list":
        devices = key_store.list_devices()
        if not devices:
            logger.info("📱 没有已配对设备")
            return
        logger.info(f"📱 已配对设备 ({len(devices)}):")
        for d in devices:
            import time
            paired = time.strftime("%Y-%m-%d %H:%M", time.localtime(d.paired_at))
            last = time.strftime("%Y-%m-%d %H:%M", time.localtime(d.last_seen)) if d.last_seen > 0 else "从未"
            logger.info(f"   {d.name} ({d.platform}) — ID: {d.device_id[:12]}...")
            logger.info(f"     配对: {paired} | 最后在线: {last}")

    elif cmd == "revoke":
        device_id = args.device_id
        if key_store.remove_device(device_id):
            logger.info(f"✅ 设备已撤销: {device_id}")
        else:
            logger.warning(f"❌ 设备不存在: {device_id}")

    else:
        logger.info("用法: mobileflow-agent devices [list|revoke <device_id>]")


def _handle_status(config: AgentConfig) -> None:
    """Display current Agent status: connection mode, port, devices, etc.

    Args:
        config: Agent configuration.
    """
    from .crypto.key_store import KeyStore

    key_store = KeyStore(data_dir=config.data_dir)
    devices = key_store.list_devices()

    logger.info("📊 MobileFlow Agent 状态")
    logger.info(f"   连接模式: {config.connection_mode}")
    logger.info(f"   端口: {config.port}")
    logger.info(f"   工作目录: {config.work_dir or '当前目录'}")
    logger.info(f"   已配对设备: {len(devices)}")
    if config.relay_url:
        logger.info(f"   Relay URL: {config.relay_url}")


if __name__ == "__main__":
    main()
