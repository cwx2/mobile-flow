"""Backend internationalization utility using python-i18n.

Loads translations from external JSON files in the locales/ directory.
New languages can be added by creating a new JSON file (e.g. ja.json)
without modifying any code.

Architecture:
    - Uses python-i18n library (pip install python-i18n[json])
    - Translation files: agent/locales/{locale}.json
    - Locale set per-request via contextvars (async-safe)
    - t(key, **kwargs) returns translated string with placeholder substitution
    - Fallback: requested locale → English → key itself

File structure:
    agent/
    ├── locales/
    │   ├── en.json    ← English translations
    │   ├── zh.json    ← Chinese translations
    │   └── ...        ← Add new languages here
    └── src/
        └── mobileflow_agent/
            └── utils/
                └── i18n.py  ← This file (loader only, no text)

Usage:
    from ..utils.i18n import t, set_locale

    set_locale("en")
    t("backend.installSuccess", name="Claude Code")
    # → "Claude Code installed successfully"

    set_locale("zh")
    t("backend.installSuccess", name="Claude Code")
    # → "Claude Code 安装成功"
"""

from __future__ import annotations

import contextvars
import sys
from pathlib import Path

import i18n

# ── Configure python-i18n ──

# Locate the locales directory.
# Development: utils/i18n.py → parent(utils) → parent(mobileflow_agent) → parent(src) → parent(agent) → locales/
# PyInstaller: sys._MEIPASS/locales/
def _find_locales_dir() -> Path:
    """Find the i18n directory for translation files.

    Shared with the Dashboard frontend — both Python backend and
    browser JS load from the same directory.
    """
    # PyInstaller bundle
    meipass = getattr(sys, '_MEIPASS', None)
    if meipass:
        candidate = Path(meipass) / "mobileflow_agent" / "dashboard" / "static" / "i18n"
        if candidate.is_dir():
            return candidate

    # Development: relative to this file
    # utils/i18n.py → mobileflow_agent/utils/ → mobileflow_agent/ → dashboard/static/i18n/
    candidate = Path(__file__).resolve().parent.parent / "dashboard" / "static" / "i18n"
    if candidate.is_dir():
        return candidate

    # Fallback: old locales/ path
    candidate = Path(__file__).resolve().parent.parent.parent.parent / "locales"
    if candidate.is_dir():
        return candidate

    return Path("locales")


_LOCALES_DIR = _find_locales_dir()

# Configure python-i18n to use JSON files with simple {locale}.json naming
i18n.set('file_format', 'json')
i18n.set('filename_format', '{locale}.{format}')
i18n.set('load_path', [str(_LOCALES_DIR)])
i18n.set('fallback', 'en')
i18n.set('enable_memoization', True)
i18n.set('skip_locale_root_data', True)

# ── Per-request locale via contextvars (async-safe) ──

_current_locale: contextvars.ContextVar[str] = contextvars.ContextVar("locale", default="zh")


def set_locale(locale: str) -> None:
    """Set the locale for the current async context.

    Called at request boundaries:
    - Dashboard HTTP: parsed from Accept-Language header
    - WebSocket: set during auth from client locale field

    Args:
        locale: Language code (e.g. "en", "zh", "en-US", "zh-CN").
            Normalized to 2-letter code.
    """
    normalized = "en" if locale.startswith("en") else "zh"
    _current_locale.set(normalized)


def get_locale() -> str:
    """Get the current locale for the active context.

    Returns:
        2-letter locale code (e.g. "en", "zh").
    """
    return _current_locale.get()


def t(key: str, **kwargs) -> str:
    """Translate a message key using the current locale.

    Uses python-i18n's t() with the locale from the current async context.
    Supports named placeholders: %{name}, %{count}, etc.

    Args:
        key: Dot-separated translation key (e.g. "backend.installSuccess").
        **kwargs: Named placeholder values for substitution.

    Returns:
        Translated string. Falls back to English, then to the key itself.
    """
    locale = _current_locale.get()
    return i18n.t(key, locale=locale, **kwargs)
