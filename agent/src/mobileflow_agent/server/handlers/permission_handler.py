"""Permission request handler and terminal output relay.

Module: server/handlers/
Responsibility:
    - Listen for EventBus ``permission.request`` events, push them to the App,
      and wait for the user's response.
    - Relay ACP terminal output events to connected mobile clients.

Design decisions:
    - Full diff data is now pushed through the collector → chat.stream path
      (following the VS Code pattern), so ``file.written`` is no longer handled
      here.
"""

from __future__ import annotations

import asyncio

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.errors import PayloadValidationError
from mobileflow_protocol.payloads.permission import (
    PermissionRequestPayload,
    PermissionResponsePayload,
)
from mobileflow_protocol.payloads.terminal import TerminalOutputPayload
from mobileflow_protocol.types import MessageType

from .base import BaseHandler


class PermissionHandler(BaseHandler):
    """Handles permission request/response flow and terminal output relay.

    Bridges the EventBus (internal) with the WebSocket protocol (external)
    for permission prompts and ACP terminal output.
    """

    def register_events(self):
        """Register EventBus listeners for permission requests and terminal output."""
        from ...core.events import Events
        self.event_bus.on(Events.PERMISSION_REQUEST, self.handle_permission_request)
        self.event_bus.on(Events.TERMINAL_OUTPUT, self.handle_terminal_output)
        # file.written is no longer needed: full diffs are now pushed directly
        # through collector → chat.stream (following the VS Code pattern)

    async def handle_permission_request(self, data: dict) -> dict | None:
        """Push a permission request to the App and wait for the user's response.

        Creates an asyncio Future that blocks until the App replies or the
        request times out (120 s).

        Args:
            data: Permission request payload containing tool_name, tool_kind,
                description, and available options.

        Returns:
            A dict with the user's outcome (selected option or cancelled),
            or a cancelled outcome on timeout.
        """
        self.server._permission_counter += 1
        request_id = f"perm_{self.server._permission_counter}"

        msg = Message.from_typed(
            type=MessageType.PERMISSION_REQUEST,
            payload=PermissionRequestPayload(
                request_id=request_id,
                tool_name=data.get("tool_name", ""),
                tool_kind=data.get("tool_kind", ""),
                description=data.get("description", ""),
                options=data.get("options", []),
            ),
        )
        await self.broadcast(msg)
        logger.debug(f"权限请求已推送: {request_id}")

        future: asyncio.Future = asyncio.get_event_loop().create_future()
        self.server._permission_futures[request_id] = future
        try:
            timeout = self.config.timeouts.permission_response
            result = await asyncio.wait_for(future, timeout=timeout)
            logger.debug(f"权限回复: {request_id}, result={result}")
            return result
        except asyncio.TimeoutError:
            logger.warning(f"权限请求超时: {request_id}")
            return {"outcome": {"outcome": "cancelled"}}
        finally:
            self.server._permission_futures.pop(request_id, None)

    async def handle_permission_response(self, client_id, ws, msg):
        """Handle the App's reply to a permission request.

        Resolves the corresponding Future so the blocked handler can continue.

        Args:
            client_id: Identifier of the responding client.
            ws: The client's WebSocket connection.
            msg: Protocol message containing request_id, option_id, and approved flag.
        """
        try:
            payload = msg.typed_payload(PermissionResponsePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ permission.response payload 校验失败: client={client_id}, {e}")
            return

        request_id = payload.request_id
        option_id = payload.option_id
        approved = payload.approved
        logger.info(f"收到权限回复: {request_id}, approved={approved}, option={option_id}")

        future = self.server._permission_futures.get(request_id)
        if future and not future.done():
            if approved:
                future.set_result({"outcome": {"outcome": "selected", "optionId": option_id}})
            else:
                future.set_result({"outcome": {"outcome": "selected", "optionId": "reject_once"}})
        else:
            logger.warning(f"权限回复无效: {request_id}")

    async def handle_terminal_output(self, data: dict) -> None:
        """Relay ACP terminal output to all connected mobile clients.

        Args:
            data: Dict with ``terminal_id`` and ``text`` fields.
        """
        await self.broadcast(Message.from_typed(
            type=MessageType.TERMINAL_OUTPUT,
            payload=TerminalOutputPayload(terminal_id=data.get("terminal_id", ""), text=data.get("text", ""), source="acp"),
        ))
