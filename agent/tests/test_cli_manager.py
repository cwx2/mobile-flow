"""
CLIManager._event_to_chunk tests.

Covers conversion of AgentEvent to StreamChunk for WebSocket delivery.
"""

from __future__ import annotations

import pytest

from mobileflow_agent.services.cli_manager import CLIManager
from mobileflow_agent.providers.base import AgentEvent, AgentEventType


_f = CLIManager._event_to_chunk


class TestEventToChunk:
    def test_text_chunk(self):
        c = _f(AgentEvent(type=AgentEventType.TEXT_CHUNK, data={"text": "hello"}))
        assert c.type.value == "text" and c.content == "hello"

    def test_thought_chunk(self):
        c = _f(AgentEvent(type=AgentEventType.THOUGHT_CHUNK, data={"text": "hmm"}))
        assert c.type.value == "thinking"

    def test_file_edit_diff(self):
        c = _f(AgentEvent(type=AgentEventType.FILE_EDIT, data={"path": "a.py", "full_old": "old", "full_new": "new"}))
        assert c.type.value == "diff"
        assert c.file_path == "a.py"
        assert c.old_content == "old"
        assert c.new_content == "new"

    def test_tool_call_start(self):
        c = _f(AgentEvent(type=AgentEventType.TOOL_CALL_START, data={
            "name": "grep", "kind": "search", "id": "t1", "status": "running",
        }))
        assert c.type.value == "tool_use" and c.content == "grep"

    def test_tool_call_update(self):
        c = _f(AgentEvent(type=AgentEventType.TOOL_CALL_UPDATE, data={
            "id": "t1", "name": "grep", "status": "completed",
        }))
        assert c.type.value == "tool_update" and c.status == "completed"

    def test_error(self):
        c = _f(AgentEvent(type=AgentEventType.ERROR, data={"error": "boom"}))
        assert c.type.value == "error" and c.content == "boom"

    def test_turn_end_returns_none(self):
        c = _f(AgentEvent(type=AgentEventType.TURN_END, data={}))
        assert c is None

    def test_plan_update(self):
        c = _f(AgentEvent(type=AgentEventType.PLAN_UPDATE, data={"entries": [{"title": "Step 1", "status": "pending"}]}))
        assert c is not None and c.type.value == "text"
