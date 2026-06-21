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

    Strategy: try UTF-8 first (git outputs UTF-8 by default on all platforms),
    then fall back to the system codepage on Windows (for rare cases where
    git or other tools use the console codepage).

    Invalid bytes are replaced with the Unicode replacement character (U+FFFD)
    instead of raising an exception.

    This is the ONLY function that should be used for decoding subprocess
    output in the entire codebase. Do not call .decode() directly on
    subprocess output bytes.

    Args:
        data: Raw bytes from subprocess stdout or stderr.

    Returns:
        Decoded string with invalid bytes replaced.
    """
    # Git outputs UTF-8 by default (even on Windows), so try UTF-8 first.
    # Only fall back to system codepage if UTF-8 produces replacement chars
    # AND system codepage produces a cleaner result.
    try:
        result = data.decode("utf-8")
        # If no replacement characters, UTF-8 decode was clean
        if "\ufffd" not in result:
            return result
    except UnicodeDecodeError:
        pass

    # Fallback: system codepage (Windows CP936/GBK, etc.)
    return data.decode(_PROCESS_ENCODING, errors="replace")
