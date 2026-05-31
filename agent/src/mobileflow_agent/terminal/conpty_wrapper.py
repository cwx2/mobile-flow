"""Custom ConPTY wrapper using ctypes — workaround for pywinpty bug.

WORKAROUND FOR:
    https://github.com/andfoy/winpty-rs/issues/49
    https://github.com/microsoft/terminal/issues/11276

PROBLEM:
    pywinpty (winpty-rs) does not set STARTF_USESTDHANDLES when calling
    CreateProcess for ConPTY children. When the parent process's stdin
    is not a real console handle (e.g. PyInstaller packaged exe), Windows
    kernel duplicates the parent's non-console handles to the child,
    overriding the pseudoterminal. TUI apps (codex, claude, gemini) then
    detect "stdin is not a terminal" and exit immediately.

    This was fixed in pywinpty v1.1.3 (PR #165) but lost in the v2.0
    Rust rewrite (winpty-rs). The upstream issue remains open.

SOLUTION:
    This module reimplements ConPTY process spawning using ctypes,
    calling the Windows ConPTY API directly with STARTF_USESTDHANDLES
    set and hStdInput/hStdOutput/hStdError set to NULL.
    This prevents Windows from duplicating parent handles to the child.

WHEN TO REMOVE:
    When pywinpty fixes winpty-rs#49, this entire file can be deleted
    and pty_native.py can revert to using PtyProcess directly.
    Check: https://github.com/andfoy/winpty-rs/issues/49

API:
    ConPtyProcess — drop-in replacement for winpty.PtyProcess with the
    same interface: spawn(), read(), write(), isalive(), setwinsize(),
    close(), pid.

Called by:
    terminal/pty_native.py (_start_winpty, only when sys.frozen=True).
"""

from __future__ import annotations

import ctypes
import ctypes.wintypes as wt
import os
from typing import Optional

from loguru import logger

# ── Windows API constants ──

_EXTENDED_STARTUPINFO_PRESENT = 0x00080000
_CREATE_UNICODE_ENVIRONMENT = 0x00000400
_STARTF_USESTDHANDLES = 0x00000100
_PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016
_INVALID_HANDLE = ctypes.c_void_p(-1).value  # INVALID_HANDLE_VALUE
_S_OK = 0
_GENERIC_READ = 0x80000000
_GENERIC_WRITE = 0x40000000
_FILE_SHARE_RW = 0x00000003
_OPEN_EXISTING = 3
_WAIT_TIMEOUT = 0x00000102
_STILL_ACTIVE = 259

_kernel32 = ctypes.windll.kernel32


# ── Windows API structures ──

class _COORD(ctypes.Structure):
    _fields_ = [("X", ctypes.c_short), ("Y", ctypes.c_short)]


class _STARTUPINFOW(ctypes.Structure):
    _fields_ = [
        ("cb", wt.DWORD),
        ("lpReserved", wt.LPWSTR),
        ("lpDesktop", wt.LPWSTR),
        ("lpTitle", wt.LPWSTR),
        ("dwX", wt.DWORD),
        ("dwY", wt.DWORD),
        ("dwXSize", wt.DWORD),
        ("dwYSize", wt.DWORD),
        ("dwXCountChars", wt.DWORD),
        ("dwYCountChars", wt.DWORD),
        ("dwFillAttribute", wt.DWORD),
        ("dwFlags", wt.DWORD),
        ("wShowWindow", wt.WORD),
        ("cbReserved2", wt.WORD),
        ("lpReserved2", ctypes.c_void_p),
        ("hStdInput", wt.HANDLE),
        ("hStdOutput", wt.HANDLE),
        ("hStdError", wt.HANDLE),
    ]


class _STARTUPINFOEXW(ctypes.Structure):
    _fields_ = [
        ("StartupInfo", _STARTUPINFOW),
        ("lpAttributeList", ctypes.c_void_p),
    ]


class _PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("hProcess", wt.HANDLE),
        ("hThread", wt.HANDLE),
        ("dwProcessId", wt.DWORD),
        ("dwThreadId", wt.DWORD),
    ]



class ConPtyProcess:
    """Drop-in replacement for winpty.PtyProcess with correct handle inheritance.

    Uses Windows ConPTY API directly via ctypes, setting STARTF_USESTDHANDLES
    with NULL handles to prevent parent handle duplication.

    Attributes:
        pid: Process ID of the spawned child.
    """

    def __init__(self):
        self._hpc: Optional[ctypes.c_void_p] = None  # HPCON
        self._h_input_write: Optional[int] = None     # pipe: we write → child reads
        self._h_output_read: Optional[int] = None     # pipe: child writes → we read
        self._h_process: Optional[int] = None
        self._h_thread: Optional[int] = None
        self._pid: int = 0
        self._closed = False

    @staticmethod
    def spawn(
        command: str,
        dimensions: tuple[int, int] = (24, 80),
        cwd: str | None = None,
        env: dict[str, str] | None = None,
    ) -> "ConPtyProcess":
        """Spawn a process inside a ConPTY pseudoterminal.

        Args:
            command: Command string to execute.
            dimensions: (rows, cols) terminal size.
            cwd: Working directory for the child process.
            env: Environment variables dict. If None, inherits parent env.

        Returns:
            A ConPtyProcess instance.

        Raises:
            OSError: If any Windows API call fails.
        """
        proc = ConPtyProcess()
        rows, cols = dimensions

        # Step 1: Create pipes for ConPTY communication
        h_input_read = wt.HANDLE()
        h_input_write = wt.HANDLE()
        h_output_read = wt.HANDLE()
        h_output_write = wt.HANDLE()

        if not _kernel32.CreatePipe(ctypes.byref(h_input_read), ctypes.byref(h_input_write), None, 0):
            raise OSError(f"CreatePipe (input) failed: {ctypes.GetLastError()}")
        if not _kernel32.CreatePipe(ctypes.byref(h_output_read), ctypes.byref(h_output_write), None, 0):
            _kernel32.CloseHandle(h_input_read)
            _kernel32.CloseHandle(h_input_write)
            raise OSError(f"CreatePipe (output) failed: {ctypes.GetLastError()}")

        # Step 2: Create the pseudoconsole
        size = _COORD(X=ctypes.c_short(cols), Y=ctypes.c_short(rows))
        hpc = ctypes.c_void_p()
        hr = _kernel32.CreatePseudoConsole(
            size, h_input_read, h_output_write, 0, ctypes.byref(hpc),
        )
        if hr != _S_OK:
            for h in (h_input_read, h_input_write, h_output_read, h_output_write):
                _kernel32.CloseHandle(h)
            raise OSError(f"CreatePseudoConsole failed: HRESULT=0x{hr & 0xFFFFFFFF:08X}")

        # Close the pipe ends that the pseudoconsole now owns
        _kernel32.CloseHandle(h_input_read)
        _kernel32.CloseHandle(h_output_write)

        proc._hpc = hpc
        proc._h_input_write = h_input_write.value
        proc._h_output_read = h_output_read.value

        # Step 3: Prepare STARTUPINFOEX with pseudoconsole attribute
        attr_size = ctypes.c_size_t(0)
        _kernel32.InitializeProcThreadAttributeList(None, 1, 0, ctypes.byref(attr_size))
        attr_buf = ctypes.create_string_buffer(attr_size.value)
        attr_list = ctypes.cast(attr_buf, ctypes.c_void_p)

        if not _kernel32.InitializeProcThreadAttributeList(attr_list, 1, 0, ctypes.byref(attr_size)):
            raise OSError(f"InitializeProcThreadAttributeList failed: {ctypes.GetLastError()}")

        if not _kernel32.UpdateProcThreadAttribute(
            attr_list, 0, _PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            hpc, ctypes.sizeof(ctypes.c_void_p), None, None,
        ):
            raise OSError(f"UpdateProcThreadAttribute failed: {ctypes.GetLastError()}")

        si_ex = _STARTUPINFOEXW()
        si_ex.StartupInfo.cb = ctypes.sizeof(_STARTUPINFOEXW)
        si_ex.lpAttributeList = attr_list

        # KEY FIX: Set STARTF_USESTDHANDLES with NULL handles (not
        # INVALID_HANDLE_VALUE). This is the exact fix used by ttyd
        # (github.com/tsl0922/ttyd) and recommended by Microsoft
        # (github.com/microsoft/terminal/issues/11276).
        # It prevents Windows from duplicating parent's std handles
        # to the child process, letting ConPTY properly take over.
        si_ex.StartupInfo.dwFlags = _STARTF_USESTDHANDLES
        si_ex.StartupInfo.hStdInput = None
        si_ex.StartupInfo.hStdOutput = None
        si_ex.StartupInfo.hStdError = None

        # Step 4: Build environment block (null-separated, double-null terminated)
        env_block = None
        if env is not None:
            parts = [f"{k}={v}" for k, v in env.items()]
            env_str = "\0".join(parts) + "\0\0"
            env_block = ctypes.create_unicode_buffer(env_str)

        # Step 5: CreateProcess
        pi = _PROCESS_INFORMATION()
        cmd_buf = ctypes.create_unicode_buffer(command)

        success = _kernel32.CreateProcessW(
            None,                           # lpApplicationName
            cmd_buf,                        # lpCommandLine
            None,                           # lpProcessAttributes
            None,                           # lpThreadAttributes
            False,                          # bInheritHandles
            _EXTENDED_STARTUPINFO_PRESENT | _CREATE_UNICODE_ENVIRONMENT,  # dwCreationFlags
            env_block,                      # lpEnvironment
            cwd,                            # lpCurrentDirectory
            ctypes.byref(si_ex.StartupInfo),  # lpStartupInfo
            ctypes.byref(pi),               # lpProcessInformation
        )

        _kernel32.DeleteProcThreadAttributeList(attr_list)

        if not success:
            err = ctypes.GetLastError()
            proc.close()
            raise OSError(f"CreateProcessW failed: error={err}")

        proc._h_process = pi.hProcess
        proc._h_thread = pi.hThread
        proc._pid = pi.dwProcessId

        logger.debug(f"ConPtyProcess spawned: pid={proc._pid}, cmd={command!r}")
        return proc

    @property
    def pid(self) -> int:
        """Process ID of the child."""
        return self._pid

    def read(self, size: int = 4096) -> str:
        """Read output from the pseudoterminal.

        Args:
            size: Maximum bytes to read.

        Returns:
            Decoded string output.

        Raises:
            EOFError: If the pipe is broken (child exited).
        """
        if self._closed or self._h_output_read is None:
            raise EOFError("Pty is closed")

        buf = ctypes.create_string_buffer(size)
        bytes_read = wt.DWORD(0)
        ok = _kernel32.ReadFile(
            wt.HANDLE(self._h_output_read),
            buf, size, ctypes.byref(bytes_read), None,
        )
        if not ok or bytes_read.value == 0:
            raise EOFError("Pty is closed")

        return buf.raw[:bytes_read.value].decode("utf-8", errors="replace")

    def write(self, data: str) -> None:
        """Write input to the pseudoterminal.

        Args:
            data: String to send to the child process.
        """
        if self._closed or self._h_input_write is None:
            return

        encoded = data.encode("utf-8")
        written = wt.DWORD(0)
        _kernel32.WriteFile(
            wt.HANDLE(self._h_input_write),
            encoded, len(encoded), ctypes.byref(written), None,
        )

    def setwinsize(self, rows: int, cols: int) -> None:
        """Resize the pseudoterminal.

        Args:
            rows: New height in rows.
            cols: New width in columns.
        """
        if self._hpc is None:
            return
        size = _COORD(X=ctypes.c_short(cols), Y=ctypes.c_short(rows))
        _kernel32.ResizePseudoConsole(self._hpc, size)

    def isalive(self) -> bool:
        """Check if the child process is still running."""
        if self._closed or self._h_process is None:
            return False
        code = wt.DWORD(0)
        _kernel32.GetExitCodeProcess(wt.HANDLE(self._h_process), ctypes.byref(code))
        return code.value == _STILL_ACTIVE

    def close(self) -> None:
        """Close the pseudoconsole and all handles."""
        if self._closed:
            return
        self._closed = True

        if self._hpc is not None:
            _kernel32.ClosePseudoConsole(self._hpc)
            self._hpc = None

        for h in (self._h_input_write, self._h_output_read, self._h_process, self._h_thread):
            if h is not None:
                _kernel32.CloseHandle(wt.HANDLE(h))

        self._h_input_write = None
        self._h_output_read = None
        self._h_process = None
        self._h_thread = None
