"""
Standard event name constants.

All event names used with EventBus are defined here to prevent typos
and provide a single source of truth. Each constant documents its
expected ``data`` dict shape and return value.
"""


class Events:
    """Event name constants for EventBus.

    Grouped by domain: permission, ACP lifecycle, session, project,
    agent status, file changes, terminal output.
    """

    # ── 权限 ──
    # data: {session_id, tool_name, tool_kind, description, options}
    # 返回: {outcome: {outcome: "selected"|"cancelled", optionId: "..."}}
    PERMISSION_REQUEST = "permission.request"

    # data: {request_id, approved, option_id}
    PERMISSION_RESPONSE = "permission.response"

    # ── ACP 生命周期 ──
    # data: {cli_name, session_id}
    ACP_CONNECTED = "acp.connected"
    ACP_DISCONNECTED = "acp.disconnected"
    ACP_SESSION_CREATED = "acp.session.created"

    # ── 会话 ──
    # data: {session_id, cli_name}
    SESSION_CREATED = "session.created"
    SESSION_SWITCHED = "session.switched"
    SESSION_CLOSED = "session.closed"

    # ── 项目 ──
    # data: {path, name}
    PROJECT_SWITCHED = "project.switched"
    PROJECT_ADDED = "project.added"
    PROJECT_REMOVED = "project.removed"

    # ── Agent 状态 ──
    # data: {status: "thinking"|"tool_running"|"streaming"|"idle", detail: "..."}
    AGENT_STATUS_CHANGED = "agent.status.changed"

    # ── 文件变化 ──
    # data: {path, change: "created"|"modified"|"deleted"}
    FILE_CHANGED = "file.changed"

    # ── 终端输出 ──
    # data: {terminal_id, text}
    TERMINAL_OUTPUT = "terminal.output"

    # ── CLI Commands ──
    # data: {cli_name, commands: [{name, description}, ...]}
    CLI_COMMANDS_AVAILABLE = "cli.commands_available"
