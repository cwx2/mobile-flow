"""
全覆盖回归测试套件（100+ 测试用例）

每次修改代码后跑一次，确认没有影响其他模块。
运行: python -m tests.test_regression

覆盖模块：
  1. ACP 包导入完整性
  2. ACP tool_calls 解析
  3. ACP content 解析
  4. ACP prompt_turn 解析
  5. ACP initialization 解析
  6. ACP agent_plan 解析
  7. ACP slash_commands 解析
  8. ACP session_list 解析
  9. ACP session_config 解析
  10. ACP overview 工具函数
  11. ACPEventConverter
  12. CLIManager._event_to_chunk
  13. SnapshotStore
  14. EventBus
"""

from __future__ import annotations

import asyncio
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

PASSED = 0
FAILED = 0
ERRORS: list[str] = []


def check(name: str, condition: bool, detail: str = ""):
    global PASSED, FAILED
    if condition:
        PASSED += 1
    else:
        FAILED += 1
        msg = f"  ✗ {name}" + (f" — {detail}" if detail else "")
        ERRORS.append(msg)
        print(msg)


# ══════════════════════════════════════════════════════════
# 辅助：模拟 ACP SDK 对象（用 SimpleNamespace 代替真实 SDK）
# ══════════════════════════════════════════════════════════

class Obj:
    """简单的属性容器，模拟 ACP SDK 的 pydantic 对象"""
    def __init__(self, **kwargs):
        for k, v in kwargs.items():
            setattr(self, k, v)


# ══════════════════════════════════════════════════════════
# 1. ACP 包导入完整性（17 个）
# ══════════════════════════════════════════════════════════

def test_acp_imports():
    print("── ACP 包导入 ──")
    modules = [
        "mobileflow_agent.providers.acp",
        "mobileflow_agent.providers.acp.overview",
        "mobileflow_agent.providers.acp.initialization",
        "mobileflow_agent.providers.acp.session_setup",
        "mobileflow_agent.providers.acp.session_list",
        "mobileflow_agent.providers.acp.prompt_turn",
        "mobileflow_agent.providers.acp.content",
        "mobileflow_agent.providers.acp.tool_calls",
        "mobileflow_agent.providers.acp.file_system",
        "mobileflow_agent.providers.acp.terminals",
        "mobileflow_agent.providers.acp.agent_plan",
        "mobileflow_agent.providers.acp.session_modes",
        "mobileflow_agent.providers.acp.session_config",
        "mobileflow_agent.providers.acp.slash_commands",
        "mobileflow_agent.providers.acp.extensibility",
        "mobileflow_agent.providers.acp.transports",
        "mobileflow_agent.providers.acp.schema",
    ]
    for mod in modules:
        try:
            __import__(mod)
            check(f"import {mod.split('.')[-1]}", True)
        except Exception as e:
            check(f"import {mod.split('.')[-1]}", False, str(e))


# ══════════════════════════════════════════════════════════
# 2. ACP tool_calls 解析（15 个）
# ══════════════════════════════════════════════════════════

def test_tool_calls():
    print("── tool_calls 解析 ──")
    from mobileflow_agent.providers.acp.tool_calls import parse_tool_call, _parse_content_item, _parse_location_list

    # TC01: 基本 ToolCallStart
    tc = parse_tool_call(Obj(
        session_update="tool_call", tool_call_id="tc_1", title="read",
        kind="read", status="in_progress", content=None, locations=None,
        raw_input=None, raw_output=None,
    ), is_update=False)
    check("TC01 tool_call_id", tc.tool_call_id == "tc_1")
    check("TC02 title", tc.title == "read")
    check("TC03 kind", tc.kind == "read")
    check("TC04 status", tc.status == "in_progress")
    check("TC05 is_update=False", tc.is_update is False)
    check("TC06 empty content", tc.content == [])
    check("TC07 empty locations", tc.locations == [])

    # TC08: ToolCallUpdate with completed status
    tc2 = parse_tool_call(Obj(
        session_update="tool_call_update", tool_call_id="tc_2", title="Editing main.py",
        kind="edit", status="completed", content=None,
        locations=[Obj(path="/home/user/main.py", line=42)],
        raw_input={"command": "insert", "path": "/home/user/main.py"},
        raw_output={"items": [{"Text": ""}]},
    ), is_update=True)
    check("TC08 is_update=True", tc2.is_update is True)
    check("TC09 location path", tc2.locations[0].path == "/home/user/main.py")
    check("TC10 location line", tc2.locations[0].line == 42)
    check("TC11 raw_input dict", tc2.raw_input["command"] == "insert")
    check("TC12 raw_output dict", "items" in tc2.raw_output)

    # TC13: content with diff
    diff_item = _parse_content_item(Obj(type="diff", path="/a.py", oldText="old", newText="new"))
    check("TC13 diff type", diff_item.type == "diff")
    check("TC14 diff old_text", diff_item.old_text == "old")
    check("TC15 diff new_text", diff_item.new_text == "new")

    # TC16: content with terminal
    term_item = _parse_content_item(Obj(type="terminal", terminalId="term_1"))
    check("TC16 terminal_id", term_item.terminal_id == "term_1")

    # TC17: content with text
    text_item = _parse_content_item(Obj(type="content", content=Obj(type="text", text="hello")))
    check("TC17 content text", text_item.text == "hello")

    # TC18: None content item
    check("TC18 None content", _parse_content_item(None) is None)

    # TC19: unknown content type with text fallback
    unk = _parse_content_item(Obj(type="unknown_type", text="fallback"))
    check("TC19 unknown fallback", unk is not None and unk.text == "fallback")

    # TC20: status normalization (enum string)
    tc3 = parse_tool_call(Obj(
        session_update="tool_call", tool_call_id="tc_3", title="x",
        kind=None, status="ToolCallStatus.COMPLETED", content=None,
        locations=None, raw_input=None, raw_output=None,
    ), is_update=False)
    check("TC20 status normalize", tc3.status == "completed")

    # TC21: locations with no line
    locs = _parse_location_list([Obj(path="/b.py", line=None)])
    check("TC21 location no line", locs[0].line is None)

    # TC22: empty path filtered out
    locs2 = _parse_location_list([Obj(path="", line=1), Obj(path="/c.py", line=5)])
    check("TC22 empty path filtered", len(locs2) == 1 and locs2[0].path == "/c.py")


# ══════════════════════════════════════════════════════════
# 3. ACP content 解析（10 个）
# ══════════════════════════════════════════════════════════

def test_content():
    print("── content 解析 ──")
    from mobileflow_agent.providers.acp.content import parse_content_block, ACPContentType

    # C01: text
    b = parse_content_block(Obj(type="text", text="hello"))
    check("C01 text type", b.type == "text")
    check("C02 text content", b.text == "hello")

    # C03: image
    b2 = parse_content_block(Obj(type="image", mimeType="image/png", data="abc123"))
    check("C03 image mime", b2.mime_type == "image/png")
    check("C04 image data", b2.data == "abc123")

    # C05: audio
    b3 = parse_content_block(Obj(type="audio", mimeType="audio/wav", data="wavdata"))
    check("C05 audio", b3.type == "audio" and b3.data == "wavdata")

    # C06: resource
    b4 = parse_content_block(Obj(type="resource", resource=Obj(uri="file:///a.py", text="code", mimeType="text/python")))
    check("C06 resource uri", b4.resource_uri == "file:///a.py")
    check("C07 resource text", b4.resource_text == "code")

    # C08: resource_link
    b5 = parse_content_block(Obj(type="resource_link", uri="file:///b.pdf", name="b.pdf", mimeType="application/pdf", title="Doc", description="A doc", size=1024))
    check("C08 link uri", b5.uri == "file:///b.pdf")
    check("C09 link size", b5.size == 1024)

    # C10: None
    check("C10 None", parse_content_block(None) is None)

    # C11: enum values
    check("C11 enum text", ACPContentType.TEXT == "text")
    check("C12 enum image", ACPContentType.IMAGE == "image")


# ══════════════════════════════════════════════════════════
# 4. ACP prompt_turn 解析（8 个）
# ══════════════════════════════════════════════════════════

def test_prompt_turn():
    print("── prompt_turn 解析 ──")
    from mobileflow_agent.providers.acp.prompt_turn import parse_message, parse_thought, ACPStopReason

    # PT01: agent message
    m = parse_message(Obj(content=Obj(type="text", text="Hello"), message_id="msg_1"), is_user=False)
    check("PT01 text", m.text == "Hello")
    check("PT02 message_id", m.message_id == "msg_1")
    check("PT03 not user", m.is_user is False)

    # PT04: user message
    m2 = parse_message(Obj(content=Obj(type="text", text="Hi"), message_id=None), is_user=True)
    check("PT04 is_user", m2.is_user is True)

    # PT05: empty content
    m3 = parse_message(Obj(content=None, message_id=None), is_user=False)
    check("PT05 empty", m3.text == "")

    # PT06: thought from content
    t = parse_thought(Obj(content=Obj(type="text", text="thinking...")))
    check("PT06 thought", t.text == "thinking...")

    # PT07: thought from thought attr
    t2 = parse_thought(Obj(content=None, thought="fallback thought"))
    check("PT07 thought fallback", t2.text == "fallback thought")

    # PT08: stop reasons
    check("PT08 end_turn", ACPStopReason.END_TURN == "end_turn")
    check("PT09 cancelled", ACPStopReason.CANCELLED == "cancelled")
    check("PT10 max_tokens", ACPStopReason.MAX_TOKENS == "max_tokens")


# ══════════════════════════════════════════════════════════
# 5. ACP initialization 解析（8 个）
# ══════════════════════════════════════════════════════════

def test_initialization():
    print("── initialization 解析 ──")
    from mobileflow_agent.providers.acp.initialization import parse_initialize_result

    result = parse_initialize_result(Obj(
        protocol_version=1,
        agent_info=Obj(name="kiro-agent", title="Kiro Agent", version="1.2.3"),
        agent_capabilities=Obj(
            load_session=True, list_sessions=False,
            close_session=False, fork_session=False, resume_session=False,
            prompt_capabilities=Obj(image=True, audio=False, embedded_context=True),
            mcp_capabilities=Obj(http=True, sse=False),
            session_capabilities=None,
        ),
        auth_methods=[Obj(id="api_key", name="API Key", description="Enter key")],
    ))
    check("I01 protocol_version", result.protocol_version == 1)
    check("I02 agent name", result.agent_info.name == "kiro-agent")
    check("I03 agent title", result.agent_info.title == "Kiro Agent")
    check("I04 agent version", result.agent_info.version == "1.2.3")
    check("I05 load_session", result.agent_capabilities.session.load_session is True)
    check("I06 image", result.agent_capabilities.prompt.image is True)
    check("I07 mcp http", result.agent_capabilities.mcp.http is True)
    check("I08 auth method", result.auth_methods[0].id == "api_key")

    # I09: empty/None
    r2 = parse_initialize_result(Obj(
        protocol_version=None, agent_info=None, agent_capabilities=None, auth_methods=None,
    ))
    check("I09 defaults", r2.agent_info.name == "" and r2.protocol_version == 1)


# ══════════════════════════════════════════════════════════
# 6. ACP agent_plan 解析（5 个）
# ══════════════════════════════════════════════════════════

def test_agent_plan():
    print("── agent_plan 解析 ──")
    from mobileflow_agent.providers.acp.agent_plan import parse_plan

    plan = parse_plan(Obj(entries=[
        Obj(content="Step 1", priority="high", status="completed"),
        Obj(content="Step 2", priority="medium", status="in_progress"),
        Obj(content="Step 3", priority="low", status="pending"),
    ]))
    check("P01 count", len(plan.entries) == 3)
    check("P02 first content", plan.entries[0].content == "Step 1")
    check("P03 first priority", plan.entries[0].priority == "high")
    check("P04 second status", plan.entries[1].status == "in_progress")

    # P05: empty
    plan2 = parse_plan(Obj(entries=None))
    check("P05 empty", len(plan2.entries) == 0)


# ══════════════════════════════════════════════════════════
# 7. ACP slash_commands 解析（4 个）
# ══════════════════════════════════════════════════════════

def test_slash_commands():
    print("── slash_commands 解析 ──")
    from mobileflow_agent.providers.acp.slash_commands import parse_commands

    cmds = parse_commands(Obj(commands=[
        Obj(name="web", description="Search web", input=Obj(hint="query")),
        Obj(name="test", description="Run tests", input=None),
    ]))
    check("S01 count", len(cmds) == 2)
    check("S02 name", cmds[0].name == "web")
    check("S03 input hint", cmds[0].input.hint == "query")
    check("S04 no input", cmds[1].input is None)


# ══════════════════════════════════════════════════════════
# 8. ACP session_list 解析（4 个）
# ══════════════════════════════════════════════════════════

def test_session_list():
    print("── session_list 解析 ──")
    from mobileflow_agent.providers.acp.session_list import parse_session_list_result

    r = parse_session_list_result(Obj(
        sessions=[
            Obj(session_id="s1", cwd="/home", title="Chat 1", updated_at="2025-01-01T00:00:00Z", _meta={"tags": ["a"]}),
            Obj(session_id="s2", cwd="/work", title="", updated_at="", _meta=None),
        ],
        next_cursor="abc123",
    ))
    check("SL01 count", len(r.sessions) == 2)
    check("SL02 session_id", r.sessions[0].session_id == "s1")
    check("SL03 next_cursor", r.next_cursor == "abc123")
    check("SL04 title empty", r.sessions[1].title == "")


# ══════════════════════════════════════════════════════════
# 9. ACP session_config 解析（4 个）
# ══════════════════════════════════════════════════════════

def test_session_config():
    print("── session_config 解析 ──")
    from mobileflow_agent.providers.acp.session_config import parse_config_options

    opts = parse_config_options([
        Obj(id="model", name="Model", description="Pick model", category="model",
            type="select", currentValue="gpt-4", options=[
                Obj(value="gpt-4", name="GPT-4", description="Best"),
                Obj(value="gpt-3", name="GPT-3", description="Fast"),
            ]),
    ])
    check("SC01 count", len(opts) == 1)
    check("SC02 id", opts[0].id == "model")
    check("SC03 current", opts[0].current_value == "gpt-4")
    check("SC04 options count", len(opts[0].options) == 2)


# ══════════════════════════════════════════════════════════
# 10. overview 工具函数（5 个）
# ══════════════════════════════════════════════════════════

def test_overview():
    print("── overview 工具函数 ──")
    from mobileflow_agent.providers.acp.overview import normalize_status, safe_str, safe_dict, safe_int

    check("O01 normalize completed", normalize_status("completed") == "completed")
    check("O02 normalize enum", normalize_status("ToolCallStatus.FAILED") == "failed")
    check("O03 normalize None", normalize_status(None) == "")
    check("O04 safe_str None", safe_str(None) == "")
    check("O05 safe_str val", safe_str(42) == "42")
    check("O06 safe_dict ok", safe_dict({"a": 1}) == {"a": 1})
    check("O07 safe_dict None", safe_dict(None) is None)
    check("O08 safe_dict str", safe_dict("not a dict") is None)
    check("O09 safe_int ok", safe_int("42") == 42)
    check("O10 safe_int None", safe_int(None) is None)
    check("O11 safe_int bad", safe_int("abc") is None)


# ══════════════════════════════════════════════════════════
# 11. ACPEventConverter（15 个）
# ══════════════════════════════════════════════════════════

def test_converter():
    print("── ACPEventConverter ──")
    from mobileflow_agent.providers.acp_converter import ACPEventConverter
    from mobileflow_agent.providers.base import AgentEventType

    conv = ACPEventConverter()

    # CV01: agent_message_chunk → TEXT_CHUNK
    e = conv.convert(Obj(session_update="agent_message_chunk", content=Obj(type="text", text="Hello"), message_id=None))
    check("CV01 text chunk", e is not None and e.type == AgentEventType.TEXT_CHUNK)
    check("CV02 text value", e.data["text"] == "Hello")

    # CV03: empty text → None
    e2 = conv.convert(Obj(session_update="agent_message_chunk", content=Obj(type="text", text=""), message_id=None))
    check("CV03 empty text", e2 is None)

    # CV04: user_message_chunk → None (skip)
    e3 = conv.convert(Obj(session_update="user_message_chunk", content=Obj(type="text", text="Hi"), message_id=None))
    check("CV04 user skip", e3 is None)

    # CV05: agent_thought_chunk → THOUGHT_CHUNK
    e4 = conv.convert(Obj(session_update="agent_thought_chunk", content=Obj(type="text", text="thinking"), thought=None))
    check("CV05 thought", e4 is not None and e4.type == AgentEventType.THOUGHT_CHUNK)

    # CV06: tool_call → TOOL_CALL_START
    e5 = conv.convert(Obj(
        session_update="tool_call", tool_call_id="tc_1", title="read file",
        kind="read", status="in_progress", content=None, locations=None,
        raw_input=None, raw_output=None,
    ))
    check("CV06 tool start", e5.type == AgentEventType.TOOL_CALL_START)
    check("CV07 tool name", e5.data["name"] == "read file")
    check("CV08 tool kind", e5.data["kind"] == "read")

    # CV09: tool_call_update → TOOL_CALL_UPDATE
    e6 = conv.convert(Obj(
        session_update="tool_call_update", tool_call_id="tc_1", title="read file",
        kind="read", status="completed", content=None,
        locations=[Obj(path="/a.py", line=10)],
        raw_input=None, raw_output={"items": [{"Text": "done"}]},
    ))
    check("CV09 tool update", e6.type == AgentEventType.TOOL_CALL_UPDATE)
    check("CV10 update status", e6.data["status"] == "completed")

    # CV11: tool_call with diff content → FILE_EDIT
    e7 = conv.convert(Obj(
        session_update="tool_call", tool_call_id="tc_2", title="Editing a.py",
        kind="edit", status="completed",
        content=[Obj(type="diff", path="/a.py", oldText="old code", newText="new code")],
        locations=None, raw_input=None, raw_output=None,
    ))
    check("CV11 file edit", e7.type == AgentEventType.FILE_EDIT)
    check("CV12 edit old", e7.data["full_old"] == "old code")
    check("CV13 edit new", e7.data["full_new"] == "new code")

    # CV14: plan → PLAN_UPDATE
    e8 = conv.convert(Obj(
        session_update="plan",
        entries=[Obj(content="Step 1", priority="high", status="pending", title=None)],
    ))
    check("CV14 plan", e8.type == AgentEventType.PLAN_UPDATE)
    check("CV15 plan entry", e8.data["entries"][0]["title"] == "Step 1")

    # CV16: available_commands_update → COMMANDS_AVAILABLE
    e9 = conv.convert(Obj(
        session_update="available_commands_update",
        commands=[Obj(name="test", description="Run tests", input=None)],
    ))
    check("CV16 commands", e9.type == AgentEventType.COMMANDS_AVAILABLE)

    # CV17: current_mode_update → MODE_CHANGE
    e10 = conv.convert(Obj(session_update="current_mode_update", mode_id="code"))
    check("CV17 mode", e10.type == AgentEventType.MODE_CHANGE and e10.data["mode_id"] == "code")

    # CV18: session_info_update → SESSION_INFO
    e11 = conv.convert(Obj(session_update="session_info_update", context_usage_percentage=0.75))
    check("CV18 session info", e11.type == AgentEventType.SESSION_INFO)

    # CV19: unknown type → None
    e12 = conv.convert(Obj(session_update="totally_unknown_type"))
    check("CV19 unknown", e12 is None)


# ══════════════════════════════════════════════════════════
# 12. CLIManager._event_to_chunk（10 个）
# ══════════════════════════════════════════════════════════

def test_event_to_chunk():
    print("── _event_to_chunk ──")
    from mobileflow_agent.services.cli_manager import CLIManager
    from mobileflow_agent.providers.base import AgentEvent, AgentEventType

    f = CLIManager._event_to_chunk

    # EC01: TEXT_CHUNK
    c = f(AgentEvent(type=AgentEventType.TEXT_CHUNK, data={"text": "hello"}))
    check("EC01 text", c.type.value == "text" and c.content == "hello")

    # EC02: THOUGHT_CHUNK
    c2 = f(AgentEvent(type=AgentEventType.THOUGHT_CHUNK, data={"text": "hmm"}))
    check("EC02 thought", c2.type.value == "thinking")

    # EC03: FILE_EDIT → DIFF
    c3 = f(AgentEvent(type=AgentEventType.FILE_EDIT, data={"path": "a.py", "full_old": "old", "full_new": "new"}))
    check("EC03 diff type", c3.type.value == "diff")
    check("EC04 diff path", c3.file_path == "a.py")
    check("EC05 diff old", c3.old_content == "old")
    check("EC06 diff new", c3.new_content == "new")

    # EC07: TOOL_CALL_START
    c4 = f(AgentEvent(type=AgentEventType.TOOL_CALL_START, data={
        "name": "grep", "kind": "search", "id": "t1", "status": "running",
    }))
    check("EC07 tool use", c4.type.value == "tool_use" and c4.content == "grep")

    # EC08: TOOL_CALL_UPDATE completed
    c5 = f(AgentEvent(type=AgentEventType.TOOL_CALL_UPDATE, data={
        "id": "t1", "name": "grep", "status": "completed",
    }))
    check("EC08 tool update", c5.type.value == "tool_update" and c5.status == "completed")

    # EC09: ERROR
    c6 = f(AgentEvent(type=AgentEventType.ERROR, data={"error": "boom"}))
    check("EC09 error", c6.type.value == "error" and c6.content == "boom")

    # EC10: TURN_END → None
    c7 = f(AgentEvent(type=AgentEventType.TURN_END, data={}))
    check("EC10 turn end", c7 is None)

    # EC11: PLAN_UPDATE
    c8 = f(AgentEvent(type=AgentEventType.PLAN_UPDATE, data={"entries": [{"title": "Step 1", "status": "pending"}]}))
    check("EC11 plan", c8 is not None and c8.type.value == "text")


# ══════════════════════════════════════════════════════════
# 13. SnapshotStore（8 个）
# ══════════════════════════════════════════════════════════

def test_snapshot_store():
    print("── SnapshotStore ──")
    from mobileflow_agent.services.snapshot_store import SnapshotStore

    s = SnapshotStore()

    # SS01: capture and get initial content
    s.capture_before_edit("a.py", "original content")
    check("SS01 initial", s.get_initial_content("a.py") == "original content")

    # SS02: second capture doesn't change initial
    s.capture_before_edit("a.py", "modified content")
    check("SS02 still initial", s.get_initial_content("a.py") == "original content")

    # SS03: edit baseline is latest
    check("SS03 edit baseline", s.get_edit_baseline("a.py") == "modified content")

    # SS04: version count
    check("SS04 versions", s.get_version_count("a.py") == 2)

    # SS05: get specific version
    check("SS05 version 0", s.get_version("a.py", 0) == "original content")
    check("SS06 version 1", s.get_version("a.py", 1) == "modified content")

    # SS07: nonexistent file
    check("SS07 nonexistent", s.get_initial_content("nope.py") is None)

    # SS08: list modified files
    s.capture_before_edit("b.py", "b content")
    files = s.list_modified_files()
    check("SS08 list files", "a.py" in files and "b.py" in files)

    # SS09: checkpoint
    cp_id = s.create_checkpoint("test checkpoint")
    cp = s.get_checkpoint(cp_id)
    check("SS09 checkpoint", cp is not None and "a.py" in cp.file_versions)

    # SS10: stats
    stats = s.stats
    check("SS10 stats files", stats["files"] == 2)

    # SS11: clear
    s.clear()
    check("SS11 clear", s.get_initial_content("a.py") is None and s.stats["files"] == 0)

    # SS12: max versions per file
    s2 = SnapshotStore()
    for i in range(25):
        s2.capture_before_edit("hot.py", f"v{i}" * 100)
    check("SS12 max versions", s2.get_version_count("hot.py") <= s2.MAX_VERSIONS_PER_FILE)


# ══════════════════════════════════════════════════════════
# 14. EventBus（5 个）
# ══════════════════════════════════════════════════════════

def test_event_bus():
    print("── EventBus ──")

    async def _run():
        from mobileflow_agent.core.event_bus import EventBus

        bus = EventBus()
        received = []

        # EB01: on + emit
        async def handler(data):
            received.append(data)
        bus.on("test", handler)
        await bus.emit("test", {"msg": "hello"})
        check("EB01 emit received", len(received) == 1 and received[0]["msg"] == "hello")

        # EB02: multiple handlers
        received2 = []
        async def handler2(data):
            received2.append(data)
        bus.on("test", handler2)
        await bus.emit("test", {"msg": "world"})
        check("EB02 multi handler", len(received) == 2 and len(received2) == 1)

        # EB03: different event
        await bus.emit("other", {"x": 1})
        check("EB03 different event", len(received) == 2)  # "test" handlers not called

        # EB04: emit_and_wait
        async def reply_handler(data):
            return {"answer": 42}
        bus2 = EventBus()
        bus2.on("ask", reply_handler)
        result = await bus2.emit_and_wait("ask", {"q": "?"}, timeout=5)
        check("EB04 emit_and_wait", result is not None and result.get("answer") == 42)

        # EB05: emit no handlers
        bus3 = EventBus()
        await bus3.emit("nobody_listens", {})
        check("EB05 no handlers", True)  # should not crash

    asyncio.run(_run())


# ══════════════════════════════════════════════════════════
# 15. ACP schema 常量（3 个）
# ══════════════════════════════════════════════════════════

def test_schema():
    print("── schema 常量 ──")
    from mobileflow_agent.providers.acp.schema import ACPMethod, ACPJsonRpcErrorCode

    check("SCH01 initialize", ACPMethod.INITIALIZE == "initialize")
    check("SCH02 session_prompt", ACPMethod.SESSION_PROMPT == "session/prompt")
    check("SCH03 error code", ACPJsonRpcErrorCode.METHOD_NOT_FOUND == -32601)


# ══════════════════════════════════════════════════════════
# 16. ACP extensibility（3 个）
# ══════════════════════════════════════════════════════════

def test_extensibility():
    print("── extensibility ──")
    from mobileflow_agent.providers.acp.extensibility import extract_meta, ACPMeta

    # EX01: extract _meta
    m = extract_meta(Obj(_meta={"traceparent": "00-abc", "custom": True}))
    check("EX01 meta", m is not None and m.traceparent == "00-abc")

    # EX02: no _meta
    check("EX02 no meta", extract_meta(Obj(x=1)) is None)

    # EX03: ACPMeta data access
    m2 = ACPMeta(data={"baggage": "ctx=123"})
    check("EX03 baggage", m2.baggage == "ctx=123")


# ══════════════════════════════════════════════════════════
# 17. ACP session_modes（3 个）
# ══════════════════════════════════════════════════════════

def test_session_modes():
    print("── session_modes ──")
    from mobileflow_agent.providers.acp.session_modes import parse_mode_state

    ms = parse_mode_state(Obj(
        current_mode_id="ask",
        available_modes=[
            Obj(id="ask", name="Ask", description="Ask before changes"),
            Obj(id="code", name="Code", description="Full access"),
        ],
    ))
    check("SM01 current", ms.current_mode_id == "ask")
    check("SM02 modes count", len(ms.available_modes) == 2)
    check("SM03 mode name", ms.available_modes[1].name == "Code")


# ══════════════════════════════════════════════════════════
# 18. ACP session_setup（3 个）
# ══════════════════════════════════════════════════════════

def test_session_setup():
    print("── session_setup ──")
    from mobileflow_agent.providers.acp.session_setup import parse_new_session_result

    r = parse_new_session_result(Obj(
        session_id="sess_123",
        modes=Obj(available_modes=[Obj(id="ask", name="Ask"), Obj(id="code", name="Code")]),
    ))
    check("SS_01 session_id", r.session_id == "sess_123")
    check("SS_02 modes", len(r.available_modes) == 2)

    # empty
    r2 = parse_new_session_result(Obj(session_id="", modes=None))
    check("SS_03 empty", r2.session_id == "" and r2.available_modes == [])


# ══════════════════════════════════════════════════════════
# 19. ACP terminals 数据类（2 个）
# ══════════════════════════════════════════════════════════

def test_terminals():
    print("── terminals ──")
    from mobileflow_agent.providers.acp.terminals import ACPTerminal, ACPTerminalOutputResult

    t = ACPTerminal(command="npm", args=["test"], cwd="/home/user")
    check("TM01 command", t.command == "npm" and t.args == ["test"])

    o = ACPTerminalOutputResult(output="PASS", truncated=False, exit_status=None)
    check("TM02 output", o.output == "PASS" and o.truncated is False)


# ══════════════════════════════════════════════════════════
# 20. ACP file_system 数据类（2 个）
# ══════════════════════════════════════════════════════════

def test_file_system():
    print("── file_system ──")
    from mobileflow_agent.providers.acp.file_system import ACPFileRead, ACPFileWrite

    r = ACPFileRead(path="/a.py", line=10, limit=50)
    check("FS01 read", r.path == "/a.py" and r.line == 10)

    w = ACPFileWrite(path="/b.py", content="hello")
    check("FS02 write", w.path == "/b.py" and w.content == "hello")


# ══════════════════════════════════════════════════════════
# 权限审批分类器测试（参照 IDE approval-classifier.test.ts）
# ══════════════════════════════════════════════════════════

def test_approval_classifier():
    print("── approval_classifier ──")
    from mobileflow_agent.providers.approval_classifier import (
        classify_tool_approval,
        resolve_tool_name,
        ApprovalClassification,
        _is_path_scoped_to_cwd,
        _normalize_tool_name,
    )

    # ── resolve_tool_name ──

    @dataclass
    class FakeToolCall:
        title: str = ""
        name: str = ""
        kind: str = ""
        raw_input: dict | None = None

    check("AC01 resolve from title",
          resolve_tool_name(FakeToolCall(title="read: /path/to/file")) == "read")
    check("AC02 resolve from Running: prefix",
          resolve_tool_name(FakeToolCall(title="Running: exec")) == "exec")
    check("AC03 resolve from name",
          resolve_tool_name(FakeToolCall(name="search")) == "search")
    check("AC04 resolve from kind",
          resolve_tool_name(FakeToolCall(kind="edit")) == "edit")
    check("AC05 resolve from raw_input",
          resolve_tool_name(FakeToolCall(raw_input={"tool": "write"})) == "write")
    check("AC06 resolve None for empty",
          resolve_tool_name(FakeToolCall()) is None)
    check("AC07 resolve None for None",
          resolve_tool_name(None) is None)
    check("AC08 MCP tool name @server/tool",
          resolve_tool_name(FakeToolCall(title="Running: @youtrack-wsl/peek_issue")) == "peek_issue")

    # ── _normalize_tool_name ──

    check("AC09 normalize lowercase", _normalize_tool_name("READ") == "read")
    check("AC10 normalize strip", _normalize_tool_name("  search  ") == "search")
    check("AC11 normalize empty", _normalize_tool_name("") is None)
    check("AC12 normalize too long", _normalize_tool_name("a" * 200) is None)
    check("AC13 normalize MCP path", _normalize_tool_name("@server/tool") == "tool")

    # ── _is_path_scoped_to_cwd ──

    check("AC14 path in cwd (relative)", _is_path_scoped_to_cwd("src/main.py", "/project"))
    check("AC15 path in cwd (absolute)", _is_path_scoped_to_cwd("/project/src/main.py", "/project"))
    check("AC16 path outside cwd", not _is_path_scoped_to_cwd("/etc/passwd", "/project"))
    check("AC17 path traversal", not _is_path_scoped_to_cwd("../../etc/passwd", "/project"))
    check("AC18 empty path", not _is_path_scoped_to_cwd("", "/project"))

    # ── classify_tool_approval: readonly_scoped ──

    result = classify_tool_approval(
        FakeToolCall(title="read: src/main.py", raw_input={"path": "src/main.py"}),
        cwd="/project"
    )
    check("AC19 read scoped auto-approve",
          result.approval_class == "readonly_scoped" and result.auto_approve)

    result = classify_tool_approval(
        FakeToolCall(title="read: /etc/passwd", raw_input={"path": "/etc/passwd"}),
        cwd="/project"
    )
    check("AC20 read outside cwd not auto-approve",
          result.approval_class == "other" and not result.auto_approve)

    # ── classify_tool_approval: readonly_search ──

    result = classify_tool_approval(FakeToolCall(name="search"), cwd="/project")
    check("AC21 search auto-approve",
          result.approval_class == "readonly_search" and result.auto_approve)

    result = classify_tool_approval(FakeToolCall(name="web_search"), cwd="/project")
    check("AC22 web_search auto-approve",
          result.approval_class == "readonly_search" and result.auto_approve)

    result = classify_tool_approval(FakeToolCall(name="grep"), cwd="/project")
    check("AC23 grep auto-approve",
          result.approval_class == "readonly_search" and result.auto_approve)

    # ── classify_tool_approval: exec_capable ──

    result = classify_tool_approval(FakeToolCall(name="exec"), cwd="/project")
    check("AC24 exec not auto-approve",
          result.approval_class == "exec_capable" and not result.auto_approve)

    result = classify_tool_approval(FakeToolCall(name="bash"), cwd="/project")
    check("AC25 bash not auto-approve",
          result.approval_class == "exec_capable" and not result.auto_approve)

    result = classify_tool_approval(FakeToolCall(name="shell"), cwd="/project")
    check("AC26 shell not auto-approve",
          result.approval_class == "exec_capable" and not result.auto_approve)

    # ── classify_tool_approval: mutating ──

    result = classify_tool_approval(FakeToolCall(name="write"), cwd="/project")
    check("AC27 write not auto-approve",
          result.approval_class == "mutating" and not result.auto_approve)

    result = classify_tool_approval(FakeToolCall(name="edit"), cwd="/project")
    check("AC28 edit not auto-approve",
          result.approval_class == "mutating" and not result.auto_approve)

    result = classify_tool_approval(FakeToolCall(name="delete"), cwd="/project")
    check("AC29 delete not auto-approve",
          result.approval_class == "mutating" and not result.auto_approve)

    # ── classify_tool_approval: control_plane ──

    result = classify_tool_approval(FakeToolCall(name="gateway"), cwd="/project")
    check("AC30 gateway not auto-approve",
          result.approval_class == "control_plane" and not result.auto_approve)

    # ── classify_tool_approval: unknown ──

    result = classify_tool_approval(FakeToolCall(), cwd="/project")
    check("AC31 unknown not auto-approve",
          result.approval_class == "unknown" and not result.auto_approve)

    # ── classify_tool_approval: MCP tool ──

    result = classify_tool_approval(
        FakeToolCall(title="Running: @youtrack-wsl/peek_issue"),
        cwd="/project"
    )
    check("AC32 MCP tool other not auto-approve",
          result.tool_name == "peek_issue" and not result.auto_approve)

    # ── classify_tool_approval: list/cat/ls (safe) ──

    result = classify_tool_approval(FakeToolCall(name="list"), cwd="/project")
    check("AC33 list is other (not in search set)",
          result.approval_class == "other" and not result.auto_approve)

    result = classify_tool_approval(FakeToolCall(name="find"), cwd="/project")
    check("AC34 find auto-approve (in search set)",
          result.approval_class == "readonly_search" and result.auto_approve)


# ══════════════════════════════════════════════════════════
# 终端 PTY 检测测试
# ══════════════════════════════════════════════════════════

def test_terminal_pty_detect():
    print("── terminal_pty_detect ──")
    from mobileflow_agent.services.terminal_service import (
        _detect_pty_method, TerminalSession, TerminalManager,
    )
    import sys

    if sys.platform == "win32":
        check("PTY01 WSL 检测", _detect_pty_method("wsl") == "wsl_script")
        method = _detect_pty_method("native")
        check("PTY02 Win native", method in ("winpty", "wsl_script", "pipe"))
    else:
        check("PTY01 Unix native", _detect_pty_method("native") == "pty_fork")
        check("PTY02 WSL 检测", _detect_pty_method("wsl") == "wsl_script")

    session = TerminalSession("test")
    check("PTY03 session init", session.session_id == "test" and not session.is_running)
    mgr = TerminalManager()
    check("PTY04 manager empty", mgr.get_session("x") is None)
    check("PTY05 win_to_wsl", TerminalSession._win_to_wsl("C:\\Users\\t") == "/mnt/c/Users/t")
    check("PTY06 win_to_wsl D", TerminalSession._win_to_wsl("D:\\p") == "/mnt/d/p")
    check("PTY07 wsl passthrough", TerminalSession._win_to_wsl("/mnt/c/t") == "/mnt/c/t")


# ══════════════════════════════════════════════════════════
# Git Service 模型测试
# ══════════════════════════════════════════════════════════

def test_git_service_models():
    print("── git_service_models ──")
    from mobileflow_agent.services.git_service import (
        GitFileStatus, GitBranch, GitLogEntry, GitStatusResult, GitService,
    )

    fs = GitFileStatus(path="a.py", status="M", staged=True)
    check("GIT01 FileStatus", fs.to_dict()["status"] == "M" and fs.to_dict()["staged"])
    fs2 = GitFileStatus(path="b.py", status="R", staged=True, old_path="old.py")
    check("GIT02 rename", fs2.to_dict()["old_path"] == "old.py")
    br = GitBranch(name="main", current=True)
    check("GIT03 Branch", br.to_dict()["current"] and not br.to_dict()["remote"])
    br2 = GitBranch(name="origin/main", current=False, remote=True)
    check("GIT04 remote", br2.to_dict()["remote"])
    le = GitLogEntry(hash="abc", short_hash="a", message="fix", author="dev", date="2026")
    check("GIT05 LogEntry", le.to_dict()["message"] == "fix")
    sr = GitStatusResult(branch="main")
    sr.staged.append(GitFileStatus(path="x", status="A", staged=True))
    sr.unstaged.append(GitFileStatus(path="y", status="M", staged=False))
    sr.untracked.append(GitFileStatus(path="z", status="?", staged=False))
    d = sr.to_dict()
    check("GIT06 StatusResult", d["branch"] == "main" and len(d["staged"]) == 1)
    check("GIT07 error", GitStatusResult(error="err").to_dict()["error"] == "err")
    gs = GitService(cwd="/tmp")
    gs._update_cwd("/p")
    check("GIT08 cwd update", gs._cwd == "/p")


# ══════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════

def main():
    print("\n🧪 MobileFlow Agent 回归测试套件\n")
    start = time.perf_counter()

    test_acp_imports()
    test_tool_calls()
    test_content()
    test_prompt_turn()
    test_initialization()
    test_agent_plan()
    test_slash_commands()
    test_session_list()
    test_session_config()
    test_overview()
    test_converter()
    test_event_to_chunk()
    test_snapshot_store()
    test_event_bus()
    test_schema()
    test_extensibility()
    test_session_modes()
    test_session_setup()
    test_terminals()
    test_file_system()
    test_approval_classifier()
    test_terminal_pty_detect()
    test_git_service_models()

    elapsed = (time.perf_counter() - start) * 1000
    total = PASSED + FAILED

    print(f"\n{'='*60}")
    if FAILED == 0:
        print(f"🎉 全部通过: {PASSED}/{total} ({elapsed:.0f}ms)")
    else:
        print(f"❌ 失败: {FAILED}/{total} ({elapsed:.0f}ms)")
        for err in ERRORS:
            print(err)
    print(f"{'='*60}\n")

    return 0 if FAILED == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
