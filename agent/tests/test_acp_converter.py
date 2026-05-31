"""
ACPEventConverter tests.

Covers: event conversion, content blocks, helper functions, tool_calls,
content parsing, prompt_turn, initialization, agent_plan, slash_commands,
session_list, session_config, overview, schema, extensibility,
session_modes, session_setup, terminals, file_system.
"""

from __future__ import annotations

import pytest
from conftest import Obj


# ── ACPEventConverter core ──


class TestACPEventConverter:
    def setup_method(self):
        from mobileflow_agent.providers.acp_converter import ACPEventConverter
        self.conv = ACPEventConverter()

    def _type(self, event):
        from mobileflow_agent.providers.base import AgentEventType
        return event.type if event else None

    def test_text_chunk(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(session_update="agent_message_chunk", content=Obj(type="text", text="Hello"), message_id=None))
        assert e is not None and e.type == AgentEventType.TEXT_CHUNK
        assert e.data["text"] == "Hello"

    def test_empty_text_returns_none(self):
        e = self.conv.convert(Obj(session_update="agent_message_chunk", content=Obj(type="text", text=""), message_id=None))
        assert e is None

    def test_user_message_chunk(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(session_update="user_message_chunk", content=Obj(type="text", text="Hi"), message_id=None))
        assert e is not None and e.type == AgentEventType.USER_MESSAGE

    def test_thought_chunk(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(session_update="agent_thought_chunk", content=Obj(type="text", text="thinking"), thought=None))
        assert e is not None and e.type == AgentEventType.THOUGHT_CHUNK

    def test_tool_call_start(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(
            session_update="tool_call", tool_call_id="tc_1", title="read file",
            kind="read", status="in_progress", content=None, locations=None,
            raw_input=None, raw_output=None,
        ))
        assert e.type == AgentEventType.TOOL_CALL_START
        assert e.data["name"] == "read file"
        assert e.data["kind"] == "read"

    def test_tool_call_update(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(
            session_update="tool_call_update", tool_call_id="tc_1", title="read file",
            kind="read", status="completed", content=None,
            locations=[Obj(path="/a.py", line=10)],
            raw_input=None, raw_output={"items": [{"Text": "done"}]},
        ))
        assert e.type == AgentEventType.TOOL_CALL_UPDATE
        assert e.data["status"] == "completed"

    def test_tool_call_diff_becomes_file_edit(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(
            session_update="tool_call", tool_call_id="tc_2", title="Editing a.py",
            kind="edit", status="completed",
            content=[Obj(type="diff", path="/a.py", old_text="old code", new_text="new code")],
            locations=None, raw_input=None, raw_output=None,
        ))
        assert e.type == AgentEventType.FILE_EDIT
        assert e.data["full_old"] == "old code"
        assert e.data["full_new"] == "new code"

    def test_plan_update(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(
            session_update="plan",
            entries=[Obj(content="Step 1", priority="high", status="pending", title=None)],
        ))
        assert e.type == AgentEventType.PLAN_UPDATE
        assert e.data["entries"][0]["title"] == "Step 1"

    def test_commands_available(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(
            session_update="available_commands_update",
            available_commands=[Obj(name="test", description="Run tests", input=None)],
        ))
        assert e.type == AgentEventType.COMMANDS_AVAILABLE

    def test_mode_change(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(session_update="current_mode_update", mode_id="code"))
        assert e.type == AgentEventType.MODE_CHANGE and e.data["mode_id"] == "code"

    def test_session_info(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(session_update="session_info_update", context_usage_percentage=0.75))
        assert e.type == AgentEventType.SESSION_INFO

    def test_unknown_returns_none(self):
        e = self.conv.convert(Obj(session_update="totally_unknown_type"))
        assert e is None


# ── Content blocks (SDK-style) ──


class TestConverterContentBlocks:
    def setup_method(self):
        from mobileflow_agent.providers.acp_converter import ACPEventConverter
        self.conv = ACPEventConverter()

    def test_tool_call_with_text_content(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(
            session_update="tool_call", tool_call_id="tc_10", title="Read file",
            kind="read", status="completed",
            content=[Obj(type="content", content=Obj(type="text", text="file contents here"))],
            locations=[Obj(path="/src/main.py", line=1)],
            raw_input={"path": "/src/main.py"}, raw_output=None,
        ))
        assert e.type == AgentEventType.TOOL_CALL_START
        assert len(e.data["content_blocks"]) == 1
        assert e.data["content_blocks"][0]["type"] == "text"
        assert e.data["content_blocks"][0]["text"] == "file contents here"
        assert e.data["tool_input"] == "/src/main.py"

    def test_tool_call_with_terminal_content(self):
        e = self.conv.convert(Obj(
            session_update="tool_call", tool_call_id="tc_11", title="Run npm test",
            kind="execute", status="in_progress",
            content=[Obj(type="terminal", terminal_id="term_42")],
            locations=[], raw_input={"command": "npm test"}, raw_output=None,
        ))
        assert e.data["content_blocks"][0]["type"] == "terminal"
        assert e.data["terminal_id"] == "term_42"
        assert e.data["tool_input"] == "npm test"

    def test_tool_call_update_raw_output_fallback(self):
        from mobileflow_agent.providers.base import AgentEventType
        e = self.conv.convert(Obj(
            session_update="tool_call_update", tool_call_id="tc_12", title="Search",
            kind="search", status="completed",
            content=[], locations=[],
            raw_input=None, raw_output={"results": ["a.py", "b.py"]},
        ))
        assert e.type == AgentEventType.TOOL_CALL_UPDATE
        assert len(e.data["content_blocks"]) == 1
        assert e.data["content_blocks"][0]["type"] == "raw_output"

    def test_tool_call_with_image_content(self):
        e = self.conv.convert(Obj(
            session_update="tool_call", tool_call_id="tc_13", title="Screenshot",
            kind="other", status="completed",
            content=[Obj(type="content", content=Obj(type="image", mime_type="image/png", data="iVBOR..."))],
            locations=[], raw_input=None, raw_output=None,
        ))
        assert e.data["content_blocks"][0]["type"] == "image"
        assert e.data["content_blocks"][0]["mime_type"] == "image/png"

    def test_command_as_list(self):
        e = self.conv.convert(Obj(
            session_update="tool_call", tool_call_id="tc_14", title="Run",
            kind="execute", status="in_progress",
            content=[], locations=[],
            raw_input={"command": ["git", "status", "--short"]}, raw_output=None,
        ))
        assert e.data["tool_input"] == "git status --short"

    def test_plan_multiple_entries(self):
        e = self.conv.convert(Obj(
            session_update="plan",
            entries=[
                Obj(content="Read files", priority="high", status="completed"),
                Obj(content="Write code", priority="medium", status="in_progress"),
                Obj(content="Run tests", priority="low", status="pending"),
            ],
        ))
        assert len(e.data["entries"]) == 3
        assert e.data["entries"][1]["status"] == "in_progress"

    def test_session_info_with_title(self):
        e = self.conv.convert(Obj(
            session_update="session_info_update",
            title="Implement auth flow",
            updated_at="2025-10-29T14:22:15Z",
            context_usage_percentage=0.42,
        ))
        assert e.data["title"] == "Implement auth flow"
        assert e.data["updated_at"] == "2025-10-29T14:22:15Z"
        assert e.data["context_usage"] == 0.42


# ── Helper functions ──


class TestConverterHelpers:
    def test_safe_str_none(self):
        from mobileflow_agent.utils.strings import safe_str
        assert safe_str(None) == ""

    def test_safe_str_int(self):
        from mobileflow_agent.utils.strings import safe_str
        assert safe_str(42) == "42"

    def test_safe_str_str(self):
        from mobileflow_agent.utils.strings import safe_str
        assert safe_str("hello") == "hello"

    def test_serialize_dict_empty(self):
        from mobileflow_agent.providers.acp_converter import _serialize_dict
        assert _serialize_dict({}) == ""

    def test_serialize_dict_none(self):
        from mobileflow_agent.providers.acp_converter import _serialize_dict
        assert _serialize_dict(None) == ""

    def test_serialize_dict_values(self):
        from mobileflow_agent.providers.acp_converter import _serialize_dict
        s = _serialize_dict({"path": "/a.py", "line": 10})
        assert "/a.py" in s

    def test_extract_tool_input_cmd_string(self):
        from mobileflow_agent.providers.acp_converter import _extract_tool_input
        assert _extract_tool_input({"command": "ls -la"}, [], []) == "ls -la"

    def test_extract_tool_input_cmd_list(self):
        from mobileflow_agent.providers.acp_converter import _extract_tool_input
        assert _extract_tool_input({"command": ["git", "log"]}, [], []) == "git log"

    def test_extract_tool_input_path(self):
        from mobileflow_agent.providers.acp_converter import _extract_tool_input
        assert _extract_tool_input({"path": "/src/main.py"}, [], []) == "/src/main.py"

    def test_extract_tool_input_query(self):
        from mobileflow_agent.providers.acp_converter import _extract_tool_input
        assert _extract_tool_input({"query": "search term"}, [], []) == "search term"

    def test_extract_tool_input_locations_fallback(self):
        from mobileflow_agent.providers.acp_converter import _extract_tool_input
        assert _extract_tool_input(None, [{"path": "/b.py"}], []) == "/b.py"

    def test_extract_tool_input_empty(self):
        from mobileflow_agent.providers.acp_converter import _extract_tool_input
        assert _extract_tool_input(None, [], []) == ""
