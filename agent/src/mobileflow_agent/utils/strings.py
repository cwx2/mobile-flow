"""
String utility functions.

General-purpose string helpers used across multiple modules.
"""

from __future__ import annotations

import re
from typing import Any


# ANSI escape sequence pattern (CSI sequences, OSC sequences, charset switches)
_ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[()][AB012]')


def strip_ansi(text: str) -> str:
    """Strip ANSI escape sequences from text.

    Removes terminal color codes, cursor movement, and other ANSI
    sequences that CLIs embed in stdout. Essential when parsing
    structured data (URLs, codes) from CLI output.

    Args:
        text: Raw text potentially containing ANSI sequences.

    Returns:
        Clean text with all ANSI sequences removed.
    """
    return _ANSI_RE.sub('', text)


def safe_str(v: Any) -> str:
    """Safely convert any value to string.

    Args:
        v: Value to convert. None returns empty string.

    Returns:
        String representation, or "" for None.
    """
    if v is None:
        return ""
    return str(v)


def truncate(s: str, max_len: int = 200, suffix: str = "...") -> str:
    """Truncate a string to max_len, appending suffix if truncated.

    Args:
        s: String to truncate.
        max_len: Maximum length before truncation. Defaults to 200.
        suffix: Suffix to append when truncated. Defaults to "...".

    Returns:
        Original string if within limit, otherwise truncated with suffix.
    """
    if len(s) <= max_len:
        return s
    return s[:max_len] + suffix
