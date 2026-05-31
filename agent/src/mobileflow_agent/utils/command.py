"""
Command resolution utilities.

Resolves CLI commands to full paths via ``shutil.which()``, handles Windows
.cmd/.bat wrapping for subprocess execution. All modules should use these
helpers instead of calling ``shutil.which()`` directly.
"""

from __future__ import annotations

import shutil
import sys


def resolve_command_str(cli_command: str) -> str:
    """Resolve a CLI command string to a full path for shell-like execution.

    On Windows, wraps .cmd/.bat files with ``cmd /c`` so they can be executed
    by WinPTY or subprocess. Avoids quoting the path because ConPTY
    misparses ``cmd /c "path"`` in tight read loops — instead uses the
    Windows short (8.3) path when the resolved path contains spaces.

    Args:
        cli_command: Space-separated command string (e.g. "npm test").

    Returns:
        Resolved command string. Example on Windows:
        ``'cmd /c C:\\Users\\...\\npm.cmd test'``
    """
    parts = cli_command.split()
    if not parts:
        return cli_command
    resolved = shutil.which(parts[0]) or parts[0]
    if sys.platform == "win32" and resolved.lower().endswith((".cmd", ".bat")):
        # Avoid quoting — ConPTY misparses cmd /c "path" in tight
        # read loops. Use short path (8.3) if the path has spaces.
        if " " in resolved:
            resolved = _get_short_path(resolved)
        args_str = " ".join(parts[1:])
        return f'cmd /c {resolved} {args_str}'.strip()
    return f'{resolved} {" ".join(parts[1:])}'.strip()


def _get_short_path(long_path: str) -> str:
    """Convert a Windows long path to its short (8.3) equivalent.

    Falls back to quoting if the conversion fails (e.g. 8.3 names
    are disabled on the volume).

    Args:
        long_path: Full Windows path that may contain spaces.

    Returns:
        Short path without spaces, or the original path quoted.
    """
    try:
        import ctypes
        buf = ctypes.create_unicode_buffer(512)
        result = ctypes.windll.kernel32.GetShortPathNameW(long_path, buf, 512)
        if result > 0:
            return buf.value
    except Exception as e:
        logger.debug(f"短路径转换失败，回退到引号包裹: path={long_path}, error={e}")
    # Fallback: quote the path (may still fail in some ConPTY scenarios)
    return f'"{long_path}"'


def resolve_command_list(cli_command: str) -> list[str]:
    """Resolve a CLI command string to an argv list for subprocess execution.

    On Windows, wraps .cmd/.bat files with ``["cmd", "/c", ...]`` so they
    can be passed to ``asyncio.create_subprocess_exec()``.

    Args:
        cli_command: Space-separated command string (e.g. "npm test").

    Returns:
        Argv list. Example on Windows:
        ``["cmd", "/c", "C:\\...\\npm.cmd", "test"]``
    """
    parts = cli_command.split()
    if not parts:
        return [cli_command]
    resolved = shutil.which(parts[0]) or parts[0]
    if sys.platform == "win32" and resolved.lower().endswith((".cmd", ".bat")):
        return ["cmd", "/c", resolved] + parts[1:]
    return [resolved] + parts[1:]


def which(command: str) -> str | None:
    """Find a command in PATH.

    On Windows, prioritizes .cmd/.exe extensions over extensionless files
    to avoid returning shell scripts that WinPTY cannot execute.

    Args:
        command: Command name to search for (e.g. "codex-acp", "git").

    Returns:
        Full path to the command, or None if not found.
    """
    import sys
    result = shutil.which(command)

    # On Windows, if the result has no extension (likely a shell script),
    # try to find the .cmd version which is the correct Windows wrapper.
    if result and sys.platform == "win32":
        from pathlib import Path
        p = Path(result)
        if not p.suffix:
            # Try .cmd first, then .exe
            cmd_path = shutil.which(command + ".cmd")
            if cmd_path:
                return cmd_path
            exe_path = shutil.which(command + ".exe")
            if exe_path:
                return exe_path

    return result
