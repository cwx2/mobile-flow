"""
ACP Transports — 传输层

对应官网: https://agentclientprotocol.com/protocol/transports

传输类型：
  - stdio: Client 启动 Agent 子进程，通过 stdin/stdout 通信（必须支持）
  - Streamable HTTP: 草案讨论中
  - 自定义传输: 可以实现任意双向通信通道

stdio 规则：
  - JSON-RPC 消息必须 UTF-8 编码
  - 消息以换行符 \\n 分隔，不得包含嵌入换行
  - Agent 可以向 stderr 写日志
  - Agent 的 stdout 只能写有效 ACP 消息
  - Client 的 stdin 只能写有效 ACP 消息
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class ACPTransportType(str, Enum):
    """ACP 传输类型"""
    STDIO = "stdio"
    HTTP = "http"          # Streamable HTTP（草案）
    CUSTOM = "custom"      # 自定义传输


@dataclass
class ACPTransportConfig:
    """传输层配置"""
    type: str = "stdio"    # stdio / http / custom
    # stdio 特有
    command: str = ""      # Agent 可执行文件路径
    args: list[str] = None  # type: ignore  # 命令行参数
    # http 特有
    url: str = ""          # HTTP 端点 URL

    def __post_init__(self):
        if self.args is None:
            self.args = []
