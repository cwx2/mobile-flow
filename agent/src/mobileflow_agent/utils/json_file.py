"""
Safe JSON file read/write utilities.

Provides consistent error handling for JSON file operations.
Used across config, session store, plugin loader, daemon state, etc.

All modules should use these helpers instead of calling json.load/dump directly.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from loguru import logger


def load_json_file(path: Path, *, default: Any = None, silent: bool = False) -> Any:
    """Safely load a JSON file, returning default on any error.

    Args:
        path: Path to the JSON file.
        default: Value to return if file doesn't exist or is invalid. Defaults to None.
        silent: If True, suppress warning logs on error.

    Returns:
        Parsed JSON data, or default on error.
    """
    if not path.is_file():
        return default
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data
    except (json.JSONDecodeError, OSError, UnicodeDecodeError) as e:
        if not silent:
            logger.warning(f"JSON 加载失败: {path} — {e}")
        return default


def save_json_file(path: Path, data: Any, *, indent: int = 2) -> bool:
    """Safely write data to a JSON file with consistent formatting.

    Creates parent directories if they don't exist. Uses UTF-8 encoding
    and preserves non-ASCII characters (ensure_ascii=False).

    Args:
        path: Path to the JSON file.
        data: Data to serialize (must be JSON-serializable).
        indent: JSON indentation level. Defaults to 2.

    Returns:
        True if write succeeded, False on error.
    """
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(data, indent=indent, ensure_ascii=False),
            encoding="utf-8",
        )
        return True
    except (OSError, TypeError, ValueError) as e:
        logger.error(f"JSON 写入失败: {path} — {e}")
        return False
