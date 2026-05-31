"""
消息类型定义
所有 WebSocket 通信的消息结构，Agent 和 App 共用
"""

from __future__ import annotations

import time
import uuid
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


class MessageType(str, Enum):
    """消息类型枚举"""

    # 认证相关
    AUTH_PAIR = "auth.pair"
    AUTH_CONNECT = "auth.connect"
    AUTH_RESULT = "auth.result"

    # 对话相关
    CHAT_SEND = "chat.send"
    CHAT_STREAM = "chat.stream"
    CHAT_DONE = "chat.done"
    CHAT_ERROR = "chat.error"
    CHAT_CANCEL = "chat.cancel"

    # 文件相关
    FILE_TREE = "file.tree"
    FILE_TREE_RESULT = "file.tree.result"
    FILE_READ = "file.read"
    FILE_READ_RESULT = "file.read.result"
    FILE_WRITE = "file.write"
    FILE_WRITE_RESULT = "file.write.result"
    FILE_SEARCH = "file.search"
    FILE_SEARCH_RESULT = "file.search.result"
    FILE_CREATE = "file.create"
    FILE_CREATE_RESULT = "file.create.result"
    FILE_RENAME = "file.rename"
    FILE_RENAME_RESULT = "file.rename.result"
    FILE_DELETE = "file.delete"
    FILE_DELETE_RESULT = "file.delete.result"
    FILE_SEARCH_STREAM = "file.search.stream"

    # Diff 相关
    DIFF_PREVIEW = "diff.preview"
    DIFF_APPLY = "diff.apply"
    DIFF_REJECT = "diff.reject"

    # CLI 相关
    CLI_LIST = "cli.list"
    CLI_LIST_RESULT = "cli.list.result"
    CLI_SWITCH = "cli.switch"
    CLI_INSTALL = "cli.install"
    CLI_INSTALL_RESULT = "cli.install.result"
    CLI_INSTALL_PROGRESS = "cli.install.progress"  # Agent -> App: step-by-step install progress
    CLI_UNINSTALL = "cli.uninstall"                # App -> Agent: uninstall request
    CLI_UNINSTALL_RESULT = "cli.uninstall.result"  # Agent -> App: uninstall result
    CLI_ADD = "cli.add"
    CLI_REMOVE = "cli.remove"
    CLI_STATUS = "cli.status"    # Agent -> App: lifecycle state push
    CLI_RETRY = "cli.retry"     # App -> Agent: retry initialization request
    AUTH_SUBMIT = "auth.submit"  # App -> Agent: submit authentication credentials
    MODE_SET = "mode.set"        # App -> Agent: switch session mode
    CONFIG_SET = "config.set"    # App -> Agent: set config option value

    # 确认相关（危险操作）
    CONFIRM_REQUEST = "confirm.request"
    CONFIRM_RESPONSE = "confirm.response"

    # 权限请求（ACP request_permission）
    PERMISSION_REQUEST = "permission.request"
    PERMISSION_RESPONSE = "permission.response"
    PERMISSION_POLICY = "permission.policy"

    # Git 相关
    GIT_DIFF = "git.diff"
    GIT_DIFF_RESULT = "git.diff.result"
    GIT_STATUS = "git.status"
    GIT_STATUS_RESULT = "git.status.result"
    GIT_STAGE = "git.stage"
    GIT_STAGE_RESULT = "git.stage.result"
    GIT_UNSTAGE = "git.unstage"
    GIT_UNSTAGE_RESULT = "git.unstage.result"
    GIT_COMMIT = "git.commit"
    GIT_COMMIT_RESULT = "git.commit.result"
    GIT_PUSH = "git.push"
    GIT_PUSH_RESULT = "git.push.result"
    GIT_PULL = "git.pull"
    GIT_PULL_RESULT = "git.pull.result"
    GIT_BRANCHES = "git.branches"
    GIT_BRANCHES_RESULT = "git.branches.result"
    GIT_CHECKOUT = "git.checkout"
    GIT_CHECKOUT_RESULT = "git.checkout.result"
    GIT_LOG = "git.log"
    GIT_LOG_RESULT = "git.log.result"
    GIT_LOG_SEARCH = "git.log.search"
    GIT_LOG_SEARCH_RESULT = "git.log.search.result"
    GIT_LOG_AUTHORS = "git.log.authors"
    GIT_LOG_AUTHORS_RESULT = "git.log.authors.result"
    GIT_SHOW = "git.show"
    GIT_SHOW_RESULT = "git.show.result"
    GIT_DIFF_COMMIT = "git.diff.commit"
    GIT_DIFF_COMMIT_RESULT = "git.diff.commit.result"
    GIT_DISCARD = "git.discard"
    GIT_DISCARD_RESULT = "git.discard.result"
    GIT_REPOS = "git.repos"
    GIT_REPOS_RESULT = "git.repos.result"
    GIT_SWITCH_REPO = "git.switch_repo"
    GIT_EXEC = "git.exec"
    GIT_EXEC_RESULT = "git.exec.result"

    # 心跳
    STATUS_PING = "status.ping"
    STATUS_PONG = "status.pong"

    # 文件变更通知（Agent -> App）
    FILE_CHANGED = "file.changed"

    # 状态推送（Agent -> App，缓存层自动刷新后推送）
    STATE_PUSH = "state.push"

    # 聊天历史
    CHAT_HISTORY = "chat.history"
    CHAT_HISTORY_RESULT = "chat.history.result"
    CHAT_HISTORY_MORE = "chat.history.more"
    CHAT_HISTORY_MORE_RESULT = "chat.history.more.result"

    # Stream replay (disconnect recovery)
    CHAT_REPLAY = "chat.replay"              # App -> Agent: request buffered chunks
    CHAT_REPLAY_RESULT = "chat.replay.result"  # Agent -> App: replayed chunks batch

    # 会话管理
    SESSION_LIST = "session.list"
    SESSION_LIST_RESULT = "session.list.result"
    SESSION_NEW = "session.new"
    SESSION_SWITCH = "session.switch"
    SESSION_CLOSE = "session.close"

    # 项目/工作目录管理
    PROJECT_LIST = "project.list"
    PROJECT_LIST_RESULT = "project.list.result"
    PROJECT_ADD = "project.add"
    PROJECT_REMOVE = "project.remove"
    PROJECT_SWITCH = "project.switch"
    PROJECT_CURRENT = "project.current"
    PROJECT_SEARCH = "project.search"
    PROJECT_SEARCH_RESULT = "project.search.result"

    # 终端模式
    TERMINAL_START = "terminal.start"
    TERMINAL_OUTPUT = "terminal.output"
    TERMINAL_INPUT = "terminal.input"
    TERMINAL_RESIZE = "terminal.resize"
    TERMINAL_STOP = "terminal.stop"
    TERMINAL_STARTED = "terminal.started"

    # 插件管理
    PLUGIN_LIST = "plugin.list"
    PLUGIN_LIST_RESULT = "plugin.list.result"
    PLUGIN_ENABLE = "plugin.enable"
    PLUGIN_DISABLE = "plugin.disable"
    PLUGIN_UNINSTALL = "plugin.uninstall"
    PLUGIN_STATE_CHANGED = "plugin.state_changed"

    # 插件安装
    PLUGIN_INSTALL = "plugin.install"
    PLUGIN_INSTALL_RESULT = "plugin.install.result"

    # 插件配置
    PLUGIN_CONFIG_GET = "plugin.config.get"
    PLUGIN_CONFIG_GET_RESULT = "plugin.config.get.result"
    PLUGIN_CONFIG_SET = "plugin.config.set"
    PLUGIN_CONFIG_SET_RESULT = "plugin.config.set.result"


class Message(BaseModel):
    """WebSocket 消息基类"""

    id: str = Field(default_factory=lambda: str(uuid.uuid4())[:12])
    type: MessageType
    timestamp: int = Field(default_factory=lambda: int(time.time() * 1000))
    payload: dict[str, Any] = Field(default_factory=dict)


# ── 对话相关 payload ──


class ChatContext(BaseModel):
    """对话上下文，告诉 CLI 当前用户在看哪个文件"""

    active_file: Optional[str] = None
    selected_lines: Optional[list[int]] = None
    work_dir: Optional[str] = None


class ChatSendPayload(BaseModel):
    """用户发送对话消息"""

    cli: str  # 使用哪个 CLI adapter，如 "claude-code"
    message: str
    context: Optional[ChatContext] = None
    session_id: Optional[str] = None


class StreamChunkType(str, Enum):
    """Stream output chunk types."""

    TEXT = "text"
    CODE = "code"
    DIFF = "diff"
    THINKING = "thinking"
    TOOL_USE = "tool_use"
    TOOL_UPDATE = "tool_update"
    ERROR = "error"
    STATUS = "status"
    MODE_CHANGE = "mode_change"           # ACP current_mode_update
    CONFIG_UPDATE = "config_update"       # ACP config_option_update


class StreamChunk(BaseModel):
    """流式输出的单个块"""

    type: StreamChunkType
    content: str
    language: Optional[str] = None
    file_path: Optional[str] = None
    old_content: Optional[str] = None
    new_content: Optional[str] = None
    # 工具调用扩展字段
    kind: Optional[str] = None          # 工具类型 (edit, execute, read 等)
    tool_input: Optional[str] = None    # 工具输入 (命令、路径等)
    tool_id: Optional[str] = None       # 工具调用 ID（用于状态更新匹配）
    status: Optional[str] = None        # running / completed / failed
    locations: Optional[list[dict]] = None  # 涉及的文件位置 [{path, line?}]
    terminal_id: Optional[str] = None   # 嵌入终端 ID（Terminal 类型内容）
    content_blocks: Optional[list[dict]] = None  # ACP ToolCallContent blocks [{type, ...}]


class ChatStreamPayload(BaseModel):
    """流式回复"""

    chunk: StreamChunk
    session_id: Optional[str] = None


class ChatDonePayload(BaseModel):
    """回复完成"""

    tokens_used: Optional[int] = None
    duration_ms: Optional[int] = None
    session_id: Optional[str] = None


# ── 文件相关 payload ──


class FileTreePayload(BaseModel):
    """请求文件树"""

    path: str = "/"
    depth: int = 2


class FileNode(BaseModel):
    """文件树节点"""

    name: str
    type: str  # "file" | "dir"
    size: Optional[int] = None
    git_status: Optional[str] = None  # "modified" | "staged" | "untracked"
    children: Optional[list[FileNode]] = None


class FileReadPayload(BaseModel):
    """请求读取文件"""

    path: str


class FileReadResultPayload(BaseModel):
    """文件内容"""

    path: str
    content: Optional[str] = None
    language: Optional[str] = None
    line_count: int = 0
    error: Optional[str] = None


class FileWritePayload(BaseModel):
    """写入文件"""

    path: str
    content: str


class FileSearchPayload(BaseModel):
    """搜索文件"""

    query: str
    search_content: bool = False  # 是否搜索文件内容


# ── CLI 相关 payload ──


class CLIInfo(BaseModel):
    """CLI tool info with ACP capability declaration."""

    name: str
    display_name: str
    installed: bool
    version: Optional[str] = None
    install_hint: Optional[str] = None
    install_npm: Optional[str] = None
    is_custom: bool = False
    can_install: bool = False  # Whether this CLI can be installed/uninstalled via npm
    source: str = "builtin"  # "builtin" | "custom" | "plugin"

    # ACP AgentCapabilities — top level
    supports_session_load: bool = False

    # ACP promptCapabilities
    supports_image: bool = False
    supports_audio: bool = False
    supports_embedded_context: bool = False

    # ACP sessionCapabilities
    supports_session_list: bool = False
    supports_session_close: bool = False
    supports_session_fork: bool = False
    supports_session_resume: bool = False

    # ACP mcpCapabilities
    supports_mcp_http: bool = False
    supports_mcp_sse: bool = False

    # Available modes (populated after session creation)
    available_modes: list[dict] = []


# ── 认证相关 payload ──


class AuthPairPayload(BaseModel):
    """配对请求"""

    token: str
    device_name: Optional[str] = None


class AuthResultPayload(BaseModel):
    """认证结果"""

    success: bool
    session_token: Optional[str] = None
    error: Optional[str] = None
