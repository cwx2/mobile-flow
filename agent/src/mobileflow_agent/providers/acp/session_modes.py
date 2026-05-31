"""
ACP Session Modes — Agent 操作模式

对应官网: https://agentclientprotocol.com/protocol/session-modes

方法：
  - session/set_mode: Client 切换模式（sessionId, modeId）

通知：
  - current_mode_update: Agent 主动切换模式

关键规则：
  - session/new 响应中可能包含 modes（currentModeId + availableModes）
  - 模式可以在会话任何时候切换（空闲或生成中）
  - 模式影响系统提示词、工具可用性、权限策略
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from .overview import safe_str


@dataclass
class ACPMode:
    """
    ACP SessionMode — 单个操作模式
    规范字段: id (required), name (required), description (optional)
    """
    id: str = ""              # 模式唯一标识
    name: str = ""            # 人类可读名称
    description: str = ""     # 模式描述


@dataclass
class ACPModeState:
    """
    ACP SessionModeState — 模式状态
    规范字段: currentModeId, availableModes
    """
    current_mode_id: str = ""                          # ACP: currentModeId
    available_modes: list[ACPMode] = field(default_factory=list)  # ACP: availableModes


@dataclass
class ACPModeChange:
    """
    current_mode_update 通知
    规范字段: modeId
    """
    mode_id: str = ""  # ACP: modeId


def parse_mode_state(raw: Any) -> ACPModeState:
    """从 session/new 响应的 modes 字段解析"""
    if raw is None:
        return ACPModeState()
    return ACPModeState(
        current_mode_id=safe_str(getattr(raw, "currentModeId", getattr(raw, "current_mode_id", ""))),
        available_modes=[
            ACPMode(
                id=safe_str(getattr(m, "id", "")),
                name=safe_str(getattr(m, "name", "")),
                description=safe_str(getattr(m, "description", "")),
            )
            for m in (getattr(raw, "availableModes", getattr(raw, "available_modes", [])) or [])
        ],
    )
