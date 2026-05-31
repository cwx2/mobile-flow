"""Run Configuration domain payload models for the MobileFlow WebSocket protocol.

Covers configuration CRUD operations and execution lifecycle control
for the Run Configuration system.

Message types handled:
  - run_config.list           (RUN_CONFIG_LIST)           — list all configurations
  - run_config.list_result    (RUN_CONFIG_LIST_RESULT)    — configuration list response
  - run_config.create         (RUN_CONFIG_CREATE)         — create new configuration
  - run_config.created        (RUN_CONFIG_CREATED)        — newly created configuration
  - run_config.update         (RUN_CONFIG_UPDATE)         — update configuration fields
  - run_config.updated        (RUN_CONFIG_UPDATED)        — updated configuration
  - run_config.delete         (RUN_CONFIG_DELETE)         — delete a configuration
  - run_config.deleted        (RUN_CONFIG_DELETED)        — deletion confirmation
  - run_config.select         (RUN_CONFIG_SELECT)         — set selected configuration
  - run_config.changed        (RUN_CONFIG_CHANGED)        — broadcast config list change
  - run_config.start          (RUN_CONFIG_START)          — start execution
  - run_config.stop           (RUN_CONFIG_STOP)           — stop execution
  - run_config.restart        (RUN_CONFIG_RESTART)        — restart execution
  - run_config.output         (RUN_CONFIG_OUTPUT)         — process output stream
  - run_config.state_changed  (RUN_CONFIG_STATE_CHANGED)  — lifecycle state transition
  - run_config.status         (RUN_CONFIG_STATUS)         — get all running states
  - run_config.status_result  (RUN_CONFIG_STATUS_RESULT)  — running states map

Each model extends PayloadBase and is registered in PAYLOAD_REGISTRY
at import time so that ``Message.typed_payload()`` can automatically
deserialize incoming payloads into the correct model.
"""

from __future__ import annotations

from typing import Literal

from ..payload_registry import register_payload
from ..types import MessageType
from .base import PayloadBase


# ── Configuration CRUD ──


class RunConfigListPayload(PayloadBase):
    """Payload for ``run_config.list`` — request all configurations.

    Sent by the App to request the full configuration list from the Agent.
    No fields required.
    """

    pass


class RunConfigListResultPayload(PayloadBase):
    """Payload for ``run_config.list_result`` — full configuration list.

    Sent by the Agent in response to a list request. Contains all
    configurations in display order and the currently selected ID.

    Attributes:
        configurations: Serialized RunConfiguration objects as dicts.
        selected_id: ID of the currently selected configuration, or None.
    """

    configurations: list[dict]
    selected_id: str | None = None


class RunConfigCreatePayload(PayloadBase):
    """Payload for ``run_config.create`` — create a new configuration.

    Sent by the App to create a new configuration with type-specific
    template defaults. Optional initial field overrides can be provided.

    Attributes:
        type: Configuration type value (preview, script, test, custom).
        initial_fields: Optional dict of field overrides to apply on top
            of the template defaults.
    """

    type: str
    initial_fields: dict | None = None


class RunConfigCreatedPayload(PayloadBase):
    """Payload for ``run_config.created`` — newly created configuration.

    Sent by the Agent after successfully creating a configuration.

    Attributes:
        configuration: The full serialized RunConfiguration object.
    """

    configuration: dict


class RunConfigUpdatePayload(PayloadBase):
    """Payload for ``run_config.update`` — update configuration fields.

    Sent by the App to perform a partial update on an existing
    configuration. Only the specified fields are changed.

    Attributes:
        config_id: ID of the configuration to update.
        updates: Dict of field_name to new_value for partial update.
    """

    config_id: str
    updates: dict


class RunConfigUpdatedPayload(PayloadBase):
    """Payload for ``run_config.updated`` — full updated configuration.

    Sent by the Agent after successfully updating a configuration.

    Attributes:
        configuration: The full serialized RunConfiguration after update.
    """

    configuration: dict


class RunConfigDeletePayload(PayloadBase):
    """Payload for ``run_config.delete`` — delete a configuration.

    Sent by the App to request deletion of a configuration by ID.

    Attributes:
        config_id: ID of the configuration to delete.
    """

    config_id: str


class RunConfigDeletedPayload(PayloadBase):
    """Payload for ``run_config.deleted`` — deletion confirmation.

    Sent by the Agent after successfully deleting a configuration.

    Attributes:
        config_id: ID of the deleted configuration.
    """

    config_id: str


class RunConfigSelectPayload(PayloadBase):
    """Payload for ``run_config.select`` — set selected configuration.

    Sent by the App to change which configuration is highlighted/selected
    in the UI. Setting to None clears the selection.

    Attributes:
        config_id: ID of the configuration to select, or None to clear.
    """

    config_id: str | None = None


class RunConfigChangedPayload(PayloadBase):
    """Payload for ``run_config.changed`` — broadcast config list change.

    Sent by the Agent to ALL connected clients when the configuration
    list changes (create, update, delete, reorder, select). Ensures
    all clients stay in sync.

    Attributes:
        configurations: Full serialized configuration list in display order.
        selected_id: ID of the currently selected configuration, or None.
    """

    configurations: list[dict]
    selected_id: str | None = None


# ── Execution Control ──


class RunConfigStartPayload(PayloadBase):
    """Payload for ``run_config.start`` — start execution.

    Sent by the App to start executing a configuration. The Agent
    will stream output and state changes back via separate messages.

    Attributes:
        config_id: ID of the configuration to start.
    """

    config_id: str


class RunConfigStopPayload(PayloadBase):
    """Payload for ``run_config.stop`` — stop execution.

    Sent by the App to stop a running configuration. The Agent
    sends SIGTERM, then SIGKILL after timeout.

    Attributes:
        config_id: ID of the configuration to stop.
    """

    config_id: str


class RunConfigRestartPayload(PayloadBase):
    """Payload for ``run_config.restart`` — restart execution.

    Sent by the App to restart a configuration (stop then start).

    Attributes:
        config_id: ID of the configuration to restart.
    """

    config_id: str


class RunConfigOutputPayload(PayloadBase):
    """Payload for ``run_config.output`` — process output stream chunk.

    Sent by the Agent as stdout/stderr data becomes available from
    the running process or before-run tasks.

    Attributes:
        config_id: ID of the configuration producing output.
        stream: Which output stream produced this data ("stdout" or "stderr").
        data: The output text content.
        task_prefix: Optional prefix for before-run task output
            (e.g. "[Before 1/2]"). None for main command output.
    """

    config_id: str
    stream: Literal["stdout", "stderr"]
    data: str
    task_prefix: str | None = None


class RunConfigStateChangedPayload(PayloadBase):
    """Payload for ``run_config.state_changed`` — lifecycle state transition.

    Sent by the Agent when a configuration's execution state changes.
    Includes optional context depending on the new state.

    Attributes:
        config_id: ID of the configuration whose state changed.
        state: New RunConfigState value (idle, before_run, starting,
            running, stopping, stopped).
        exit_code: Process exit code when transitioning to stopped.
            None for non-terminal transitions.
        error_message: Human-readable error description when execution
            fails. None on success.
        preview_url: Preview URL when a preview config reaches running
            state. None for non-preview configs.
    """

    config_id: str
    state: str
    exit_code: int | None = None
    error_message: str | None = None
    preview_url: str | None = None


class RunConfigStatusPayload(PayloadBase):
    """Payload for ``run_config.status`` — request all running states.

    Sent by the App to query the current execution state of all
    configurations. Useful on reconnect to sync UI state.
    No fields required.
    """

    pass


class RunConfigStatusResultPayload(PayloadBase):
    """Payload for ``run_config.status_result`` — running states map.

    Sent by the Agent with the current state of all non-idle
    configurations.

    Attributes:
        states: Dict mapping config_id to RunConfigState value string.
            Only includes configurations that are not in idle state.
    """

    states: dict[str, str]


# ── Registry wiring ──

register_payload(MessageType.RUN_CONFIG_LIST, RunConfigListPayload)
register_payload(MessageType.RUN_CONFIG_LIST_RESULT, RunConfigListResultPayload)
register_payload(MessageType.RUN_CONFIG_CREATE, RunConfigCreatePayload)
register_payload(MessageType.RUN_CONFIG_CREATED, RunConfigCreatedPayload)
register_payload(MessageType.RUN_CONFIG_UPDATE, RunConfigUpdatePayload)
register_payload(MessageType.RUN_CONFIG_UPDATED, RunConfigUpdatedPayload)
register_payload(MessageType.RUN_CONFIG_DELETE, RunConfigDeletePayload)
register_payload(MessageType.RUN_CONFIG_DELETED, RunConfigDeletedPayload)
register_payload(MessageType.RUN_CONFIG_SELECT, RunConfigSelectPayload)
register_payload(MessageType.RUN_CONFIG_CHANGED, RunConfigChangedPayload)
register_payload(MessageType.RUN_CONFIG_START, RunConfigStartPayload)
register_payload(MessageType.RUN_CONFIG_STOP, RunConfigStopPayload)
register_payload(MessageType.RUN_CONFIG_RESTART, RunConfigRestartPayload)
register_payload(MessageType.RUN_CONFIG_OUTPUT, RunConfigOutputPayload)
register_payload(MessageType.RUN_CONFIG_STATE_CHANGED, RunConfigStateChangedPayload)
register_payload(MessageType.RUN_CONFIG_STATUS, RunConfigStatusPayload)
register_payload(MessageType.RUN_CONFIG_STATUS_RESULT, RunConfigStatusResultPayload)
