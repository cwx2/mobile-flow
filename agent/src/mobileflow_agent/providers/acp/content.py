"""
ACP Content — 内容块类型定义

对应官网: https://agentclientprotocol.com/protocol/content

ContentBlock 出现在：
  - session/prompt 的用户输入
  - session/update 的 AI 输出
  - Tool Call 的进度和结果

内容类型（与 MCP ContentBlock 结构一致）：
  - text: 纯文本（所有 Agent 必须支持）
  - image: 图片（需要 image prompt capability）
  - audio: 音频（需要 audio prompt capability）
  - resource: 嵌入资源（需要 embeddedContext prompt capability）
  - resource_link: 资源引用链接
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional


class ACPContentType(str, Enum):
    """ACP ContentBlock.type — 内容块类型"""
    TEXT = "text"
    IMAGE = "image"
    AUDIO = "audio"
    RESOURCE = "resource"
    RESOURCE_LINK = "resource_link"


@dataclass
class ACPContentBlock:
    """
    ACP ContentBlock — 通用内容块
    根据 type 字段，不同的属性有效
    """
    type: str = "text"  # text / image / audio / resource / resource_link

    # text 类型
    text: str = ""

    # image 类型（ACP: mimeType, data）
    mime_type: str = ""       # ACP: mimeType
    data: str = ""            # Base64 编码数据（image / audio 共用）

    # audio 类型（同 image，用 mime_type + data）

    # resource 类型（ACP: resource.uri, resource.text, resource.mimeType）
    resource_uri: str = ""
    resource_text: str = ""
    resource_mime_type: str = ""

    # resource_link 类型（ACP: uri, name, mimeType, title, description, size）
    uri: str = ""
    name: str = ""
    title: str = ""
    description: str = ""
    size: Optional[int] = None

    # 所有类型共有（ACP: _meta）
    meta: Optional[dict] = None  # ACP: _meta


def parse_content_block(raw: Any) -> Optional[ACPContentBlock]:
    """从 ACP SDK 对象解析 ContentBlock"""
    if raw is None:
        return None

    content_type = getattr(raw, "type", "text") or "text"

    block = ACPContentBlock(type=content_type)

    if content_type == "text":
        block.text = getattr(raw, "text", "") or ""

    elif content_type == "image":
        block.mime_type = getattr(raw, "mimeType", getattr(raw, "mime_type", "")) or ""
        block.data = getattr(raw, "data", "") or ""

    elif content_type == "audio":
        block.mime_type = getattr(raw, "mimeType", getattr(raw, "mime_type", "")) or ""
        block.data = getattr(raw, "data", "") or ""

    elif content_type == "resource":
        res = getattr(raw, "resource", None)
        if res:
            block.resource_uri = getattr(res, "uri", "") or ""
            block.resource_text = getattr(res, "text", "") or ""
            block.resource_mime_type = getattr(res, "mimeType", getattr(res, "mime_type", "")) or ""

    elif content_type == "resource_link":
        block.uri = getattr(raw, "uri", "") or ""
        block.name = getattr(raw, "name", "") or ""
        block.mime_type = getattr(raw, "mimeType", getattr(raw, "mime_type", "")) or ""
        block.title = getattr(raw, "title", "") or ""
        block.description = getattr(raw, "description", "") or ""
        block.size = getattr(raw, "size", None)

    block.meta = getattr(raw, "_meta", None)
    return block
