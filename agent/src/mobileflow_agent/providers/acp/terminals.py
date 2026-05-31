"""
ACP Terminals — 终端命令执行和管理

对应官网: https://agentclientprotocol.com/protocol/terminals

方法（Agent → Client 调用）：
  - terminal/create: 创建终端执行命令 → terminalId
  - terminal/output: 获取终端输出（不等待完成）
  - terminal/wait_for_exit: 等待命令完成
  - terminal/kill: 终止命令（不释放终端）
  - terminal/release: 释放终端（如果还在运行则先终止）

关键规则：
  - 需要 clientCapabilities.terminal 能力
  - terminal/create 立即返回 terminalId，命令在后台运行
  - 终端可以嵌入 ToolCallContent（type: "terminal"）实时显示输出
  - kill 后终端仍然有效（可以 output/wait_for_exit），必须 release
  - release 后 terminalId 失效
  - outputByteLimit 超限时从头部截断，必须在字符边界截断
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ACPTerminalEnv:
    """终端环境变量"""
    name: str = ""
    value: str = ""


@dataclass
class ACPTerminal:
    """
    terminal/create 请求参数
    规范字段: sessionId, command (required), args, env, cwd, outputByteLimit
    """
    session_id: str = ""                              # ACP: sessionId
    command: str = ""                                 # 命令（required）
    args: list[str] = field(default_factory=list)     # 命令参数
    env: list[ACPTerminalEnv] = field(default_factory=list)  # 环境变量
    cwd: str = ""                                     # 工作目录（绝对路径）
    output_byte_limit: Optional[int] = None           # ACP: outputByteLimit


@dataclass
class ACPTerminalCreateResult:
    """terminal/create 响应"""
    terminal_id: str = ""  # ACP: terminalId


@dataclass
class ACPTerminalExitStatus:
    """终端退出状态"""
    exit_code: Optional[int] = None  # ACP: exitCode
    signal: Optional[str] = None     # ACP: signal


@dataclass
class ACPTerminalOutputResult:
    """
    terminal/output 响应
    规范字段: output, truncated, exitStatus (optional)
    """
    output: str = ""                                    # 终端输出内容
    truncated: bool = False                             # 是否因 byte limit 被截断
    exit_status: Optional[ACPTerminalExitStatus] = None  # ACP: exitStatus（命令已退出时才有）
