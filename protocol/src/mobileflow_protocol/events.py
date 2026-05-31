"""
事件类型定义
Agent 内部事件，用于模块间通信
"""

from __future__ import annotations

from enum import Enum
from typing import Optional

from pydantic import BaseModel


class EventType(str, Enum):
    """内部事件类型"""

    # CLI 生命周期
    CLI_STARTED = "cli.started"
    CLI_STOPPED = "cli.stopped"
    CLI_OUTPUT = "cli.output"
    CLI_ERROR = "cli.error"

    # 文件变更（watchfiles 触发）
    FILE_CHANGED = "file.changed"
    FILE_CREATED = "file.created"
    FILE_DELETED = "file.deleted"

    # 连接状态
    CLIENT_CONNECTED = "client.connected"
    CLIENT_DISCONNECTED = "client.disconnected"


class Event(BaseModel):
    """内部事件基类"""

    type: EventType
    data: dict = {}
    source: Optional[str] = None
