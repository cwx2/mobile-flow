# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for MobileFlow Agent.

Builds a single-file executable with system tray support.
Run: pyinstaller build/mobileflow-agent.spec
"""

import sys
from pathlib import Path

# Project root (one level up from build/)
project_root = Path(SPECPATH).parent
src_root = project_root / "src"
config_dir = project_root / "config"

a = Analysis(
    [str(project_root / "entry_point.py")],
    pathex=[str(src_root)],
    binaries=[],
    datas=[
        # Bundle default config
        (str(config_dir / "default.json"), "config"),
        (str(config_dir / "development.json"), "config"),
        (str(config_dir / "production.json"), "config"),
        # Bundle tray icon
        (str(project_root / "assets" / "icon.ico"), "assets"),
        # Bundle dashboard static files (HTML/CSS/JS for web management panel)
        (str(src_root / "mobileflow_agent" / "dashboard" / "static"), "mobileflow_agent/dashboard/static"),
    ],
    hiddenimports=[
        "pystray",
        "pystray._win32" if sys.platform == "win32" else
        "pystray._darwin" if sys.platform == "darwin" else
        "pystray._xorg",
        "PIL",
        "PIL.Image",
        "PIL.ImageDraw",
        "websockets",
        "websockets.legacy",
        "websockets.legacy.server",
        "pydantic",
        "pydantic_settings",
        "loguru",
        "aiohttp",
        "qrcode",
        "nacl",
        "nacl.secret",
        "nacl.utils",
        "keyring",
        "jsonschema",
        "mobileflow_protocol",
        "agent_client_protocol",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[str(project_root / "build" / "runtime_hook_env.py")],
    excludes=[
        "tkinter",
        "unittest",
        "test",
        "pytest",
        "hypothesis",
    ],
    noarchive=False,
    optimize=1,
)

pyz = PYZ(a.pure, a.zipped_data)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="mobileflow-agent",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    # Windows icon
    icon=str(project_root / "assets" / "icon.ico")
    if (project_root / "assets" / "icon.ico").exists()
    else None,
)
