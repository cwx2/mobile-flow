"""
ACP Agent Plan — 执行计划

对应官网: https://agentclientprotocol.com/protocol/agent-plan

通知：session/update (sessionUpdate: "plan")

关键规则：
  - 每次更新必须发送完整的 entries 列表，Client 完全替换当前计划
  - 计划可以动态变化（添加/删除/修改条目）
  - priority: high / medium / low
  - status: pending / in_progress / completed
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from .overview import safe_str


class ACPPlanPriority(str, Enum):
    """ACP PlanEntryPriority"""
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class ACPPlanStatus(str, Enum):
    """ACP PlanEntry status"""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"


@dataclass
class ACPPlanEntry:
    """
    计划条目
    规范字段: content (required), priority (required), status (required)
    """
    content: str = ""       # ACP: content — 任务描述
    priority: str = ""      # high / medium / low
    status: str = ""        # pending / in_progress / completed


@dataclass
class ACPPlan:
    """
    完整计划（entries 数组）
    每次更新都是完整替换
    """
    entries: list[ACPPlanEntry] = field(default_factory=list)


def parse_plan(update: Any) -> ACPPlan:
    """解析 plan update"""
    entries = []
    for e in getattr(update, "entries", []) or []:
        entries.append(ACPPlanEntry(
            content=safe_str(getattr(e, "content", getattr(e, "title", ""))),
            priority=safe_str(getattr(e, "priority", "")),
            status=safe_str(getattr(e, "status", "")),
        ))
    return ACPPlan(entries=entries)
