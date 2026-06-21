# -*- mode: python ; coding: utf-8 -*-
# MobileFlow Agent PyInstaller spec file.
# Build with: python build/scripts/build.py
#
# All paths use forward slashes for cross-platform compatibility.

import os
from pathlib import Path

# Resolve paths relative to this spec file's location (agent/build/)
spec_dir = os.path.dirname(os.path.abspath(SPEC))
agent_root = os.path.dirname(spec_dir)

a = Analysis(
    [os.path.join(agent_root, 'entry_point.py')],
    pathex=[os.path.join(agent_root, 'src')],
    binaries=[],
    datas=[
        (os.path.join(agent_root, 'locales'), 'locales'),
        (os.path.join(agent_root, 'config'), 'config'),
        (os.path.join(agent_root, 'assets'), 'assets'),
        (os.path.join(agent_root, 'src', 'mobileflow_agent', 'dashboard', 'static'), 'mobileflow_agent/dashboard/static'),
    ],
    hiddenimports=['mobileflow_agent'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='mobileflow-agent',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=os.path.join(agent_root, 'assets', 'icon.ico'),
)
