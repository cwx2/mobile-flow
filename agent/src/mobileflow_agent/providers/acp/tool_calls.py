"""
ACP Tool Calls — 工具调用报告

对应官网: https://agentclientprotocol.com/protocol/tool-calls

事件类型：
  - tool_call (ToolCallStart): 工具调用开始
  - tool_call_update (ToolCallProgress): 工具调用进度/结果

字段（tool_call）：
  - toolCallId (required): 唯一 ID
  - title (required): 人类可读标题
  - kind: 工具类别 (read/edit/delete/move/search/execute/think/fetch/other)
  - status: 执行状态 (pending/in_progress/completed/failed)
  - content: ToolCallContent[] — 内容块数组
  - locations: ToolCallLocation[] — 涉及的文件位置
  - rawInput: 原始输入参数
  - rawOutput: 原始输出结果

ToolCallContent 三种类型：
  - diff: {type:"diff", path, oldText, newText}
  - content: {type:"content", content:{type:"text", text:...}}
  - terminal: {type:"terminal", terminalId:...}

Permission:
  - session/request_permission: Agent 请求用户授权
  - PermissionOption: allow_once / allow_always / reject_once / reject_always
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional

from loguru import logger

from .overview import normalize_status, safe_str, safe_dict, safe_int


class ACPToolKind(str, Enum):
    """ACP ToolKind — 工具类别"""
    READ = "read"
    EDIT = "edit"
    DELETE = "delete"
    MOVE = "move"
    SEARCH = "search"
    EXECUTE = "execute"
    THINK = "think"
    FETCH = "fetch"
    OTHER = "other"


class ACPToolStatus(str, Enum):
    """ACP ToolCallStatus — 工具执行状态"""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"


class ACPPermissionKind(str, Enum):
    """ACP PermissionOptionKind — 权限选项类型"""
    ALLOW_ONCE = "allow_once"
    ALLOW_ALWAYS = "allow_always"
    REJECT_ONCE = "reject_once"
    REJECT_ALWAYS = "reject_always"


# ── 数据类 ──


@dataclass
class ACPLocation:
    """
    ACP ToolCallLocation — 工具调用涉及的文件位置
    规范字段: path (required, absolute), line (optional, 1-based)
    """
    path: str = ""
    line: Optional[int] = None


@dataclass
class ACPToolContent:
    """
    ACP ToolCallContent — 工具调用产生的内容块
    规范定义三种类型：
      - diff: {type:"diff", path, oldText, newText}
      - content: {type:"content", content:{type:"text", text:...}}
      - terminal: {type:"terminal", terminalId:...}
    """
    type: str = ""  # "diff" / "content" / "terminal"

    # diff 类型（ACP: path, oldText, newText）
    path: str = ""
    old_text: str = ""   # ACP: oldText
    new_text: str = ""   # ACP: newText

    # content 类型
    text: str = ""

    # terminal 类型（ACP: terminalId）
    terminal_id: str = ""  # ACP: terminalId


@dataclass
class ACPToolCall:
    """
    ACP ToolCall / ToolCallUpdate — 完整的工具调用数据
    """
    tool_call_id: str = ""                         # ACP: toolCallId (required)
    title: str = ""                                # ACP: title (required)
    kind: str = ""                                 # ACP: kind (ToolKind)
    status: str = ""                               # ACP: status (ToolCallStatus)
    content: list[ACPToolContent] = field(default_factory=list)   # ACP: content[]
    locations: list[ACPLocation] = field(default_factory=list)    # ACP: locations[]
    raw_input: Optional[dict] = None               # ACP: rawInput
    raw_output: Optional[dict] = None              # ACP: rawOutput
    is_update: bool = False                        # True = tool_call_update


@dataclass
class ACPPermissionOption:
    """ACP PermissionOption — 权限选项"""
    option_id: str = ""   # ACP: optionId
    name: str = ""        # 人类可读标签
    kind: str = ""        # ACP: kind (PermissionOptionKind)


# ── 解析函数 ──


def parse_tool_call(update: Any, is_update: bool = False) -> ACPToolCall:
    """解析 tool_call / tool_call_update"""
    return ACPToolCall(
        tool_call_id=safe_str(getattr(update, "tool_call_id", "")),
        title=safe_str(getattr(update, "title", "")),
        kind=safe_str(getattr(update, "kind", "")),
        status=normalize_status(getattr(update, "status", "")),
        content=_parse_content_list(getattr(update, "content", None)),
        locations=_parse_location_list(getattr(update, "locations", None)),
        raw_input=safe_dict(getattr(update, "raw_input", None)),
        raw_output=safe_dict(getattr(update, "raw_output", None)),
        is_update=is_update,
    )


def parse_permission_options(options: Any) -> list[ACPPermissionOption]:
    """解析权限选项列表"""
    if not options or not isinstance(options, list):
        return []
    return [
        ACPPermissionOption(
            option_id=safe_str(getattr(opt, "option_id", "")),
            name=safe_str(getattr(opt, "name", "")),
            kind=safe_str(getattr(opt, "kind", "")),
        )
        for opt in options
    ]


def _parse_content_list(raw: Any) -> list[ACPToolContent]:
    """解析 ToolCallContent[] 数组"""
    if raw is None:
        return []
    items = raw if isinstance(raw, list) else [raw]
    result = []
    for item in items:
        parsed = _parse_content_item(item)
        if parsed:
            result.append(parsed)
    return result


def _parse_content_item(item: Any) -> Optional[ACPToolContent]:
    """
    解析单个 ToolCallContent（严格按 ACP 规范三种类型）
    """
    if item is None:
        return None

    content_type = safe_str(getattr(item, "type", ""))

    if content_type == "diff":
        return ACPToolContent(
            type="diff",
            path=safe_str(getattr(item, "path", "")),
            old_text=safe_str(getattr(item, "oldText", "")),  # ACP camelCase
            new_text=safe_str(getattr(item, "newText", "")),   # ACP camelCase
        )

    if content_type == "terminal":
        return ACPToolContent(
            type="terminal",
            terminal_id=safe_str(getattr(item, "terminalId", "")),  # ACP camelCase
        )

    if content_type == "content":
        inner = getattr(item, "content", None)
        text = safe_str(getattr(inner, "text", "")) if inner else ""
        return ACPToolContent(type="content", text=text)

    # 有 text 属性的未知类型
    if hasattr(item, "text"):
        return ACPToolContent(type="content", text=safe_str(getattr(item, "text", "")))

    logger.debug(f"ACP 未识别的 ToolCallContent 类型: {content_type}")
    return None


def _parse_location_list(raw: Any) -> list[ACPLocation]:
    """解析 ToolCallLocation[] 数组"""
    if raw is None:
        return []
    items = raw if isinstance(raw, list) else [raw]
    result = []
    for item in items:
        path = safe_str(getattr(item, "path", ""))
        if not path:
            continue
        result.append(ACPLocation(
            path=path,
            line=safe_int(getattr(item, "line", None)),
        ))
    return result
