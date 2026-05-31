"""
Path conversion utilities.

Cross-platform path helpers for Windows ↔ WSL path translation.
"""

from __future__ import annotations


def win_to_wsl(path: str) -> str:
    """Convert a Windows path to WSL path format.

    Example: ``C:\\Users\\foo`` → ``/mnt/c/Users/foo``

    Passes through paths that are already in Unix format (no drive letter).

    Args:
        path: Windows-style path string.

    Returns:
        WSL-compatible path string.
    """
    p = path.replace("\\", "/")
    if len(p) >= 2 and p[1] == ":":
        return f"/mnt/{p[0].lower()}{p[2:]}"
    return p


def wsl_to_win(path: str) -> str:
    """Convert a WSL path to Windows path format.

    Example: ``/mnt/c/Users/foo`` → ``C:\\Users\\foo``

    Returns the original path unchanged if it doesn't match ``/mnt/<drive>/...``.

    Args:
        path: WSL-style path string.

    Returns:
        Windows-compatible path string.
    """
    if path.startswith("/mnt/") and len(path) > 5:
        drive = path[5].upper()
        rest = path[6:].replace("/", "\\")
        return f"{drive}:{rest}"
    return path
