"""Subprocess output encoding utilities.

Provides a single function for decoding subprocess stdout/stderr bytes
to str, handling the platform encoding difference transparently:
  - Windows: console output uses the system codepage (typically CP936/GBK
    for Chinese, CP1252 for Western European, etc.)
  - macOS/Linux: subprocess output is UTF-8

All code that reads subprocess output MUST use decode_process_output()
instead of calling .decode() directly. This ensures consistent behavior
across platforms without each caller needing to know about encoding.

Usage:
    from ..utils.encoding import decode_process_output

    stdout, stderr = await proc.communicate()
    text = decode_process_output(stdout)
"""

from __future__ import annotations

import locale
import sys

# Resolve the system's subprocess output encoding once at import time.
# On Windows this is typically 'cp936' (Chinese) or 'cp1252' (Western).
# On macOS/Linux this is 'UTF-8'.
if sys.platform == "win32":
    _PROCESS_ENCODING = locale.getpreferredencoding(False)
else:
    _PROCESS_ENCODING = "utf-8"


def decode_process_output(data: bytes) -> str:
    """Decode subprocess stdout/stderr bytes to string.

    Uses the system's console codepage on Windows (e.g. CP936 for Chinese),
    UTF-8 on macOS/Linux. Invalid bytes are replaced with the Unicode
    replacement character (U+FFFD) instead of raising an exception.

    This is the ONLY function that should be used for decoding subprocess
    output in the entire codebase. Do not call .decode() directly on
    subprocess output bytes.

    Args:
        data: Raw bytes from subprocess stdout or stderr.

    Returns:
        Decoded string with invalid bytes replaced.
    """
    return data.decode(_PROCESS_ENCODING, errors="replace")
