"""
Approval classifier tests (mirrors IDE approval-classifier.test.ts).

Covers: resolve_tool_name, _normalize_tool_name, _is_path_scoped_to_cwd,
classify_tool_approval for all approval classes.
"""

from __future__ import annotations

from dataclasses import dataclass

import pytest

from mobileflow_agent.providers.approval_classifier import (
    classify_tool_approval,
    resolve_tool_name,
    ApprovalClassification,
    _is_path_scoped_to_cwd,
    _normalize_tool_name,
)


@dataclass
class FakeToolCall:
    title: str = ""
    name: str = ""
    kind: str = ""
    raw_input: dict | None = None


# ── resolve_tool_name ──


class TestResolveToolName:
    def test_from_title(self):
        assert resolve_tool_name(FakeToolCall(title="read: /path/to/file")) == "read"

    def test_from_running_prefix(self):
        assert resolve_tool_name(FakeToolCall(title="Running: exec")) == "exec"

    def test_from_name(self):
        assert resolve_tool_name(FakeToolCall(name="search")) == "search"

    def test_from_kind(self):
        assert resolve_tool_name(FakeToolCall(kind="edit")) == "edit"

    def test_from_raw_input(self):
        assert resolve_tool_name(FakeToolCall(raw_input={"tool": "write"})) == "write"

    def test_empty_returns_none(self):
        assert resolve_tool_name(FakeToolCall()) is None

    def test_none_returns_none(self):
        assert resolve_tool_name(None) is None

    def test_mcp_tool_name(self):
        assert resolve_tool_name(FakeToolCall(title="Running: @youtrack-wsl/peek_issue")) == "peek_issue"


# ── _normalize_tool_name ──


class TestNormalizeToolName:
    def test_lowercase(self):
        assert _normalize_tool_name("READ") == "read"

    def test_strip(self):
        assert _normalize_tool_name("  search  ") == "search"

    def test_empty(self):
        assert _normalize_tool_name("") is None

    def test_too_long(self):
        assert _normalize_tool_name("a" * 200) is None

    def test_mcp_path(self):
        assert _normalize_tool_name("@server/tool") == "tool"


# ── _is_path_scoped_to_cwd ──


class TestPathScoped:
    def test_relative_in_cwd(self):
        assert _is_path_scoped_to_cwd("src/main.py", "/project")

    def test_absolute_in_cwd(self):
        assert _is_path_scoped_to_cwd("/project/src/main.py", "/project")

    def test_outside_cwd(self):
        assert not _is_path_scoped_to_cwd("/etc/passwd", "/project")

    def test_traversal(self):
        assert not _is_path_scoped_to_cwd("../../etc/passwd", "/project")

    def test_empty_path(self):
        assert not _is_path_scoped_to_cwd("", "/project")


# ── classify_tool_approval ──


class TestClassifyToolApproval:
    def test_read_scoped_auto_approve(self):
        r = classify_tool_approval(
            FakeToolCall(title="read: src/main.py", raw_input={"path": "src/main.py"}),
            cwd="/project",
        )
        assert r.approval_class == "readonly_scoped" and r.auto_approve

    def test_read_outside_cwd(self):
        r = classify_tool_approval(
            FakeToolCall(title="read: /etc/passwd", raw_input={"path": "/etc/passwd"}),
            cwd="/project",
        )
        assert r.approval_class == "other" and not r.auto_approve

    def test_search_auto_approve(self):
        r = classify_tool_approval(FakeToolCall(name="search"), cwd="/project")
        assert r.approval_class == "readonly_search" and r.auto_approve

    def test_web_search_auto_approve(self):
        r = classify_tool_approval(FakeToolCall(name="web_search"), cwd="/project")
        assert r.approval_class == "readonly_search" and r.auto_approve

    def test_grep_auto_approve(self):
        r = classify_tool_approval(FakeToolCall(name="grep"), cwd="/project")
        assert r.approval_class == "readonly_search" and r.auto_approve

    def test_exec_not_auto_approve(self):
        r = classify_tool_approval(FakeToolCall(name="exec"), cwd="/project")
        assert r.approval_class == "exec_capable" and not r.auto_approve

    def test_bash_not_auto_approve(self):
        r = classify_tool_approval(FakeToolCall(name="bash"), cwd="/project")
        assert r.approval_class == "exec_capable" and not r.auto_approve

    def test_shell_not_auto_approve(self):
        r = classify_tool_approval(FakeToolCall(name="shell"), cwd="/project")
        assert r.approval_class == "exec_capable" and not r.auto_approve

    def test_write_mutating(self):
        r = classify_tool_approval(FakeToolCall(name="write"), cwd="/project")
        assert r.approval_class == "mutating" and not r.auto_approve

    def test_edit_mutating(self):
        r = classify_tool_approval(FakeToolCall(name="edit"), cwd="/project")
        assert r.approval_class == "mutating" and not r.auto_approve

    def test_delete_mutating(self):
        r = classify_tool_approval(FakeToolCall(name="delete"), cwd="/project")
        assert r.approval_class == "mutating" and not r.auto_approve

    def test_gateway_control_plane(self):
        r = classify_tool_approval(FakeToolCall(name="gateway"), cwd="/project")
        assert r.approval_class == "control_plane" and not r.auto_approve

    def test_unknown(self):
        r = classify_tool_approval(FakeToolCall(), cwd="/project")
        assert r.approval_class == "unknown" and not r.auto_approve

    def test_mcp_tool(self):
        r = classify_tool_approval(
            FakeToolCall(title="Running: @youtrack-wsl/peek_issue"), cwd="/project",
        )
        assert r.tool_name == "peek_issue" and not r.auto_approve

    def test_list_is_other(self):
        r = classify_tool_approval(FakeToolCall(name="list"), cwd="/project")
        assert r.approval_class == "other" and not r.auto_approve

    def test_find_auto_approve(self):
        r = classify_tool_approval(FakeToolCall(name="find"), cwd="/project")
        assert r.approval_class == "readonly_search" and r.auto_approve
