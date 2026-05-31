"""
ACP Schema — JSON-RPC 2.0 基础 + Schema 引用

对应官网: https://agentclientprotocol.com/protocol/schema

ACP 基于 JSON-RPC 2.0 规范：
  - 请求: {jsonrpc: "2.0", id, method, params}
  - 响应: {jsonrpc: "2.0", id, result} 或 {jsonrpc: "2.0", id, error}
  - 通知: {jsonrpc: "2.0", method, params}（无 id，无响应）

错误码（JSON-RPC 2.0 标准）：
  - -32700: Parse error
  - -32600: Invalid Request
  - -32601: Method not found
  - -32602: Invalid params
  - -32603: Internal error

OpenAPI Schema: https://agentclientprotocol.com/api-reference/openapi.json
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Any, Optional


class ACPJsonRpcErrorCode(IntEnum):
    """JSON-RPC 2.0 标准错误码"""
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603


@dataclass
class ACPJsonRpcError:
    """JSON-RPC 2.0 错误对象"""
    code: int = 0
    message: str = ""
    data: Optional[Any] = None


# ACP 方法名常量（方便引用，避免硬编码字符串）

class ACPMethod:
    """ACP 协议方法名"""
    # Agent 端方法（Client → Agent）
    INITIALIZE = "initialize"
    AUTHENTICATE = "authenticate"
    SESSION_NEW = "session/new"
    SESSION_LOAD = "session/load"
    SESSION_PROMPT = "session/prompt"
    SESSION_LIST = "session/list"
    SESSION_SET_MODE = "session/set_mode"
    SESSION_SET_CONFIG = "session/set_config_option"

    # Client 端方法（Agent → Client）
    REQUEST_PERMISSION = "session/request_permission"
    FS_READ = "fs/read_text_file"
    FS_WRITE = "fs/write_text_file"
    TERMINAL_CREATE = "terminal/create"
    TERMINAL_OUTPUT = "terminal/output"
    TERMINAL_WAIT = "terminal/wait_for_exit"
    TERMINAL_KILL = "terminal/kill"
    TERMINAL_RELEASE = "terminal/release"

    # 通知（无响应）
    SESSION_UPDATE = "session/update"
    SESSION_CANCEL = "session/cancel"
