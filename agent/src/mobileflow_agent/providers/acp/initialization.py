"""
ACP Initialization — 版本协商、能力交换、认证方法

对应官网: https://agentclientprotocol.com/protocol/initialization

流程：
  1. Client → Agent: initialize(protocolVersion, clientCapabilities, clientInfo)
  2. Agent → Client: result(protocolVersion, agentCapabilities, agentInfo, authMethods)
  3. Client → Agent: authenticate(methodId, data) — 如果 authMethods 非空

关键规则：
  - protocolVersion 是单个整数（MAJOR 版本），只在破坏性变更时递增
  - 所有 capabilities 都是 OPTIONAL，省略 = 不支持
  - 新增 capability 不算破坏性变更
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from .overview import safe_str


# ── 实现信息 ──


@dataclass
class ACPClientInfo:
    """
    Client 实现信息（clientInfo）
    规范字段: name, title (optional), version
    """
    name: str = ""       # 程序化标识（如 "mobileflow"）
    title: str = ""      # 人类可读名称（如 "MobileFlow IDE"），可选
    version: str = ""    # 版本号


@dataclass
class ACPAgentInfo:
    """
    Agent 实现信息（agentInfo）
    规范字段: name, title (optional), version
    """
    name: str = ""       # 程序化标识（如 "kiro-agent"）
    title: str = ""      # 人类可读名称（如 "Kiro Agent"），可选
    version: str = ""    # 版本号


# ── 能力声明 ──


@dataclass
class ACPPromptCapabilities:
    """
    Agent 的 prompt 输入能力（promptCapabilities）
    基线：所有 Agent 必须支持 ContentBlock::Text 和 ContentBlock::ResourceLink
    可选：image, audio, embeddedContext
    """
    image: bool = False           # 支持 ContentBlock::Image
    audio: bool = False           # 支持 ContentBlock::Audio
    embedded_context: bool = False  # 支持 ContentBlock::Resource（ACP: embeddedContext）


@dataclass
class ACPMcpCapabilities:
    """
    Agent 的 MCP 连接能力（mcpCapabilities）
    """
    http: bool = False   # 支持 MCP over HTTP
    sse: bool = False    # 支持 MCP over SSE（已被 MCP 规范废弃）


@dataclass
class ACPSessionCapabilities:
    """
    Agent 的会话能力（从 agentCapabilities 中提取）
    基线：session/new, session/prompt, session/cancel, session/update
    可选：loadSession, listSessions, closeSession, forkSession, resumeSession
    """
    load_session: bool = False     # ACP: loadSession
    list_sessions: bool = False    # ACP: listSessions（来自 session_list 规范）
    close_session: bool = False    # ACP: closeSession
    fork_session: bool = False     # ACP: forkSession
    resume_session: bool = False   # ACP: resumeSession


@dataclass
class ACPClientCapabilities:
    """
    Client 能力声明（clientCapabilities）
    规范字段: fs.readTextFile, fs.writeTextFile, terminal
    """
    fs_read: bool = False      # ACP: fs.readTextFile — fs/read_text_file 可用
    fs_write: bool = False     # ACP: fs.writeTextFile — fs/write_text_file 可用
    terminal: bool = False     # ACP: terminal — 所有 terminal/* 方法可用


@dataclass
class ACPAgentCapabilities:
    """
    Agent 能力声明（agentCapabilities）
    """
    prompt: ACPPromptCapabilities = field(default_factory=ACPPromptCapabilities)
    mcp: ACPMcpCapabilities = field(default_factory=ACPMcpCapabilities)
    session: ACPSessionCapabilities = field(default_factory=ACPSessionCapabilities)


# ── 认证 ──


@dataclass
class ACPAuthMethod:
    """
    认证方法（authMethods 数组中的一项）
    规范字段: id, name, description
    """
    id: str = ""
    name: str = ""
    description: str = ""


# ── Initialize 结果 ──


@dataclass
class ACPInitializeResult:
    """
    initialize 方法的完整响应
    """
    protocol_version: int = 1                    # ACP: protocolVersion
    agent_info: ACPAgentInfo = field(default_factory=ACPAgentInfo)
    agent_capabilities: ACPAgentCapabilities = field(default_factory=ACPAgentCapabilities)
    auth_methods: list[ACPAuthMethod] = field(default_factory=list)


# ── 解析函数 ──


def parse_initialize_result(raw: Any) -> ACPInitializeResult:
    """从 ACP SDK 的 initialize 响应对象解析为 ACPInitializeResult"""
    agent_info_raw = getattr(raw, "agent_info", None)
    agent_caps_raw = getattr(raw, "agent_capabilities", None)
    auth_raw = getattr(raw, "auth_methods", None) or []

    # Agent Info
    agent_info = ACPAgentInfo(
        name=safe_str(getattr(agent_info_raw, "name", "")) if agent_info_raw else "",
        title=safe_str(getattr(agent_info_raw, "title", "")) if agent_info_raw else "",
        version=safe_str(getattr(agent_info_raw, "version", "")) if agent_info_raw else "",
    )

    # Prompt Capabilities
    prompt_caps_raw = getattr(agent_caps_raw, "prompt_capabilities", None) if agent_caps_raw else None
    prompt_caps = ACPPromptCapabilities(
        image=bool(getattr(prompt_caps_raw, "image", False)) if prompt_caps_raw else False,
        audio=bool(getattr(prompt_caps_raw, "audio", False)) if prompt_caps_raw else False,
        embedded_context=bool(getattr(prompt_caps_raw, "embedded_context", False)) if prompt_caps_raw else False,
    )

    # MCP Capabilities
    mcp_caps_raw = getattr(agent_caps_raw, "mcp_capabilities", None) if agent_caps_raw else None
    mcp_caps = ACPMcpCapabilities(
        http=bool(getattr(mcp_caps_raw, "http", False)) if mcp_caps_raw else False,
        sse=bool(getattr(mcp_caps_raw, "sse", False)) if mcp_caps_raw else False,
    )

    # Session Capabilities
    session_caps = ACPSessionCapabilities(
        load_session=bool(getattr(agent_caps_raw, "load_session", False)) if agent_caps_raw else False,
        list_sessions=bool(getattr(agent_caps_raw, "list_sessions", False)) if agent_caps_raw else False,
        close_session=bool(getattr(agent_caps_raw, "close_session", False)) if agent_caps_raw else False,
        fork_session=bool(getattr(agent_caps_raw, "fork_session", False)) if agent_caps_raw else False,
        resume_session=bool(getattr(agent_caps_raw, "resume_session", False)) if agent_caps_raw else False,
    )

    # Auth Methods
    auth_methods = [
        ACPAuthMethod(
            id=safe_str(getattr(m, "id", "")),
            name=safe_str(getattr(m, "name", "")),
            description=safe_str(getattr(m, "description", "")),
        )
        for m in auth_raw
    ]

    return ACPInitializeResult(
        protocol_version=getattr(raw, "protocol_version", 1) or 1,
        agent_info=agent_info,
        agent_capabilities=ACPAgentCapabilities(
            prompt=prompt_caps, mcp=mcp_caps, session=session_caps,
        ),
        auth_methods=auth_methods,
    )
