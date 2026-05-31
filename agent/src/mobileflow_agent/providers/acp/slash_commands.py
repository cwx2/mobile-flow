"""
ACP Slash Commands — 可用命令广播

对应官网: https://agentclientprotocol.com/protocol/slash-commands

通知：session/update (sessionUpdate: "available_commands_update")

关键规则：
  - Agent 在创建会话后可以发送可用命令列表
  - 命令可以随时动态更新（添加/删除/修改）
  - 命令通过 session/prompt 以 /command 前缀执行
  - 命令可以和其他内容类型（图片、音频等）一起发送
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from .overview import safe_str


@dataclass
class ACPCommandInput:
    """
    命令输入规范
    规范字段: hint (optional)
    """
    hint: str = ""  # 输入提示文本


@dataclass
class ACPCommand:
    """
    ACP AvailableCommand — 单个可用命令
    规范字段: name (required), description (required), input (optional)
    """
    name: str = ""            # 命令名（如 "web", "test", "plan"）
    description: str = ""     # 人类可读描述
    input: Optional[ACPCommandInput] = None  # 输入规范


def parse_commands(update: Any) -> list[ACPCommand]:
    """解析 available_commands_update"""
    commands = []
    for c in getattr(update, "availableCommands", getattr(update, "commands", [])) or []:
        input_raw = getattr(c, "input", None)
        cmd_input = None
        if input_raw:
            cmd_input = ACPCommandInput(hint=safe_str(getattr(input_raw, "hint", "")))
        commands.append(ACPCommand(
            name=safe_str(getattr(c, "name", "")),
            description=safe_str(getattr(c, "description", "")),
            input=cmd_input,
        ))
    return commands
