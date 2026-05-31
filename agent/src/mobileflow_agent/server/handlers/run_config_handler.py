"""Run Configuration handler for all run_config.* protocol messages.

Module: server/handlers/
Responsibility:
    Route run_config.* messages to RunConfigurationStore (CRUD) and
    RunConfigurationExecutor (lifecycle). Broadcasts configuration
    changes to all connected clients. Streams process output and
    state transitions back to the requesting client.

Supported message types:
    - run_config.list       — list all configurations
    - run_config.create     — create new configuration
    - run_config.update     — update configuration fields
    - run_config.delete     — delete a configuration
    - run_config.select     — set selected configuration
    - run_config.start      — start execution
    - run_config.stop       — stop execution
    - run_config.restart    — restart execution
    - run_config.status     — get all running states

Called by:
    WebSocketServer message router.

Design decisions:
    - Running configurations persist across client disconnects (project-scoped).
    - Configuration changes are broadcast to ALL clients for multi-device sync.
    - Output streaming is sent only to the requesting client (not broadcast).
"""

from __future__ import annotations

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.payloads.run_config import (
    RunConfigChangedPayload,
    RunConfigCreatePayload,
    RunConfigCreatedPayload,
    RunConfigDeletedPayload,
    RunConfigDeletePayload,
    RunConfigListResultPayload,
    RunConfigOutputPayload,
    RunConfigRestartPayload,
    RunConfigSelectPayload,
    RunConfigStartPayload,
    RunConfigStateChangedPayload,
    RunConfigStatusResultPayload,
    RunConfigStopPayload,
    RunConfigUpdatePayload,
    RunConfigUpdatedPayload,
)
from mobileflow_protocol.types import MessageType

from ...services.run_config import RunConfigurationExecutor, RunConfigurationStore, RunConfigType
from .base import BaseHandler


class RunConfigHandler(BaseHandler):
    """Handles run_config.* protocol messages.

    Routes CRUD operations to RunConfigurationStore and execution
    commands to RunConfigurationExecutor. Broadcasts state changes
    and configuration updates to all connected clients.

    Attributes:
        _store: Configuration persistence and CRUD operations.
        _executor: Execution engine for running configurations.
    """

    def __init__(self, server, store: RunConfigurationStore, executor: RunConfigurationExecutor):
        """Initialize the handler with store and executor dependencies.

        Registers global listeners on the executor so that ALL state
        changes and output are broadcast to ALL connected WebSocket
        clients, regardless of who triggered the action (App or Dashboard).

        Args:
            server: The owning WebSocketServer instance.
            store: RunConfigurationStore for CRUD operations.
            executor: RunConfigurationExecutor for lifecycle management.
        """
        super().__init__(server)
        self._store = store
        self._executor = executor

        # Register global listeners for state changes and output.
        # These fire for EVERY state transition, ensuring all clients
        # stay in sync even when actions are triggered from Dashboard HTTP API.
        executor.set_global_listeners(
            on_state_changed=self._on_global_state_changed,
            on_output=self._on_global_output,
        )

    async def _on_global_state_changed(self, config_id: str, state, **kwargs) -> None:
        """Global state change listener — broadcasts to all WebSocket clients."""
        from mobileflow_protocol.payloads.run_config import RunConfigStateChangedPayload
        state_value = state.value if hasattr(state, 'value') else str(state)
        preview_url = kwargs.get("preview_url")
        logger.debug(
            f"广播 run_config 状态变更: id={config_id[:16]}..., "
            f"state={state_value}, preview_url={preview_url}"
        )
        msg = Message.from_typed(
            type=MessageType.RUN_CONFIG_STATE_CHANGED,
            payload=RunConfigStateChangedPayload(
                config_id=config_id,
                state=state_value,
                exit_code=kwargs.get("exit_code"),
                error_message=kwargs.get("error_message"),
                preview_url=preview_url,
            ),
        )
        await self.broadcast(msg)

    async def _on_global_output(self, config_id: str, stream: str, text: str) -> None:
        """Global output listener — broadcasts to all WebSocket clients.

        Called by the executor for every output line from any running
        configuration, regardless of who triggered the execution. This
        ensures Dashboard-triggered runs also have their output visible
        to all connected App clients.

        Args:
            config_id: ID of the configuration producing output.
            stream: Output stream name ("stdout" or "stderr").
            text: The output text content.
        """
        output_msg = Message.from_typed(
            type=MessageType.RUN_CONFIG_OUTPUT,
            payload=RunConfigOutputPayload(
                config_id=config_id,
                stream=stream,
                data=text,
            ),
        )
        await self.broadcast(output_msg)

    async def handle_run_config_list(self, client_id: str, ws, msg: Message) -> None:
        """Handle run_config.list — return all configurations.

        Args:
            client_id: ID of the requesting client.
            ws: The client's WebSocket connection.
            msg: The incoming protocol message.
        """
        configs = self._store.list_all()
        payload = RunConfigListResultPayload(
            configurations=[c.model_dump(mode="json") for c in configs],
            selected_id=self._store.selected_id,
        )
        await self.send(ws, Message.from_typed(
            type=MessageType.RUN_CONFIG_LIST_RESULT,
            payload=payload,
        ))
        logger.debug(f"run_config.list: 返回 {len(configs)} 条配置")

    async def handle_run_config_create(self, client_id: str, ws, msg: Message) -> None:
        """Handle run_config.create — create a new configuration.

        Creates the configuration with template defaults, sends the
        created config back to the requester, and broadcasts the
        updated list to all clients.

        Args:
            client_id: ID of the requesting client.
            ws: The client's WebSocket connection.
            msg: The incoming protocol message with RunConfigCreatePayload.
        """
        payload = RunConfigCreatePayload.model_validate(msg.payload)
        config_type = RunConfigType(payload.type)
        config = self._store.create(config_type, payload.initial_fields)

        # Send created confirmation to requester
        await self.send(ws, Message.from_typed(
            type=MessageType.RUN_CONFIG_CREATED,
            payload=RunConfigCreatedPayload(
                configuration=config.model_dump(mode="json"),
            ),
        ))

        # Broadcast change to all clients
        await self._broadcast_changed()
        logger.info(f"run_config.create: name={config.name!r}, type={config_type.value}")

    async def handle_run_config_update(self, client_id: str, ws, msg: Message) -> None:
        """Handle run_config.update — partial field update.

        Updates the specified fields, sends the updated config back
        to the requester, and broadcasts the change to all clients.

        Args:
            client_id: ID of the requesting client.
            ws: The client's WebSocket connection.
            msg: The incoming protocol message with RunConfigUpdatePayload.
        """
        payload = RunConfigUpdatePayload.model_validate(msg.payload)
        updated = self._store.update(payload.config_id, payload.updates)

        if updated is None:
            await self.send_error(ws, f"Configuration not found: {payload.config_id}")
            return

        # Send updated confirmation to requester
        await self.send(ws, Message.from_typed(
            type=MessageType.RUN_CONFIG_UPDATED,
            payload=RunConfigUpdatedPayload(
                configuration=updated.model_dump(mode="json"),
            ),
        ))

        # Broadcast change to all clients
        await self._broadcast_changed()
        logger.debug(f"run_config.update: id={payload.config_id[:16]}..., fields={list(payload.updates.keys())}")

    async def handle_run_config_delete(self, client_id: str, ws, msg: Message) -> None:
        """Handle run_config.delete — remove a configuration.

        Deletes the configuration, sends confirmation to the requester,
        and broadcasts the change to all clients.

        Args:
            client_id: ID of the requesting client.
            ws: The client's WebSocket connection.
            msg: The incoming protocol message with RunConfigDeletePayload.
        """
        payload = RunConfigDeletePayload.model_validate(msg.payload)
        success = self._store.delete(payload.config_id)

        if not success:
            await self.send_error(ws, f"Configuration not found: {payload.config_id}")
            return

        # Send deleted confirmation to requester
        await self.send(ws, Message.from_typed(
            type=MessageType.RUN_CONFIG_DELETED,
            payload=RunConfigDeletedPayload(config_id=payload.config_id),
        ))

        # Broadcast change to all clients
        await self._broadcast_changed()
        logger.info(f"run_config.delete: id={payload.config_id[:16]}...")

    async def handle_run_config_select(self, client_id: str, ws, msg: Message) -> None:
        """Handle run_config.select — set the selected configuration.

        Updates the selection and broadcasts the change to all clients.

        Args:
            client_id: ID of the requesting client.
            ws: The client's WebSocket connection.
            msg: The incoming protocol message with RunConfigSelectPayload.
        """
        payload = RunConfigSelectPayload.model_validate(msg.payload)
        self._store.select(payload.config_id)

        # Broadcast change to all clients
        await self._broadcast_changed()
        logger.debug(f"run_config.select: id={payload.config_id[:16] + '...' if payload.config_id else 'None'}")

    async def handle_run_config_start(self, client_id: str, ws, msg: Message) -> None:
        """Handle run_config.start — start execution of a configuration.

        Looks up the configuration, updates last_used_at, then delegates
        to the executor. Output and state changes are streamed back to
        the requesting client via callbacks.

        Args:
            client_id: ID of the requesting client.
            ws: The client's WebSocket connection.
            msg: The incoming protocol message with RunConfigStartPayload.
        """
        payload = RunConfigStartPayload.model_validate(msg.payload)
        config = self._store.get(payload.config_id)

        if config is None:
            await self.send_error(ws, f"Configuration not found: {payload.config_id}")
            return

        # Update last_used_at timestamp
        from datetime import datetime
        self._store.update(payload.config_id, {"last_used_at": datetime.now().isoformat()})

        # Output broadcasting is handled by the global listener registered
        # in __init__ (which now receives config_id). No per-call output
        # callback needed — avoids duplicate broadcasts.

        # State changes are handled by the global listener registered in __init__.

        # Start execution (runs in background via executor)
        await self._executor.start(config)
        logger.info(f"run_config.start: name={config.name!r}, id={payload.config_id[:16]}...")

    async def handle_run_config_stop(self, client_id: str, ws, msg: Message) -> None:
        """Handle run_config.stop — stop a running configuration.

        Args:
            client_id: ID of the requesting client.
            ws: The client's WebSocket connection.
            msg: The incoming protocol message with RunConfigStopPayload.
        """
        payload = RunConfigStopPayload.model_validate(msg.payload)
        await self._executor.stop(payload.config_id)
        logger.info(f"run_config.stop: id={payload.config_id[:16]}...")

    async def handle_run_config_restart(self, client_id: str, ws, msg: Message) -> None:
        """Handle run_config.restart — restart a configuration.

        Stops the existing instance and starts a new one. Output and
        state changes are streamed back via callbacks.

        Args:
            client_id: ID of the requesting client.
            ws: The client's WebSocket connection.
            msg: The incoming protocol message with RunConfigRestartPayload.
        """
        payload = RunConfigRestartPayload.model_validate(msg.payload)
        config = self._store.get(payload.config_id)

        if config is None:
            await self.send_error(ws, f"Configuration not found: {payload.config_id}")
            return

        # Output broadcasting handled by global listener (no per-call callback needed)
        await self._executor.restart(payload.config_id)
        logger.info(f"run_config.restart: id={payload.config_id[:16]}...")

    async def handle_run_config_status(self, client_id: str, ws, msg: Message) -> None:
        """Handle run_config.status — return all running states.

        Useful for clients reconnecting to sync their UI state with
        the current execution status.

        Args:
            client_id: ID of the requesting client.
            ws: The client's WebSocket connection.
            msg: The incoming protocol message.
        """
        all_states = self._executor.get_all_states()
        # Convert RunConfigState enum values to strings
        states_dict = {
            cid: state.value if hasattr(state, 'value') else str(state)
            for cid, state in all_states.items()
        }
        await self.send(ws, Message.from_typed(
            type=MessageType.RUN_CONFIG_STATUS_RESULT,
            payload=RunConfigStatusResultPayload(states=states_dict),
        ))
        logger.debug(f"run_config.status: {len(states_dict)} 个非空闲配置")

    # ── Private helpers ──

    async def _broadcast_changed(self) -> None:
        """Broadcast the current configuration list to all connected clients.

        Called after any CRUD operation that modifies the configuration
        list (create, update, delete, select, reorder).
        """
        configs = self._store.list_all()
        payload = RunConfigChangedPayload(
            configurations=[c.model_dump(mode="json") for c in configs],
            selected_id=self._store.selected_id,
        )
        await self.broadcast(Message.from_typed(
            type=MessageType.RUN_CONFIG_CHANGED,
            payload=payload,
        ))
