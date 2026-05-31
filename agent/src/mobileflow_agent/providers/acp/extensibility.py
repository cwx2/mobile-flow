"""
ACP Extensibility — 自定义扩展机制

对应官网: https://agentclientprotocol.com/protocol/extensibility

三种扩展机制：
  1. _meta 字段: 所有类型都有，用于附加自定义数据
  2. 自定义方法: 下划线前缀（如 _zed.dev/workspace/buffers）
  3. 自定义能力: 在 capabilities._meta 中广播

关键规则：
  - 不得在规范类型的根级别添加自定义字段（所有名称保留给未来版本）
  - _meta 中的 traceparent / tracestate / baggage 保留给 W3C trace context
  - 自定义请求遵循 JSON-RPC 2.0 语义（有 id = 请求，无 id = 通知）
  - 不识别的自定义请求返回 -32601 Method not found
  - 不识别的自定义通知应忽略
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional


@dataclass
class ACPMeta:
    """
    ACP _meta 字段 — 自定义元数据容器
    所有 ACP 类型都可以包含 _meta
    """
    data: dict = field(default_factory=dict)

    # W3C trace context 保留字段
    @property
    def traceparent(self) -> str:
        return self.data.get("traceparent", "")

    @property
    def tracestate(self) -> str:
        return self.data.get("tracestate", "")

    @property
    def baggage(self) -> str:
        return self.data.get("baggage", "")


def extract_meta(obj: Any) -> Optional[ACPMeta]:
    """从任意 ACP 对象提取 _meta 字段"""
    meta = getattr(obj, "_meta", None)
    if meta and isinstance(meta, dict):
        return ACPMeta(data=meta)
    return None
