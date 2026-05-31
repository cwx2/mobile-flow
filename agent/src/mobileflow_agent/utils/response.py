"""Unified response builder for user-facing API responses.

Provides a consistent response structure for all Agent → Client
communication (both Dashboard HTTP and WebSocket message payloads).

Inspired by Java's R<T> pattern: every response has a predictable
shape so the frontend can handle success/failure uniformly.

Usage:
    from ..utils.response import R

    R.ok("Install successful")
    # → {"success": True, "message": "Install successful"}

    R.ok(data={"adapters": [...]})
    # → {"success": True, "data": {"adapters": [...]}}

    R.fail("npm not found")
    # → {"success": False, "message": "npm not found"}

    # With i18n:
    from ..utils.i18n import t
    R.ok(t("backend.installSuccess", "Claude Code"))
    R.fail(t("backend.npmNotFound"))
"""

from __future__ import annotations

from typing import Any


class R:
    """Unified response builder.

    All methods return a plain dict suitable for JSON serialization.
    The structure is always:
        {"success": bool, "message": str, ...extra_fields}
    """

    @staticmethod
    def ok(message: str = "", **kwargs: Any) -> dict:
        """Build a success response.

        Args:
            message: Optional success message for the user.
            **kwargs: Additional fields to include in the response
                (e.g. data, adapters, configuration).

        Returns:
            Dict with success=True, message, and any extra fields.
        """
        result = {"success": True, "message": message}
        result.update(kwargs)
        return result

    @staticmethod
    def fail(message: str, **kwargs: Any) -> dict:
        """Build a failure response.

        Args:
            message: Error message for the user (already translated).
            **kwargs: Additional fields to include in the response
                (e.g. code, error, details).

        Returns:
            Dict with success=False, message, and any extra fields.
        """
        result = {"success": False, "message": message}
        result.update(kwargs)
        return result
