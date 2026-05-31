"""Typed payload models for the MobileFlow WebSocket protocol.

This package contains Pydantic models for every message type's payload,
organized into domain-specific submodules (auth, chat, cli, file, etc.).
Each model inherits from :class:`PayloadBase` and provides validated
serialization / deserialization via ``to_payload_dict()`` and
``from_payload_dict()``.

As domain modules are added during the P0–P5 migration, this barrel
module re-exports all payload classes so consumers can import from a
single path::

    from mobileflow_protocol.payloads import PayloadBase
    from mobileflow_protocol.payloads import AuthPairPayload  # P0
    from mobileflow_protocol.payloads import CliStatusPayload  # P0
"""

from .base import PayloadBase

# P0: Auth domain
from .auth import (
    AuthConnectPayload,
    AuthPairPayload,
    AuthResultPayload,
    AuthSubmitPayload,
)

# P0: CLI domain
from .cli import (
    CliAddPayload,
    CliCommandsPayload,
    CliInstallPayload,
    CliInstallProgressPayload,
    CliInstallResultPayload,
    CliListPayload,
    CliListResultPayload,
    CliRemovePayload,
    CliRetryPayload,
    CliStatusPayload,
    CliSwitchPayload,
    CliUninstallPayload,
    CliUninstallResultPayload,
)

# P1: Chat domain
from .chat import (
    ChatCancelPayload,
    ChatDonePayload,
    ChatErrorPayload,
    ChatHistoryMorePayload,
    ChatHistoryMoreResultPayload,
    ChatHistoryPayload,
    ChatHistoryResultPayload,
    ChatReplayPayload,
    ChatReplayResultPayload,
    ChatSendPayload,
    ChatStreamPayload,
)

# P1: Session domain
from .session import (
    SessionClosePayload,
    SessionListPayload,
    SessionListResultPayload,
    SessionNewPayload,
    SessionSwitchPayload,
)

# P1: Permission domain
from .permission import (
    PermissionPolicyPayload,
    PermissionRequestPayload,
    PermissionResponsePayload,
)

# P2: File domain
from .file import (
    FileChangedPayload,
    FileCreatePayload,
    FileCreateResultPayload,
    FileDeletePayload,
    FileDeleteResultPayload,
    FileReadPayload,
    FileReadResultPayload,
    FileRenamePayload,
    FileRenameResultPayload,
    FileSearchPayload,
    FileSearchResultPayload,
    FileSearchStreamPayload,
    FileTreePayload,
    FileTreeResultPayload,
    FileWritePayload,
    FileWriteResultPayload,
)

# P2: Diff domain
from .diff import (
    DiffApplyPayload,
    DiffPreviewPayload,
    DiffRejectPayload,
)

# P4: Terminal domain
from .terminal import (
    TerminalInputPayload,
    TerminalOutputPayload,
    TerminalResizePayload,
    TerminalStartedPayload,
    TerminalStartPayload,
    TerminalStopPayload,
)

# P4: Project domain
from .project import (
    ProjectAddPayload,
    ProjectCurrentPayload,
    ProjectListPayload,
    ProjectListResultPayload,
    ProjectRemovePayload,
    ProjectSearchPayload,
    ProjectSearchResultPayload,
    ProjectSwitchPayload,
)

# P4: Plugin domain
from .plugin import (
    PluginConfigGetPayload,
    PluginConfigGetResultPayload,
    PluginConfigSetPayload,
    PluginConfigSetResultPayload,
    PluginDisablePayload,
    PluginEnablePayload,
    PluginInstallPayload,
    PluginInstallResultPayload,
    PluginListPayload,
    PluginListResultPayload,
    PluginStateChangedPayload,
    PluginUninstallPayload,
)

# P5: State / Heartbeat / Confirm / Config domain
from .state import (
    ConfigSetPayload,
    ConfirmRequestPayload,
    ConfirmResponsePayload,
    ModeSetPayload,
    StatePushPayload,
    StatusPingPayload,
    StatusPongPayload,
)

# Test Panel domain (script, api, preview, screenshot, visual diff)
from .test_panel import (
    ApiErrorPayload,
    ApiRequestPayload,
    ApiResponsePayload,
    PreviewDetectPayload,
    PreviewDetectResultPayload,
    PreviewFileChangedPayload,
    PreviewOutputPayload,
    PreviewReadyPayload,
    PreviewStartPayload,
    PreviewStopPayload,
    PreviewStoppedPayload,
    ScreenshotCapturePayload,
    ScreenshotErrorPayload,
    ScreenshotResultPayload,
    ScriptDonePayload,
    ScriptOutputPayload,
    ScriptRunPayload,
    ScriptStopPayload,
    VisualDiffComparePayload,
    VisualDiffResultPayload,
    VisualDiffStartPayload,
)

# Run Configuration domain (CRUD + execution lifecycle)
from .run_config import (
    RunConfigChangedPayload,
    RunConfigCreatePayload,
    RunConfigCreatedPayload,
    RunConfigDeletePayload,
    RunConfigDeletedPayload,
    RunConfigListPayload,
    RunConfigListResultPayload,
    RunConfigOutputPayload,
    RunConfigRestartPayload,
    RunConfigSelectPayload,
    RunConfigStartPayload,
    RunConfigStateChangedPayload,
    RunConfigStatusPayload,
    RunConfigStatusResultPayload,
    RunConfigStopPayload,
    RunConfigUpdatePayload,
    RunConfigUpdatedPayload,
)

# P3: Git domain
from .git import (
    GitBranchesPayload,
    GitBranchesResultPayload,
    GitCheckoutPayload,
    GitCheckoutResultPayload,
    GitCommitPayload,
    GitCommitResultPayload,
    GitDiffCommitPayload,
    GitDiffCommitResultPayload,
    GitDiffPayload,
    GitDiffResultPayload,
    GitDiscardPayload,
    GitDiscardResultPayload,
    GitExecPayload,
    GitExecResultPayload,
    GitLogAuthorsPayload,
    GitLogAuthorsResultPayload,
    GitLogPayload,
    GitLogResultPayload,
    GitLogSearchPayload,
    GitLogSearchResultPayload,
    GitPullPayload,
    GitPullResultPayload,
    GitPushPayload,
    GitPushResultPayload,
    GitReposPayload,
    GitReposResultPayload,
    GitShowPayload,
    GitShowResultPayload,
    GitStagePayload,
    GitStageResultPayload,
    GitStatusPayload,
    GitStatusResultPayload,
    GitSwitchRepoPayload,
    GitUnstagePayload,
    GitUnstageResultPayload,
)

__all__ = [
    "PayloadBase",
    # Auth (P0)
    "AuthConnectPayload",
    "AuthPairPayload",
    "AuthResultPayload",
    "AuthSubmitPayload",
    # CLI (P0)
    "CliAddPayload",
    "CliCommandsPayload",
    "CliInstallPayload",
    "CliInstallProgressPayload",
    "CliInstallResultPayload",
    "CliListPayload",
    "CliListResultPayload",
    "CliRemovePayload",
    "CliRetryPayload",
    "CliStatusPayload",
    "CliSwitchPayload",
    "CliUninstallPayload",
    "CliUninstallResultPayload",
    # Chat (P1)
    "ChatCancelPayload",
    "ChatDonePayload",
    "ChatErrorPayload",
    "ChatHistoryMorePayload",
    "ChatHistoryMoreResultPayload",
    "ChatHistoryPayload",
    "ChatHistoryResultPayload",
    "ChatReplayPayload",
    "ChatReplayResultPayload",
    "ChatSendPayload",
    "ChatStreamPayload",
    # Session (P1)
    "SessionClosePayload",
    "SessionListPayload",
    "SessionListResultPayload",
    "SessionNewPayload",
    "SessionSwitchPayload",
    # Permission (P1)
    "PermissionPolicyPayload",
    "PermissionRequestPayload",
    "PermissionResponsePayload",
    # File (P2)
    "FileChangedPayload",
    "FileCreatePayload",
    "FileCreateResultPayload",
    "FileDeletePayload",
    "FileDeleteResultPayload",
    "FileReadPayload",
    "FileReadResultPayload",
    "FileRenamePayload",
    "FileRenameResultPayload",
    "FileSearchPayload",
    "FileSearchResultPayload",
    "FileSearchStreamPayload",
    "FileTreePayload",
    "FileTreeResultPayload",
    "FileWritePayload",
    "FileWriteResultPayload",
    # Diff (P2)
    "DiffApplyPayload",
    "DiffPreviewPayload",
    "DiffRejectPayload",
    # Git (P3)
    "GitBranchesPayload",
    "GitBranchesResultPayload",
    "GitCheckoutPayload",
    "GitCheckoutResultPayload",
    "GitCommitPayload",
    "GitCommitResultPayload",
    "GitDiffCommitPayload",
    "GitDiffCommitResultPayload",
    "GitDiffPayload",
    "GitDiffResultPayload",
    "GitDiscardPayload",
    "GitDiscardResultPayload",
    "GitExecPayload",
    "GitExecResultPayload",
    "GitLogAuthorsPayload",
    "GitLogAuthorsResultPayload",
    "GitLogPayload",
    "GitLogResultPayload",
    "GitLogSearchPayload",
    "GitLogSearchResultPayload",
    "GitPullPayload",
    "GitPullResultPayload",
    "GitPushPayload",
    "GitPushResultPayload",
    "GitReposPayload",
    "GitReposResultPayload",
    "GitShowPayload",
    "GitShowResultPayload",
    "GitStagePayload",
    "GitStageResultPayload",
    "GitStatusPayload",
    "GitStatusResultPayload",
    "GitSwitchRepoPayload",
    "GitUnstagePayload",
    "GitUnstageResultPayload",
    # Terminal (P4)
    "TerminalInputPayload",
    "TerminalOutputPayload",
    "TerminalResizePayload",
    "TerminalStartedPayload",
    "TerminalStartPayload",
    "TerminalStopPayload",
    # Project (P4)
    "ProjectAddPayload",
    "ProjectCurrentPayload",
    "ProjectListPayload",
    "ProjectListResultPayload",
    "ProjectRemovePayload",
    "ProjectSearchPayload",
    "ProjectSearchResultPayload",
    "ProjectSwitchPayload",
    # Plugin (P4)
    "PluginConfigGetPayload",
    "PluginConfigGetResultPayload",
    "PluginConfigSetPayload",
    "PluginConfigSetResultPayload",
    "PluginDisablePayload",
    "PluginEnablePayload",
    "PluginInstallPayload",
    "PluginInstallResultPayload",
    "PluginListPayload",
    "PluginListResultPayload",
    "PluginStateChangedPayload",
    "PluginUninstallPayload",
    # State / Heartbeat / Confirm / Config (P5)
    "ConfigSetPayload",
    "ConfirmRequestPayload",
    "ConfirmResponsePayload",
    "ModeSetPayload",
    "StatePushPayload",
    "StatusPingPayload",
    "StatusPongPayload",
    # Test Panel (script, api, preview, screenshot, visual diff)
    "ApiErrorPayload",
    "ApiRequestPayload",
    "ApiResponsePayload",
    "PreviewDetectPayload",
    "PreviewDetectResultPayload",
    "PreviewFileChangedPayload",
    "PreviewOutputPayload",
    "PreviewReadyPayload",
    "PreviewStartPayload",
    "PreviewStopPayload",
    "PreviewStoppedPayload",
    "ScreenshotCapturePayload",
    "ScreenshotErrorPayload",
    "ScreenshotResultPayload",
    "ScriptDonePayload",
    "ScriptOutputPayload",
    "ScriptRunPayload",
    "ScriptStopPayload",
    "VisualDiffComparePayload",
    "VisualDiffResultPayload",
    "VisualDiffStartPayload",
    # Run Configuration (CRUD + execution lifecycle)
    "RunConfigChangedPayload",
    "RunConfigCreatePayload",
    "RunConfigCreatedPayload",
    "RunConfigDeletePayload",
    "RunConfigDeletedPayload",
    "RunConfigListPayload",
    "RunConfigListResultPayload",
    "RunConfigOutputPayload",
    "RunConfigRestartPayload",
    "RunConfigSelectPayload",
    "RunConfigStartPayload",
    "RunConfigStateChangedPayload",
    "RunConfigStatusPayload",
    "RunConfigStatusResultPayload",
    "RunConfigStopPayload",
    "RunConfigUpdatePayload",
    "RunConfigUpdatedPayload",
]
