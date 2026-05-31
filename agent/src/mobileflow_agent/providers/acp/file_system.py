"""
ACP File System — Client 文件系统访问

对应官网: https://agentclientprotocol.com/protocol/file-system

方法（Agent → Client 调用）：
  - fs/read_text_file: 读取文件内容（支持 line + limit 参数）
  - fs/write_text_file: 写入文件内容（文件不存在时 Client 必须创建）

关键规则：
  - 需要 clientCapabilities.fs.readTextFile / writeTextFile 能力
  - path 必须是绝对路径
  - line 从 1 开始
  - 读取可以获取编辑器中未保存的内容
  - 写入让 Client 能追踪 Agent 的文件修改
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class ACPFileRead:
    """
    fs/read_text_file 请求参数
    规范字段: sessionId, path (required), line (optional), limit (optional)
    """
    session_id: str = ""     # ACP: sessionId
    path: str = ""           # 绝对路径
    line: Optional[int] = None   # 起始行号（1-based）
    limit: Optional[int] = None  # 最大读取行数


@dataclass
class ACPFileReadResult:
    """
    fs/read_text_file 响应
    规范字段: content
    """
    content: str = ""


@dataclass
class ACPFileWrite:
    """
    fs/write_text_file 请求参数
    规范字段: sessionId, path (required), content (required)
    """
    session_id: str = ""     # ACP: sessionId
    path: str = ""           # 绝对路径（不存在时 Client 必须创建）
    content: str = ""        # 要写入的文本内容
