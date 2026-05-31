"""
ACP Session Config Options — 会话配置选项

对应官网: https://agentclientprotocol.com/protocol/session-config-options

方法：
  - session/set_config_option: Client 设置配置值（configId, value）

通知：
  - config_option_update: Agent 推送配置变更

关键规则：
  - configOptions 数组顺序代表优先级，Client 应尊重排序
  - 目前只支持 select 类型
  - Agent 必须为每个选项提供默认值
  - 设置后 Agent 必须返回完整配置列表
  - 预留 category: mode / model / thought_level
  - 下划线开头的 category 可自定义
  - Session Config Options 取代旧的 Session Modes API
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from .overview import safe_str


@dataclass
class ACPConfigOptionValue:
    """
    配置选项的可选值
    规范字段: value (required), name (required), description (optional)
    """
    value: str = ""          # 值标识
    name: str = ""           # 人类可读名称
    description: str = ""    # 描述


@dataclass
class ACPConfigOption:
    """
    单个配置选项
    规范字段: id, name, description, category, type, currentValue, options[]
    """
    id: str = ""                    # 唯一标识
    name: str = ""                  # 人类可读标签
    description: str = ""           # 描述
    category: str = ""              # 语义分类: mode / model / thought_level / _custom
    type: str = "select"            # 输入类型（目前只有 select）
    current_value: str = ""         # ACP: currentValue — 当前选中值
    options: list[ACPConfigOptionValue] = field(default_factory=list)


def parse_config_options(raw: Any) -> list[ACPConfigOption]:
    """从 session/new 响应或 config_option_update 解析配置选项列表"""
    if raw is None:
        return []
    items = raw if isinstance(raw, list) else getattr(raw, "config_options", getattr(raw, "configOptions", [])) or []
    result = []
    for item in items:
        options = []
        for opt in getattr(item, "options", []) or []:
            options.append(ACPConfigOptionValue(
                value=safe_str(getattr(opt, "value", "")),
                name=safe_str(getattr(opt, "name", "")),
                description=safe_str(getattr(opt, "description", "")),
            ))
        result.append(ACPConfigOption(
            id=safe_str(getattr(item, "id", "")),
            name=safe_str(getattr(item, "name", "")),
            description=safe_str(getattr(item, "description", "")),
            category=safe_str(getattr(item, "category", "")),
            type=safe_str(getattr(item, "type", "select")),
            current_value=safe_str(getattr(item, "currentValue", getattr(item, "current_value", ""))),
            options=options,
        ))
    return result
