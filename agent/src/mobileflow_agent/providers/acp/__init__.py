"""
ACP 协议基础包（Agent Client Protocol）

严格按 ACP 规范（agentclientprotocol.com）定义所有协议类型。
每个文件对应官网 Protocol 导航栏的一个页面。

包结构：
  overview.py          — 基础规则、通用工具函数
  initialization.py    — initialize 握手、能力协商、认证方法
  session_setup.py     — session/new, session/load
  session_list.py      — session/list
  prompt_turn.py       — session/prompt, session/update, session/cancel
  content.py           — Content blocks (text/image/resource)
  tool_calls.py        — ToolCall, ToolCallUpdate, ToolCallContent, ToolCallLocation
  file_system.py       — fs/read_text_file, fs/write_text_file
  terminals.py         — terminal/* 方法
  agent_plan.py        — AgentPlanUpdate
  session_modes.py     — session/set_mode, CurrentModeUpdate
  session_config.py    — Session Config Options
  slash_commands.py    — AvailableCommandsUpdate
  extensibility.py     — _meta 字段, 自定义方法/能力
  transports.py        — stdio / SSE 传输层
  schema.py            — JSON-RPC 2.0 基础 + Schema 引用

使用方式：
  from mobileflow_agent.providers.acp import ACPToolCall, ACPLocation, ...
  from mobileflow_agent.providers.acp.tool_calls import parse_tool_call
"""

# 从各模块导出核心类型（按使用频率排序）
from .tool_calls import (
    ACPToolCall,
    ACPToolContent,
    ACPToolKind,
    ACPToolStatus,
    ACPLocation,
)
from .content import ACPContentBlock, ACPContentType
from .initialization import (
    ACPAgentCapabilities,
    ACPAgentInfo,
    ACPClientCapabilities,
    ACPClientInfo,
    ACPInitializeResult,
    ACPAuthMethod,
)
from .prompt_turn import ACPMessage, ACPThought, ACPSessionUpdate
from .session_setup import ACPNewSessionResult, ACPLoadSessionResult
from .session_list import ACPSessionSummary
from .agent_plan import ACPPlan, ACPPlanEntry
from .session_modes import ACPMode, ACPModeChange
from .session_config import ACPConfigOption
from .slash_commands import ACPCommand
from .terminals import ACPTerminal
from .file_system import ACPFileRead, ACPFileWrite
from .extensibility import ACPMeta

__all__ = [
    # tool_calls
    "ACPToolCall", "ACPToolContent", "ACPToolKind", "ACPToolStatus", "ACPLocation",
    # content
    "ACPContentBlock", "ACPContentType",
    # initialization
    "ACPAgentCapabilities", "ACPAgentInfo", "ACPClientCapabilities", "ACPClientInfo",
    "ACPInitializeResult", "ACPAuthMethod",
    # prompt_turn
    "ACPMessage", "ACPThought", "ACPSessionUpdate",
    # session
    "ACPNewSessionResult", "ACPLoadSessionResult", "ACPSessionSummary",
    # plan
    "ACPPlan", "ACPPlanEntry",
    # modes
    "ACPMode", "ACPModeChange",
    # config
    "ACPConfigOption",
    # commands
    "ACPCommand",
    # terminals
    "ACPTerminal",
    # file_system
    "ACPFileRead", "ACPFileWrite",
    # extensibility
    "ACPMeta",
]
