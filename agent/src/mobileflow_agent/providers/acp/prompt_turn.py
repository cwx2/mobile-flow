"""
ACP Prompt Turn — 对话回合生命周期

对应官网: https://agentclientprotocol.com/protocol/prompt-turn

生命周期：
  1. Client → Agent: session/prompt(sessionId, prompt[])
  2. Agent 处理，发送 session/update 通知（消息、工具调用、计划等）
  3. 工具调用可能触发 session/request_permission
  4. 工具完成后结果返回给 LLM，循环到步骤 2
  5. 回合结束：Agent 返回 session/prompt 响应 + StopReason
  6. Client 可发 session/cancel 取消

session/update 的 sessionUpdate 类型：
  - agent_message_chunk: AI 文本回复
  - agent_thought_chunk: AI 思考过程
  - user_message_chunk: 用户消息回显（session/load 回放时）
  - tool_call: 工具调用开始
  - tool_call_update: 工具调用进度/结果
  - plan: 执行计划
  - available_commands_update: 可用命令变更
  - current_mode_update: 模式变更
  - session_info_update: 会话元信息变更
  - config_option_update: 配置选项变更

StopReason：
  - end_turn: LLM 正常完成
  - max_tokens: 达到 token 上限
  - max_model_requests: 达到模型请求次数上限
  - refused: Agent 拒绝继续
  - cancelled: Client 取消
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional

from .overview import safe_str


class ACPStopReason(str, Enum):
    """ACP StopReason — 回合结束原因"""
    END_TURN = "end_turn"
    MAX_TOKENS = "max_tokens"
    MAX_MODEL_REQUESTS = "max_model_requests"
    REFUSED = "refused"
    CANCELLED = "cancelled"


class ACPSessionUpdateType(str, Enum):
    """ACP sessionUpdate 字段值 — session/update 通知的事件类型"""
    AGENT_MESSAGE = "agent_message_chunk"
    AGENT_THOUGHT = "agent_thought_chunk"
    USER_MESSAGE = "user_message_chunk"
    TOOL_CALL = "tool_call"
    TOOL_CALL_UPDATE = "tool_call_update"
    PLAN = "plan"
    AVAILABLE_COMMANDS = "available_commands_update"
    CURRENT_MODE = "current_mode_update"
    SESSION_INFO = "session_info_update"
    CONFIG_OPTION = "config_option_update"


@dataclass
class ACPMessage:
    """
    ACP AgentMessageChunk / UserMessageChunk — 文本消息
    规范字段: content (ContentBlock), messageId (optional)
    """
    text: str = ""
    message_id: Optional[str] = None  # ACP: messageId
    is_user: bool = False             # True = user_message_chunk


@dataclass
class ACPThought:
    """
    ACP AgentThoughtChunk — AI 思考过程
    规范字段: content (ContentBlock with text)
    """
    text: str = ""


@dataclass
class ACPPromptResult:
    """
    session/prompt 的响应
    规范字段: stopReason (required)
    """
    stop_reason: str = ""  # ACP: stopReason


@dataclass
class ACPSessionUpdate:
    """
    session/update 通知的完整数据
    包含 sessionId + update 对象
    """
    session_id: str = ""
    update_type: str = ""  # ACPSessionUpdateType 的值
    raw_update: Any = None  # 原始 update 对象，供各模块解析


# ── 解析函数 ──


def parse_message(update: Any, is_user: bool = False) -> ACPMessage:
    """解析 agent_message_chunk / user_message_chunk"""
    content = getattr(update, "content", None)
    text = ""
    if content:
        text = getattr(content, "text", "") or ""
        if not text and isinstance(content, list):
            text = "".join(getattr(b, "text", "") for b in content if hasattr(b, "text"))
    return ACPMessage(
        text=text,
        message_id=getattr(update, "message_id", None),
        is_user=is_user,
    )


def parse_thought(update: Any) -> ACPThought:
    """解析 agent_thought_chunk"""
    content = getattr(update, "content", None)
    text = ""
    if content:
        text = getattr(content, "text", "") or ""
    if not text:
        text = getattr(update, "thought", "") or ""
    return ACPThought(text=text)
