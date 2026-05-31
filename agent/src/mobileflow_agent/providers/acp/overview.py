"""
ACP Protocol Overview — 基础规则和通用工具函数

对应官网: https://agentclientprotocol.com/protocol/overview

协议基础规则：
  - 基于 JSON-RPC 2.0（Methods = 请求/响应, Notifications = 单向）
  - 所有文件路径必须是绝对路径（All file paths MUST be absolute）
  - 行号从 1 开始（Line numbers are 1-based）
  - 错误处理遵循 JSON-RPC 2.0 error object 规范
  - 扩展性：_meta 字段、下划线前缀自定义方法、自定义能力
"""

from __future__ import annotations

from typing import Any

from loguru import logger


def normalize_status(val: Any) -> str:
    """
    规范化 ACP status 字段值
    ACP SDK 可能返回枚举对象（如 ToolCallStatus.COMPLETED）而不是纯字符串，
    统一转为小写字符串。
    """
    if val is None:
        return ""
    s = str(val)
    # 处理 "ToolCallStatus.COMPLETED" → "completed"
    if "." in s:
        s = s.split(".")[-1]
    return s.lower()


def safe_str(val: Any) -> str:
    """安全转字符串，None → 空字符串"""
    if val is None:
        return ""
    return str(val)


def safe_dict(val: Any) -> dict | None:
    """安全提取 dict，非 dict 返回 None"""
    if val is not None and isinstance(val, dict):
        return val
    return None


def safe_int(val: Any) -> int | None:
    """安全转 int，失败返回 None"""
    if val is None:
        return None
    try:
        return int(val)
    except (TypeError, ValueError):
        return None
