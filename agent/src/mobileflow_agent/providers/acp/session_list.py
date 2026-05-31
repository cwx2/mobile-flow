"""
ACP Session List — 发现已有会话

对应官网: https://agentclientprotocol.com/protocol/session-list

方法：
  - session/list: 列出 Agent 已知的会话（可选 cwd 过滤 + cursor 分页）

通知：
  - session_info_update: Agent 实时推送会话元数据更新（标题等）

关键规则：
  - 需要 sessionCapabilities.list 能力
  - cursor 是不透明令牌，Client 不得解析/修改/持久化
  - nextCursor 缺失 = 没有更多结果
  - session/list 只是发现机制，不恢复或修改会话
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

from .overview import safe_str


@dataclass
class ACPSessionSummary:
    """
    session/list 返回的单个会话摘要
    规范字段: sessionId (required), cwd (required), title, updatedAt, _meta
    """
    session_id: str = ""          # ACP: sessionId — 会话唯一标识
    cwd: str = ""                 # 工作目录（绝对路径）
    title: str = ""               # 人类可读标题（可能从首条 prompt 自动生成）
    updated_at: str = ""          # ACP: updatedAt — ISO 8601 时间戳
    meta: Optional[dict] = None   # ACP: _meta — 自定义元数据


@dataclass
class ACPSessionListResult:
    """
    session/list 的完整响应
    规范字段: sessions (required), nextCursor (optional)
    """
    sessions: list[ACPSessionSummary] = field(default_factory=list)
    next_cursor: Optional[str] = None  # ACP: nextCursor — 分页游标


@dataclass
class ACPSessionInfoUpdate:
    """
    session_info_update 通知 — Agent 实时推送会话元数据变更
    规范字段: title, updatedAt, _meta（都是 optional，只包含变更的字段）
    """
    title: Optional[str] = None        # 设为 None 表示清除
    updated_at: Optional[str] = None   # ACP: updatedAt
    meta: Optional[dict] = None        # ACP: _meta


# ── 解析函数 ──


def parse_session_list_result(raw: Any) -> ACPSessionListResult:
    """解析 session/list 响应"""
    sessions = []
    for s in getattr(raw, "sessions", []) or []:
        sessions.append(ACPSessionSummary(
            session_id=safe_str(getattr(s, "session_id", getattr(s, "sessionId", ""))),
            cwd=safe_str(getattr(s, "cwd", "")),
            title=safe_str(getattr(s, "title", "")),
            updated_at=safe_str(getattr(s, "updated_at", getattr(s, "updatedAt", ""))),
            meta=getattr(s, "_meta", None),
        ))
    return ACPSessionListResult(
        sessions=sessions,
        next_cursor=getattr(raw, "next_cursor", getattr(raw, "nextCursor", None)),
    )
