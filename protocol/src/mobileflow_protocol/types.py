"""Message type enumeration for App-Agent WebSocket communication.

Every WebSocket message carries a ``type`` field from this enum.
Types are organized by functional domain and annotated with their
communication direction.

Naming conventions (following LSP / ACP patterns):
  - Request + Response pairs: ``domain.action`` / ``domain.action.result``
  - One-way notifications:    ``domain.event``
  - Progress streams:         ``domain.action.progress``

Direction legend used in comments:
  - App -> Agent:  mobile client sends to desktop server
  - Agent -> App:  desktop server pushes to mobile client
"""

from enum import Enum


class MessageType(str, Enum):
    """WebSocket message types for MobileFlow App-Agent protocol."""

    # ── Authentication ──
    # Pairing and session management between App and Agent.

    AUTH_PAIR = "auth.pair"                # App -> Agent: initial 6-digit pairing
    AUTH_CONNECT = "auth.connect"          # App -> Agent: reconnect with session token
    AUTH_RESULT = "auth.result"            # Agent -> App: auth outcome (success/failure)
    AUTH_SUBMIT = "auth.submit"            # App -> Agent: submit CLI auth credentials

    # ── Chat ──
    # User messaging, AI streaming, and conversation history.

    CHAT_SEND = "chat.send"               # App -> Agent: user message to AI
    CHAT_STREAM = "chat.stream"           # Agent -> App: streaming response chunk
    CHAT_DONE = "chat.done"               # Agent -> App: AI turn complete
    CHAT_ERROR = "chat.error"             # Agent -> App: prompt-level error
    CHAT_CANCEL = "chat.cancel"           # App -> Agent: cancel current AI operation
    CHAT_HISTORY = "chat.history"         # App -> Agent: request conversation history
    CHAT_HISTORY_RESULT = "chat.history.result"        # Agent -> App: history page
    CHAT_HISTORY_MORE = "chat.history.more"            # App -> Agent: request next page
    CHAT_HISTORY_MORE_RESULT = "chat.history.more.result"  # Agent -> App: next page
    CHAT_REPLAY = "chat.replay"           # App -> Agent: request buffered chunks after reconnect
    CHAT_REPLAY_RESULT = "chat.replay.result"  # Agent -> App: replayed chunks batch

    # ── Session ──
    # ACP session lifecycle (list, create, switch, close).

    SESSION_LIST = "session.list"         # App -> Agent: list available sessions
    SESSION_LIST_RESULT = "session.list.result"  # Agent -> App: session list
    SESSION_NEW = "session.new"           # App -> Agent: create new session
    SESSION_SWITCH = "session.switch"     # App -> Agent: switch to existing session
    SESSION_CLOSE = "session.close"       # App -> Agent: close a session

    # ── ACP Configuration ──
    # Mode switching and config option updates (model, thinking, etc.).

    MODE_SET = "mode.set"                 # App -> Agent: switch session mode
    CONFIG_SET = "config.set"             # App -> Agent: set config option value

    # ── File Operations ──
    # File tree browsing, read/write, search, create, rename, delete.

    FILE_TREE = "file.tree"               # App -> Agent: request directory tree
    FILE_TREE_RESULT = "file.tree.result"  # Agent -> App: directory tree data
    FILE_READ = "file.read"               # App -> Agent: read file content
    FILE_READ_RESULT = "file.read.result"  # Agent -> App: file content
    FILE_WRITE = "file.write"             # App -> Agent: write file content
    FILE_WRITE_RESULT = "file.write.result"  # Agent -> App: write result
    FILE_SEARCH = "file.search"           # App -> Agent: search files/content
    FILE_SEARCH_RESULT = "file.search.result"  # Agent -> App: search results (final)
    FILE_SEARCH_STREAM = "file.search.stream"  # Agent -> App: search results (streaming)
    FILE_CREATE = "file.create"           # App -> Agent: create file or directory
    FILE_CREATE_RESULT = "file.create.result"  # Agent -> App: create result
    FILE_RENAME = "file.rename"           # App -> Agent: rename file or directory
    FILE_RENAME_RESULT = "file.rename.result"  # Agent -> App: rename result
    FILE_DELETE = "file.delete"           # App -> Agent: delete file or directory
    FILE_DELETE_RESULT = "file.delete.result"  # Agent -> App: delete result
    FILE_CHANGED = "file.changed"         # Agent -> App: file system change notification

    # ── Diff Operations ──
    # Accept or reject AI-proposed file changes.

    DIFF_PREVIEW = "diff.preview"         # Agent -> App: proposed diff for review
    DIFF_APPLY = "diff.apply"             # App -> Agent: accept proposed diff
    DIFF_REJECT = "diff.reject"           # App -> Agent: reject proposed diff

    # ── Git Operations ──
    # Repository status, staging, commits, branches, history.

    GIT_STATUS = "git.status"             # App -> Agent: request repo status
    GIT_STATUS_RESULT = "git.status.result"  # Agent -> App: repo status
    GIT_DIFF = "git.diff"                 # App -> Agent: request file diff
    GIT_DIFF_RESULT = "git.diff.result"   # Agent -> App: diff content
    GIT_STAGE = "git.stage"               # App -> Agent: stage files
    GIT_STAGE_RESULT = "git.stage.result"  # Agent -> App: stage result
    GIT_UNSTAGE = "git.unstage"           # App -> Agent: unstage files
    GIT_UNSTAGE_RESULT = "git.unstage.result"  # Agent -> App: unstage result
    GIT_COMMIT = "git.commit"             # App -> Agent: create commit
    GIT_COMMIT_RESULT = "git.commit.result"  # Agent -> App: commit result
    GIT_PUSH = "git.push"                 # App -> Agent: push to remote
    GIT_PUSH_RESULT = "git.push.result"   # Agent -> App: push result
    GIT_PULL = "git.pull"                 # App -> Agent: pull from remote
    GIT_PULL_RESULT = "git.pull.result"   # Agent -> App: pull result
    GIT_BRANCHES = "git.branches"         # App -> Agent: list branches
    GIT_BRANCHES_RESULT = "git.branches.result"  # Agent -> App: branch list
    GIT_CHECKOUT = "git.checkout"         # App -> Agent: switch branch
    GIT_CHECKOUT_RESULT = "git.checkout.result"  # Agent -> App: checkout result
    GIT_LOG = "git.log"                   # App -> Agent: request commit log
    GIT_LOG_RESULT = "git.log.result"     # Agent -> App: commit log
    GIT_LOG_SEARCH = "git.log.search"     # App -> Agent: search commit log
    GIT_LOG_SEARCH_RESULT = "git.log.search.result"  # Agent -> App: search results
    GIT_LOG_AUTHORS = "git.log.authors"   # App -> Agent: list commit authors
    GIT_LOG_AUTHORS_RESULT = "git.log.authors.result"  # Agent -> App: author list
    GIT_SHOW = "git.show"                 # App -> Agent: show commit details
    GIT_SHOW_RESULT = "git.show.result"   # Agent -> App: commit details
    GIT_DIFF_COMMIT = "git.diff.commit"   # App -> Agent: diff a specific commit file
    GIT_DIFF_COMMIT_RESULT = "git.diff.commit.result"  # Agent -> App: commit file diff
    GIT_DISCARD = "git.discard"           # App -> Agent: discard file changes
    GIT_DISCARD_RESULT = "git.discard.result"  # Agent -> App: discard result
    GIT_REPOS = "git.repos"              # App -> Agent: discover git repositories
    GIT_REPOS_RESULT = "git.repos.result"  # Agent -> App: repository list
    GIT_SWITCH_REPO = "git.switch_repo"   # App -> Agent: switch active repository
    GIT_EXEC = "git.exec"                # App -> Agent: execute arbitrary git command
    GIT_EXEC_RESULT = "git.exec.result"   # Agent -> App: execution result

    # ── Terminal ──
    # Interactive PTY terminal sessions.

    TERMINAL_START = "terminal.start"     # App -> Agent: start terminal session
    TERMINAL_STARTED = "terminal.started"  # Agent -> App: terminal session ready
    TERMINAL_INPUT = "terminal.input"     # App -> Agent: user keyboard input
    TERMINAL_OUTPUT = "terminal.output"   # Agent -> App: terminal output (base64)
    TERMINAL_RESIZE = "terminal.resize"   # App -> Agent: resize terminal dimensions
    TERMINAL_STOP = "terminal.stop"       # App -> Agent: stop terminal session

    # ── CLI Management ──
    # AI CLI adapter listing, switching, install/uninstall, lifecycle.

    CLI_LIST = "cli.list"                 # App -> Agent: list all CLI adapters
    CLI_LIST_RESULT = "cli.list.result"   # Agent -> App: adapter list with capabilities
    CLI_SWITCH = "cli.switch"             # App -> Agent: switch active CLI
    CLI_STATUS = "cli.status"             # Agent -> App: CLI lifecycle state push
    CLI_RETRY = "cli.retry"              # App -> Agent: retry failed CLI initialization
    CLI_INSTALL = "cli.install"           # App -> Agent: install a CLI
    CLI_INSTALL_RESULT = "cli.install.result"  # Agent -> App: install outcome
    CLI_INSTALL_PROGRESS = "cli.install.progress"  # Agent -> App: install step progress
    CLI_UNINSTALL = "cli.uninstall"       # App -> Agent: uninstall a CLI
    CLI_UNINSTALL_RESULT = "cli.uninstall.result"  # Agent -> App: uninstall outcome
    CLI_COMMANDS = "cli.commands"           # Agent -> App: CLI-advertised slash commands
    CLI_ADD = "cli.add"                   # App -> Agent: add custom agent
    CLI_REMOVE = "cli.remove"             # App -> Agent: remove custom agent

    # ── Permissions ──
    # ACP tool permission request/response flow.

    PERMISSION_REQUEST = "permission.request"    # Agent -> App: request tool permission
    PERMISSION_RESPONSE = "permission.response"  # App -> Agent: user permission decision
    PERMISSION_POLICY = "permission.policy"      # Agent -> App: permission policy update

    # ── Confirm (legacy) ──
    # Dangerous operation confirmation (predates ACP permissions).

    CONFIRM_REQUEST = "confirm.request"   # Agent -> App: confirm dangerous operation
    CONFIRM_RESPONSE = "confirm.response"  # App -> Agent: user confirmation

    # ── Project Management ──
    # Working directory and project list management.

    PROJECT_LIST = "project.list"         # App -> Agent: list registered projects
    PROJECT_LIST_RESULT = "project.list.result"  # Agent -> App: project list
    PROJECT_ADD = "project.add"           # App -> Agent: add project directory
    PROJECT_REMOVE = "project.remove"     # App -> Agent: remove project
    PROJECT_SWITCH = "project.switch"     # App -> Agent: switch active project
    PROJECT_CURRENT = "project.current"   # Agent -> App: current project info
    PROJECT_SEARCH = "project.search"     # App -> Agent: search/browse for projects
    PROJECT_SEARCH_RESULT = "project.search.result"  # Agent -> App: search results

    # ── Plugin Management ──
    # Extension plugin lifecycle and configuration.

    PLUGIN_LIST = "plugin.list"           # App -> Agent: list installed plugins
    PLUGIN_LIST_RESULT = "plugin.list.result"  # Agent -> App: plugin list
    PLUGIN_ENABLE = "plugin.enable"       # App -> Agent: enable a plugin
    PLUGIN_DISABLE = "plugin.disable"     # App -> Agent: disable a plugin
    PLUGIN_UNINSTALL = "plugin.uninstall"  # App -> Agent: uninstall a plugin
    PLUGIN_STATE_CHANGED = "plugin.state_changed"  # Agent -> App: plugin state change
    PLUGIN_INSTALL = "plugin.install"     # App -> Agent: install a plugin
    PLUGIN_INSTALL_RESULT = "plugin.install.result"  # Agent -> App: install outcome
    PLUGIN_CONFIG_GET = "plugin.config.get"  # App -> Agent: get plugin config
    PLUGIN_CONFIG_GET_RESULT = "plugin.config.get.result"  # Agent -> App: plugin config
    PLUGIN_CONFIG_SET = "plugin.config.set"  # App -> Agent: set plugin config
    PLUGIN_CONFIG_SET_RESULT = "plugin.config.set.result"  # Agent -> App: set result

    # ── Heartbeat ──
    # Connection liveness check.

    STATUS_PING = "status.ping"           # App -> Agent: ping
    STATUS_PONG = "status.pong"           # Agent -> App: pong

    # ── State Push ──
    # Cache layer auto-refresh notifications.

    STATE_PUSH = "state.push"             # Agent -> App: cached state update

    # ── Script Execution ──
    # Run arbitrary commands from the App, stream output back.

    SCRIPT_RUN = "script.run"             # App -> Agent: execute a command
    SCRIPT_OUTPUT = "script.output"       # Agent -> App: stdout/stderr stream chunk
    SCRIPT_DONE = "script.done"           # Agent -> App: command completed
    SCRIPT_STOP = "script.stop"           # App -> Agent: stop running command

    # ── API Proxy ──
    # Forward HTTP requests from App through Agent to any target.

    API_REQUEST = "api.request"           # App -> Agent: execute HTTP request
    API_RESPONSE = "api.response"         # Agent -> App: HTTP response
    API_ERROR = "api.error"               # Agent -> App: request error

    # ── Preview ──
    # Dev server management and port proxy for web preview.

    PREVIEW_START = "preview.start"       # App -> Agent: start dev server + proxy
    PREVIEW_READY = "preview.ready"       # Agent -> App: preview URL available
    PREVIEW_OUTPUT = "preview.output"     # Agent -> App: dev server stdout/stderr
    PREVIEW_STOP = "preview.stop"         # App -> Agent: stop dev server + proxy
    PREVIEW_STOPPED = "preview.stopped"   # Agent -> App: dev server terminated
    PREVIEW_FILE_CHANGED = "preview.file_changed"  # Agent -> App: file change during preview
    PREVIEW_DETECT = "preview.detect"     # App -> Agent: detect project type (plugin)
    PREVIEW_DETECT_RESULT = "preview.detect.result"  # Agent -> App: detection result

    # ── Screenshot ──
    # Headless browser screenshot capture (optional Playwright).

    SCREENSHOT_CAPTURE = "screenshot.capture"      # App -> Agent: capture screenshot
    SCREENSHOT_RESULT = "screenshot.result"        # Agent -> App: screenshot image
    SCREENSHOT_ERROR = "screenshot.error"          # Agent -> App: capture error

    # ── Visual Diff ──
    # Before/after screenshot comparison.

    VISUAL_DIFF_START = "visual_diff.start"        # App -> Agent: capture "before" baseline
    VISUAL_DIFF_COMPARE = "visual_diff.compare"    # App -> Agent: capture "after" and diff
    VISUAL_DIFF_RESULT = "visual_diff.result"      # Agent -> App: diff result with images

    # ── Plugin Queries ──
    # Smart suggestions from installed plugins.

    RUNTIME_RESOLVE = "runtime.resolve"            # App -> Agent: resolve file → command mapping
    RUNTIME_RESOLVE_RESULT = "runtime.resolve.result"  # Agent -> App: resolved command

    # ── Run Configuration ──
    # Configuration-driven run system (replaces ad-hoc Web Preview).

    RUN_CONFIG_LIST = "run_config.list"                    # App -> Agent: list all configurations
    RUN_CONFIG_LIST_RESULT = "run_config.list_result"      # Agent -> App: configuration list
    RUN_CONFIG_CREATE = "run_config.create"                # App -> Agent: create new configuration
    RUN_CONFIG_CREATED = "run_config.created"              # Agent -> App: newly created config
    RUN_CONFIG_UPDATE = "run_config.update"                # App -> Agent: update configuration fields
    RUN_CONFIG_UPDATED = "run_config.updated"              # Agent -> App: updated configuration
    RUN_CONFIG_DELETE = "run_config.delete"                # App -> Agent: delete a configuration
    RUN_CONFIG_DELETED = "run_config.deleted"              # Agent -> App: deletion confirmation
    RUN_CONFIG_SELECT = "run_config.select"                # App -> Agent: set selected configuration
    RUN_CONFIG_CHANGED = "run_config.changed"              # Agent -> All: broadcast config list change
    RUN_CONFIG_START = "run_config.start"                  # App -> Agent: start execution
    RUN_CONFIG_STOP = "run_config.stop"                    # App -> Agent: stop execution
    RUN_CONFIG_RESTART = "run_config.restart"              # App -> Agent: restart execution
    RUN_CONFIG_OUTPUT = "run_config.output"                # Agent -> App: process output stream
    RUN_CONFIG_STATE_CHANGED = "run_config.state_changed"  # Agent -> App: lifecycle state transition
    RUN_CONFIG_STATUS = "run_config.status"                # App -> Agent: get all running states
    RUN_CONFIG_STATUS_RESULT = "run_config.status_result"  # Agent -> App: running states map


# ── Message pattern classification ──
#
# Every message falls into one of three patterns (following LSP / ACP):
#
#   REQUEST:      App sends, expects a paired .result response.
#   NOTIFICATION: One-way push from Agent to App, no response expected.
#   COMMAND:      App sends, Agent acts but no .result is returned.
#
# This classification helps handlers, middleware, and documentation
# understand the expected behavior of each message type.


class MessagePattern:
    """Message exchange pattern constants."""

    REQUEST = "request"          # Paired request-response (xxx + xxx.result)
    NOTIFICATION = "notification"  # One-way push (Agent -> App)
    COMMAND = "command"          # One-way action (App -> Agent, no result)


# Registry mapping each MessageType to its exchange pattern.
# Types not listed here default to REQUEST (the most common pattern).
_NOTIFICATIONS: frozenset[MessageType] = frozenset({
    # Agent -> App: lifecycle and status pushes
    MessageType.CLI_STATUS,
    MessageType.CLI_COMMANDS,
    MessageType.CLI_INSTALL_PROGRESS,
    MessageType.FILE_CHANGED,
    MessageType.STATE_PUSH,
    MessageType.PLUGIN_STATE_CHANGED,
    MessageType.PROJECT_CURRENT,
    MessageType.TERMINAL_STARTED,
    MessageType.TERMINAL_OUTPUT,
    # Agent -> App: chat streaming (triggered by chat.send, but each chunk is a push)
    MessageType.CHAT_STREAM,
    MessageType.CHAT_DONE,
    MessageType.CHAT_ERROR,
    # Agent -> App: permission prompt (Agent initiates, App responds separately)
    MessageType.PERMISSION_REQUEST,
    MessageType.PERMISSION_POLICY,
    MessageType.DIFF_PREVIEW,
})

_COMMANDS: frozenset[MessageType] = frozenset({
    # App -> Agent: fire-and-forget actions (no .result response)
    MessageType.CHAT_CANCEL,
    MessageType.CLI_SWITCH,
    MessageType.CLI_RETRY,
    MessageType.CLI_REMOVE,
    MessageType.MODE_SET,
    MessageType.CONFIG_SET,
    MessageType.AUTH_SUBMIT,
    MessageType.TERMINAL_INPUT,
    MessageType.TERMINAL_RESIZE,
    MessageType.TERMINAL_STOP,
    MessageType.DIFF_APPLY,
    MessageType.DIFF_REJECT,
    MessageType.CONFIRM_RESPONSE,
    MessageType.PERMISSION_RESPONSE,
    MessageType.PERMISSION_POLICY,
    MessageType.PROJECT_REMOVE,
    MessageType.PROJECT_SWITCH,
    MessageType.PLUGIN_ENABLE,
    MessageType.PLUGIN_DISABLE,
    MessageType.PLUGIN_UNINSTALL,
    MessageType.STATUS_PING,
    MessageType.STATUS_PONG,
})


def get_message_pattern(msg_type: MessageType) -> str:
    """Return the exchange pattern for a message type.

    Args:
        msg_type: The message type to classify.

    Returns:
        One of MessagePattern.REQUEST, NOTIFICATION, or COMMAND.
    """
    if msg_type in _NOTIFICATIONS:
        return MessagePattern.NOTIFICATION
    if msg_type in _COMMANDS:
        return MessagePattern.COMMAND
    return MessagePattern.REQUEST
