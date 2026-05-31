"""
ACP Session Setup — 创建和加载会话

对应官网: https://agentclientprotocol.com/protocol/session-setup

方法：
  - session/new: 创建新会话（cwd, mcpServers）→ sessionId
  - session/load: 加载已有会话（需要 loadSession 能力）→ 通过 session/update 回放历史

关键规则：
  - cwd 必须是绝对路径
  - cwd 用于会话的文件系统上下文，不管 Agent 进程在哪里启动
  - session/load 时 Agent 必须通过 session/update 回放完整对话历史
  - MCP 服务器：所有 Agent 必须支持 stdio 传输，HTTP/SSE 是可选能力
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from .overview import safe_str


# ── MCP 服务器配置 ──


@dataclass
class ACPEnvVariable:
    """MCP 服务器环境变量"""
    name: str = ""
    value: str = ""


@dataclass
class ACPHttpHeader:
    """MCP HTTP/SSE 传输的 HTTP 头"""
    name: str = ""
    value: str = ""


@dataclass
class ACPMcpServer:
    """
    MCP 服务器配置（三种传输类型）
    - stdio: command + args + env
    - http: url + headers (type="http")
    - sse: url + headers (type="sse")
    """
    name: str = ""                                    # 人类可读标识
    transport_type: str = "stdio"                     # "stdio" / "http" / "sse"
    # stdio 传输
    command: str = ""                                 # 可执行文件绝对路径
    args: list[str] = field(default_factory=list)     # 命令行参数
    env: list[ACPEnvVariable] = field(default_factory=list)  # 环境变量
    # http / sse 传输
    url: str = ""                                     # 服务器 URL
    headers: list[ACPHttpHeader] = field(default_factory=list)  # HTTP 头


# ── Session 结果 ──


@dataclass
class ACPNewSessionResult:
    """
    session/new 的响应
    规范字段: sessionId (required), modes (optional)
    """
    session_id: str = ""                              # ACP: sessionId
    available_modes: list[dict] = field(default_factory=list)  # 可用模式列表


@dataclass
class ACPLoadSessionResult:
    """
    session/load 的响应
    Agent 通过 session/update 回放历史后，返回 null result
    """
    session_id: str = ""


# ── 解析函数 ──


def parse_new_session_result(raw: Any) -> ACPNewSessionResult:
    """解析 session/new 响应"""
    session_id = safe_str(getattr(raw, "session_id", ""))
    modes_raw = getattr(raw, "modes", None)
    available_modes = []
    if modes_raw:
        for m in getattr(modes_raw, "available_modes", []) or []:
            available_modes.append({
                "id": safe_str(getattr(m, "id", "")),
                "name": safe_str(getattr(m, "name", "")),
            })
    return ACPNewSessionResult(session_id=session_id, available_modes=available_modes)
