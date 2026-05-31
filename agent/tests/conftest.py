"""
Shared fixtures and helpers for all agent tests.
"""

from __future__ import annotations


class Obj:
    """Simple attribute container to mock ACP SDK pydantic objects."""

    def __init__(self, **kwargs):
        for k, v in kwargs.items():
            setattr(self, k, v)
