"""
Permission approval classifier (based on IDE src/acp/approval-classifier.ts).

Classifies ACP tool calls into approval categories to determine whether
they can be auto-approved or need user confirmation on the phone.

Classification rules (matching IDE behavior):
  - readonly_scoped: read tool with path inside cwd → auto-approve
  - readonly_search: search/web_search/memory_search → auto-approve
  - exec_capable: exec/bash/shell/process/spawn → needs confirmation
  - control_plane: gateway/cron/sessions_spawn → needs confirmation
  - interactive: whatsapp_login etc. → needs confirmation
  - mutating: write/edit/delete/message etc. → needs confirmation
  - unknown: unrecognized tool name → needs confirmation
  - other: anything else → needs confirmation

Called by: ACPClientImpl.request_permission (when policy is ask_user)
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Optional


# ── 工具分类集合（参照 IDE 的常量定义）──

SAFE_SEARCH_TOOL_IDS = frozenset({
    "search", "web_search", "memory_search",
    "grep", "find", "ripgrep", "rg",
})

EXEC_CAPABLE_TOOL_IDS = frozenset({
    "exec", "spawn", "shell", "bash", "process",
    "nodes", "code_execution", "terminal",
})

CONTROL_PLANE_TOOL_IDS = frozenset({
    "gateway", "cron", "sessions_spawn", "sessions_send",
    "session_status",
})

INTERACTIVE_TOOL_IDS = frozenset({
    "whatsapp_login",
})

MUTATING_TOOL_NAMES = frozenset({
    "write", "edit", "delete", "remove", "rename",
    "move", "copy", "mkdir", "message", "send",
    "patch", "apply",
})

# Known safe core tools (read-only operations that never need approval)
KNOWN_SAFE_TOOL_IDS = frozenset({
    "read", "search", "web_search", "memory_search",
    "list", "ls", "cat", "head", "tail", "stat",
    "grep", "find", "ripgrep", "rg",
})


@dataclass
class ApprovalClassification:
    """Result of tool call approval classification.

    Attributes:
        tool_name: Resolved tool name (None if unrecognizable).
        approval_class: Classification category string.
        auto_approve: Whether this tool call can be auto-approved.
    """
    tool_name: Optional[str]
    approval_class: str
    auto_approve: bool


def resolve_tool_name(tool_call: Any) -> Optional[str]:
    """Extract and normalize the tool name from an ACP tool_call object.

    Follows the IDE's resolveToolNameForPermission pattern:
    tries _meta.toolName → title (before colon) → name → kind → rawInput.tool.

    Args:
        tool_call: ACP tool call object.

    Returns:
        Normalized lowercase tool name, or None if unresolvable.
    """
    if tool_call is None:
        return None

    # 1. Extract from title ("Running: read" → "read", "read: /path" → "read")
    title = getattr(tool_call, "title", None) or ""
    if title:
        # Strip "Running: " prefix
        if title.startswith("Running: "):
            title = title[9:]
        # Take the part before the colon
        name_part = title.split(":")[0].strip().split(" ")[0].strip()
        if name_part:
            normalized = _normalize_tool_name(name_part)
            if normalized:
                return normalized

    # 2. 从 name 属性
    name = getattr(tool_call, "name", None)
    if name:
        normalized = _normalize_tool_name(str(name))
        if normalized:
            return normalized

    # 3. 从 kind 属性（edit, execute, read 等）
    kind = str(getattr(tool_call, "kind", "") or "")
    if kind:
        normalized = _normalize_tool_name(kind)
        if normalized:
            return normalized

    # 4. 从 rawInput
    raw_input = getattr(tool_call, "raw_input", None)
    if isinstance(raw_input, dict):
        for key in ("tool", "toolName", "tool_name", "name"):
            val = raw_input.get(key)
            if val and isinstance(val, str):
                normalized = _normalize_tool_name(val)
                if normalized:
                    return normalized

    return None


def _normalize_tool_name(value: str) -> Optional[str]:
    """标准化工具名称：小写、去空格、验证格式"""
    normalized = value.strip().lower()
    if not normalized or len(normalized) > 128:
        return None
    # Handle MCP tool names (@server/tool_name → tool_name)
    if "/" in normalized:
        normalized = normalized.split("/")[-1]
    # Only allow alphanumeric and ._-
    import re
    if re.match(r'^[a-z0-9._-]+$', normalized):
        return normalized
    return None


def _resolve_path_from_tool(tool_call: Any) -> Optional[str]:
    """从 tool_call 提取文件路径"""
    raw_input = getattr(tool_call, "raw_input", None)
    if isinstance(raw_input, dict):
        for key in ("path", "file_path", "filePath"):
            val = raw_input.get(key)
            if val and isinstance(val, str) and val.strip():
                return val.strip()

    # Extract from title ("read: /path/to/file" → "/path/to/file")
    title = getattr(tool_call, "title", None) or ""
    if ":" in title:
        path_part = title.split(":", 1)[1].strip()
        if path_part:
            return path_part

    return None


def _is_path_scoped_to_cwd(path: str, cwd: str) -> bool:
    """检查路径是否在 cwd 内（参照 IDE 的 isReadToolCallScopedToCwd）"""
    if not path or not cwd:
        return False
    try:
        # Handle relative paths
        if os.path.isabs(path):
            abs_path = os.path.normpath(path)
        else:
            abs_path = os.path.normpath(os.path.join(cwd, path))
        abs_cwd = os.path.normpath(os.path.abspath(cwd))
        # Check if path is within cwd
        rel = os.path.relpath(abs_path, abs_cwd)
        return not rel.startswith("..")
    except (ValueError, OSError):
        return False


def _is_mutating_tool(tool_name: str, raw_input: Any = None) -> bool:
    """判断是否是修改性工具（参照 IDE 的 isMutatingToolCall）"""
    if tool_name in MUTATING_TOOL_NAMES:
        return True
    # Check raw_input for write-related parameters
    if isinstance(raw_input, dict):
        if "content" in raw_input and "path" in raw_input:
            return True  # write_text_file 模式
    return False


def classify_tool_approval(
    tool_call: Any,
    cwd: str = "",
) -> ApprovalClassification:
    """Classify an ACP tool call's approval level.

    Follows the IDE's classifyAcpToolApproval priority:
    1. Unrecognized tool → unknown, no auto-approve
    2. read + path in cwd → readonly_scoped, auto-approve
    3. search tools → readonly_search, auto-approve
    4. exec tools → exec_capable, no auto-approve
    5. control_plane → no auto-approve
    6. interactive → no auto-approve
    7. mutating → no auto-approve
    8. other → no auto-approve

    Args:
        tool_call: ACP tool call object.
        cwd: Current working directory for path scoping checks.

    Returns:
        ApprovalClassification with tool_name, class, and auto_approve flag.
    """
    tool_name = resolve_tool_name(tool_call)
    if not tool_name:
        return ApprovalClassification(
            tool_name=None, approval_class="unknown", auto_approve=False
        )

    is_known_safe = tool_name in KNOWN_SAFE_TOOL_IDS

    # read 且路径在 cwd 内
    if tool_name == "read" and is_known_safe:
        path = _resolve_path_from_tool(tool_call)
        scoped = _is_path_scoped_to_cwd(path or "", cwd) if path else False
        return ApprovalClassification(
            tool_name=tool_name,
            approval_class="readonly_scoped" if scoped else "other",
            auto_approve=scoped,
        )

    # search 类
    if tool_name in SAFE_SEARCH_TOOL_IDS and is_known_safe:
        return ApprovalClassification(
            tool_name=tool_name, approval_class="readonly_search", auto_approve=True
        )

    # exec 类
    if tool_name in EXEC_CAPABLE_TOOL_IDS:
        return ApprovalClassification(
            tool_name=tool_name, approval_class="exec_capable", auto_approve=False
        )

    # control_plane 类
    if tool_name in CONTROL_PLANE_TOOL_IDS:
        return ApprovalClassification(
            tool_name=tool_name, approval_class="control_plane", auto_approve=False
        )

    # interactive 类
    if tool_name in INTERACTIVE_TOOL_IDS:
        return ApprovalClassification(
            tool_name=tool_name, approval_class="interactive", auto_approve=False
        )

    # mutating 类
    raw_input = getattr(tool_call, "raw_input", None)
    if _is_mutating_tool(tool_name, raw_input):
        return ApprovalClassification(
            tool_name=tool_name, approval_class="mutating", auto_approve=False
        )

    # 其他
    return ApprovalClassification(
        tool_name=tool_name, approval_class="other", auto_approve=False
    )
