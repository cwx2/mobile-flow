"""
Terminal PTY detection and path conversion tests.

Covers: _create_backend for WSL/native, TerminalSession init,
TerminalManager empty state, _win_to_wsl path conversion.
"""

from __future__ import annotations

import sys

import pytest

from mobileflow_agent.terminal import TerminalSession, TerminalManager
from mobileflow_agent.terminal.session import _create_backend
from mobileflow_agent.utils.path import win_to_wsl


class TestCreateBackend:
    @pytest.mark.skipif(sys.platform != "win32", reason="Windows only")
    def test_wsl_backend_on_windows(self):
        backend = _create_backend("wsl")
        assert type(backend).__name__ == "WslPty"

    @pytest.mark.skipif(sys.platform != "win32", reason="Windows only")
    def test_native_backend_on_windows(self):
        backend = _create_backend("native")
        assert type(backend).__name__ in ("NativePty", "PipePty")

    @pytest.mark.skipif(sys.platform == "win32", reason="Unix only")
    def test_native_backend_on_unix(self):
        backend = _create_backend("native")
        assert type(backend).__name__ == "NativePty"

    @pytest.mark.skipif(sys.platform == "win32", reason="Unix only")
    def test_wsl_backend_on_unix(self):
        backend = _create_backend("wsl")
        assert type(backend).__name__ == "WslPty"


class TestTerminalSessionInit:
    def test_session_id(self):
        s = TerminalSession("test")
        assert s.session_id == "test" and not s.is_running


class TestTerminalManagerEmpty:
    def test_get_nonexistent(self):
        mgr = TerminalManager()
        assert mgr.get_session("x") is None


class TestWinToWsl:
    @pytest.mark.parametrize("win_path,expected", [
        ("C:\\Users\\t", "/mnt/c/Users/t"),
        ("D:\\p", "/mnt/d/p"),
        ("/mnt/c/t", "/mnt/c/t"),
    ])
    def test_path_conversion(self, win_path, expected):
        assert win_to_wsl(win_path) == expected
