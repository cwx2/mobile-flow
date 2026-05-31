"""CLI domain payload models for the MobileFlow WebSocket protocol.

Defines typed Pydantic models for the eleven CLI management message types:
  - cli.list             (CLI_LIST)             — App requests adapter list
  - cli.list.result      (CLI_LIST_RESULT)      — Agent returns adapter list
  - cli.switch           (CLI_SWITCH)           — App switches active CLI
  - cli.status           (CLI_STATUS)           — Agent pushes CLI lifecycle state
  - cli.retry            (CLI_RETRY)            — App retries failed CLI init
  - cli.install          (CLI_INSTALL)          — App installs a CLI
  - cli.install.result   (CLI_INSTALL_RESULT)   — Agent returns install outcome
  - cli.install.progress (CLI_INSTALL_PROGRESS) — Agent pushes install progress
  - cli.uninstall        (CLI_UNINSTALL)        — App uninstalls a CLI
  - cli.uninstall.result (CLI_UNINSTALL_RESULT) — Agent returns uninstall outcome
  - cli.add              (CLI_ADD)              — App adds custom agent
  - cli.remove           (CLI_REMOVE)           — App removes custom agent

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Any, Optional

from ..models import CLIInfo
from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


# ── Request payloads (App -> Agent) ──


class CliListPayload(PayloadBase):
    """Payload for ``cli.list`` — request list of CLI adapters.

    The App sends this to discover all available CLI adapters.
    The ``cli`` field is optional and currently unused by the handler,
    but included for forward compatibility.

    Attributes:
        cli: Optional CLI name filter (reserved for future use).
    """

    cli: Optional[str] = None


class CliSwitchPayload(PayloadBase):
    """Payload for ``cli.switch`` — switch the active CLI adapter.

    Triggers shutdown of the old CLI's ACP provider and initialization
    of the new one.

    Attributes:
        cli: Target CLI adapter name to switch to.
    """

    cli: str = ""


class CliRetryPayload(PayloadBase):
    """Payload for ``cli.retry`` — retry failed CLI initialization.

    Sent when the user wants to re-attempt CLI setup after a failure.
    Falls back to the configured default CLI if ``cli`` is empty.

    Attributes:
        cli: CLI adapter name to retry (empty = use default).
    """

    cli: Optional[str] = None


class CliInstallPayload(PayloadBase):
    """Payload for ``cli.install`` — install a CLI adapter.

    Triggers npm-based installation of the CLI's packages with
    progress streaming back to the App.

    Attributes:
        cli: CLI adapter name to install.
    """

    cli: str = ""


class CliUninstallPayload(PayloadBase):
    """Payload for ``cli.uninstall`` — uninstall a CLI adapter.

    Stops any active sessions for the CLI before removing its
    npm packages.

    Attributes:
        cli: CLI adapter name to uninstall.
    """

    cli: str = ""


class CliAddPayload(PayloadBase):
    """Payload for ``cli.add`` — add a custom agent.

    Validates the command is accessible before registering the agent.
    For WSL paths, checks permissions and returns actionable errors.

    Attributes:
        name: Internal identifier for the custom agent.
        command: Executable command path or name.
        args: Command-line arguments for the agent.
        display_name: Human-readable name shown in the App UI.
    """

    name: str = ""
    command: str = ""
    args: list[str] = []
    display_name: Optional[str] = None


class CliRemovePayload(PayloadBase):
    """Payload for ``cli.remove`` — remove a custom agent.

    Unregisters the agent and refreshes the adapter list.

    Attributes:
        name: Internal identifier of the custom agent to remove.
    """

    name: str = ""


class CliCommandsPayload(PayloadBase):
    """Payload for ``cli.commands`` — CLI-advertised slash commands.

    Sent by the Agent when a CLI advertises available commands via ACP
    AvailableCommandsUpdate events. Uses replace semantics: each message
    replaces the previous command list for that CLI adapter.

    Attributes:
        cli: Source CLI adapter name.
        commands: List of command objects with name and description.
    """

    cli: str
    commands: list[dict[str, str]]


# ── Response / notification payloads (Agent -> App) ──


class CliListResultPayload(PayloadBase):
    """Payload for ``cli.list.result`` — adapter list response.

    Returns the full list of detected CLI adapters with their
    capabilities and installation status.

    Attributes:
        adapters: List of CLI adapter info dicts (serialized CLIInfo).
        default_cli: Currently configured default CLI adapter name.
        action_result: Optional result from a preceding add/remove action.
    """

    adapters: list[dict[str, Any]] = []
    default_cli: str = ""
    action_result: Optional[dict[str, Any]] = None


class CliStatusPayload(PayloadBase):
    """Payload for ``cli.status`` — CLI lifecycle state notification.

    Pushed by the Agent whenever a CLI adapter's state changes
    (e.g. checking_env → starting → ready, or → failed/auth_required).

    Attributes:
        cli: CLI adapter name.
        state: Lifecycle state (checking_env, starting, ready, failed, auth_required).
        message: User-facing status message (translated to client's locale).
        capabilities: ACP capability dict when state is "ready".
        error: Error detail string for debugging on failure.
        auth_methods: Available auth methods when state is "auth_required".
        auth_type: Authentication type identifier (e.g. "device_code").
        device_code_url: URL for device code authentication flow.
        device_code: Device code for the user to enter.
    """

    cli: str
    state: str
    message: str
    capabilities: Optional[dict[str, Any]] = None
    error: Optional[str] = None
    auth_methods: Optional[list[dict[str, Any]]] = None
    auth_type: Optional[str] = None
    device_code_url: Optional[str] = None
    device_code: Optional[str] = None


class CliInstallResultPayload(PayloadBase):
    """Payload for ``cli.install.result`` — install outcome.

    Returned after the install process completes (success or failure).

    Attributes:
        cli: CLI adapter name that was installed.
        success: Whether the installation succeeded.
        message: Human-readable result description.
    """

    cli: str = ""
    success: bool = False
    message: str = ""


class CliInstallProgressPayload(PayloadBase):
    """Payload for ``cli.install.progress`` — install/uninstall step progress.

    Streamed during install or uninstall to show per-package progress.
    Also used during uninstall operations (same message type).

    Attributes:
        cli: CLI adapter name being installed/uninstalled.
        step: Current step number (1-based).
        total_steps: Total number of packages to process.
        package: npm package name being processed.
        label: Human-readable label for the current package.
        status: Step status (installing, uninstalling).
    """

    cli: str = ""
    step: int = 0
    total_steps: int = 0
    package: str = ""
    label: str = ""
    status: str = ""


class CliUninstallResultPayload(PayloadBase):
    """Payload for ``cli.uninstall.result`` — uninstall outcome.

    Returned after the uninstall process completes.

    Attributes:
        cli: CLI adapter name that was uninstalled.
        success: Whether the uninstallation succeeded.
        message: Human-readable result description.
    """

    cli: str = ""
    success: bool = False
    message: str = ""


# ── Registry wiring ──
# Register all CLI payload models so Message.typed_payload() and
# get_payload_class() can resolve them by MessageType.

register_payload(MessageType.CLI_LIST, CliListPayload)
register_payload(MessageType.CLI_LIST_RESULT, CliListResultPayload)
register_payload(MessageType.CLI_SWITCH, CliSwitchPayload)
register_payload(MessageType.CLI_STATUS, CliStatusPayload)
register_payload(MessageType.CLI_RETRY, CliRetryPayload)
register_payload(MessageType.CLI_INSTALL, CliInstallPayload)
register_payload(MessageType.CLI_INSTALL_RESULT, CliInstallResultPayload)
register_payload(MessageType.CLI_INSTALL_PROGRESS, CliInstallProgressPayload)
register_payload(MessageType.CLI_UNINSTALL, CliUninstallPayload)
register_payload(MessageType.CLI_UNINSTALL_RESULT, CliUninstallResultPayload)
register_payload(MessageType.CLI_ADD, CliAddPayload)
register_payload(MessageType.CLI_REMOVE, CliRemovePayload)
register_payload(MessageType.CLI_COMMANDS, CliCommandsPayload)
