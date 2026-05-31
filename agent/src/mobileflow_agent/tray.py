"""System tray icon for MobileFlow Agent.

Provides a cross-platform system tray icon (Windows/macOS/Linux) using
pystray. Shows connection status, password, and a link to the web dashboard.

The tray runs on the main thread while the WebSocket server runs in a
background thread via asyncio. Thread-safe communication uses a shared
state object protected by a threading lock.

Architecture:
    Main thread  → pystray event loop (blocking)
    Sub thread   → asyncio event loop (WebSocket server + dashboard)
    Shared state → TrayState (lock-protected)
"""

from __future__ import annotations

import asyncio
import sys
import threading
from dataclasses import dataclass, field

from loguru import logger

from .core.config import AgentConfig
from .utils.i18n import t


@dataclass
class TrayState:
    """Thread-safe shared state between tray and server.

    All fields are read/written under ``lock`` to prevent data races
    between the pystray main thread and the asyncio server thread.
    """

    lock: threading.Lock = field(default_factory=threading.Lock)
    connected_clients: int = 0
    pair_token: str = ""
    host: str = ""
    port: int = 9600
    running: bool = True


def _load_icon_file():
    """Try to load the custom icon from assets/icon.ico."""
    from pathlib import Path
    from PIL import Image

    candidates = [
        Path(getattr(sys, '_MEIPASS', '')) / "assets" / "icon.ico",
        Path(__file__).resolve().parent.parent.parent.parent / "assets" / "icon.ico",
        Path("assets") / "icon.ico",
    ]
    for path in candidates:
        if path.is_file():
            logger.debug(f"托盘图标已加载: {path}")
            return Image.open(path)
    return None


def _create_icon_image(connected: bool):
    """Get the tray icon image (custom or generated fallback)."""
    from PIL import Image, ImageDraw

    custom = _load_icon_file()
    if custom is not None:
        return custom

    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = (76, 175, 80, 255) if connected else (158, 158, 158, 255)
    draw.ellipse([4, 4, size - 4, size - 4], fill=color)
    draw.text((18, 14), "</>", fill=(255, 255, 255, 255))
    return img


def _copy_to_clipboard(text: str) -> None:
    """Copy text to system clipboard (cross-platform)."""
    import subprocess
    try:
        if sys.platform == "win32":
            subprocess.run(
                ["clip"], input=text.encode("utf-8"),
                check=True, creationflags=0x08000000,
            )
        elif sys.platform == "darwin":
            subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)
        else:
            try:
                subprocess.run(
                    ["xclip", "-selection", "clipboard"],
                    input=text.encode("utf-8"), check=True)
            except FileNotFoundError:
                subprocess.run(
                    ["xsel", "--clipboard", "--input"],
                    input=text.encode("utf-8"), check=True)
    except Exception as e:
        logger.warning(f"复制到剪贴板失败: {e}")


def run_tray(config: AgentConfig, state: TrayState, stop_event: threading.Event) -> None:
    """Run the system tray icon (blocking, call from main thread).

    Menu items:
      - Connection status (read-only)
      - Address (click to copy)
      - Password (click to copy)
      - Open dashboard (opens browser)
      - Quit

    Args:
        config: Agent configuration.
        state: Shared state object for server ↔ tray communication.
        stop_event: Set this event to signal the server thread to stop.
    """
    import pystray

    def _get_status_text() -> str:
        with state.lock:
            clients = state.connected_clients
        return t("backend.trayConnected", count=str(clients)) if clients > 0 else t("backend.trayWaiting")

    def _on_copy_address(icon, item):
        with state.lock:
            addr = f"ws://{state.host}:{state.port}"
        _copy_to_clipboard(addr)

    def _on_copy_password(icon, item):
        with state.lock:
            pwd = state.pair_token
        _copy_to_clipboard(pwd)

    def _on_open_dashboard(icon, item):
        import webbrowser
        with state.lock:
            port = state.port
        webbrowser.open(f"http://localhost:{port}")

    def _on_quit(icon, item):
        logger.info("👋 用户从托盘退出")
        stop_event.set()
        icon.stop()

    def _build_menu():
        return pystray.Menu(
            pystray.MenuItem(lambda _t: _get_status_text(), None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem(
                lambda _t: t("backend.trayAddress", addr=f"{state.host}:{state.port}"), _on_copy_address),
            pystray.MenuItem(
                lambda _t: t("backend.trayPassword", pwd=state.pair_token), _on_copy_password),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem(t("backend.trayOpenDashboard"), _on_open_dashboard),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem(t("backend.trayQuit"), _on_quit),
        )

    icon = pystray.Icon(
        name="MobileFlow Agent",
        icon=_create_icon_image(connected=False),
        title="MobileFlow Agent",
        menu=_build_menu(),
    )

    # Periodic icon update
    def _update_loop():
        last_connected = False
        while not stop_event.is_set():
            with state.lock:
                connected = state.connected_clients > 0
            if connected != last_connected:
                icon.icon = _create_icon_image(connected)
                last_connected = connected
            stop_event.wait(timeout=2.0)
        try:
            icon.stop()
        except Exception as e:
            logger.debug(f"托盘图标停止出错（可忽略）: {e}")

    threading.Thread(target=_update_loop, daemon=True).start()
    logger.info("🖥️ 系统托盘已启动")
    icon.run()


def start_with_tray(config: AgentConfig, log_buffer=None) -> None:
    """Start the Agent with system tray (main entry point for packaged app).

    Runs the tray on the main thread and the WebSocket server on a
    background thread. Auto-opens the dashboard in the browser on first start.

    Args:
        config: Agent configuration.
    """
    from .server.websocket import WebSocketServer

    state = TrayState(port=config.port)
    stop_event = threading.Event()
    server_ready = threading.Event()

    # Resolve local IP
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        state.host = s.getsockname()[0]
        s.close()
    except Exception as e:
        logger.debug(f"LAN IP 检测失败: {e}")
        state.host = "127.0.0.1"

    server = WebSocketServer(config, log_buffer=log_buffer)

    def _server_thread():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        async def _run():
            server_task = asyncio.create_task(server.start())
            await asyncio.sleep(0.1)
            with state.lock:
                token, _ = server.auth.ensure_pair_token()
                state.pair_token = token
            server_ready.set()

            while not stop_event.is_set():
                with state.lock:
                    state.connected_clients = server.client_count
                await asyncio.sleep(0.5)

            await server.shutdown()
            server_task.cancel()
            try:
                await server_task
            except asyncio.CancelledError:
                pass

        try:
            loop.run_until_complete(_run())
        except Exception as e:
            logger.error(f"服务器线程异常: {e}")
        finally:
            loop.close()

    srv_thread = threading.Thread(target=_server_thread, daemon=True)
    srv_thread.start()
    server_ready.wait(timeout=10.0)

    # Auto-open dashboard in browser
    import webbrowser
    webbrowser.open(f"http://localhost:{config.port}")

    try:
        run_tray(config, state, stop_event)
    except Exception as e:
        logger.error(f"托盘异常: {e}")
    finally:
        stop_event.set()
        srv_thread.join(timeout=5)
        logger.info("👋 Agent 已退出")
