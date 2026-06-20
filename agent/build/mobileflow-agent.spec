# -*- mode: python ; coding: utf-8 -*-
# MobileFlow Agent PyInstaller spec file.
# Build with: python build/scripts/build.py

a = Analysis(
    ['..\\entry_point.py'],
    pathex=['..\\src'],
    binaries=[],
    datas=[('..\\locales', 'locales'), ('..\\config', 'config'), ('..\\assets', 'assets'), ('..\\src\\mobileflow_agent\\dashboard\\static', 'mobileflow_agent/dashboard/static')],
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
    icon='..\\assets\\icon.ico',
)
