"""Authentication interceptor for CLI-dependent handlers.

Two responsibilities:
1. pre_handle: If handler requires CLI and CLI state is auth_required,
   cancel the request and push auth_required to frontend.
2. on_error: If handler raises AuthRequiredError, set CLI state to
   auth_required and push to frontend.

This replaces the old _with_auth_retry + auth_event.wait() pattern
that caused deadlocks by blocking the message loop.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.payloads.chat import ChatErrorPayload
from mobileflow_protocol.types import MessageType

from ...utils.i18n import t
from .base import Interceptor, MessageContext
from ...core.errors import AuthRequiredError
from ...providers.base import ProviderLifecycleState

if TYPE_CHECKING:
    from ..websocket import WebSocketServer


class AuthInterceptor(Interceptor):
    """Interceptor that manages CLI authentication state.

    Attributes:
        order: 10 (runs after LogInterceptor at 1).
    """

    order: int = 10

    def __init__(self, server: 'WebSocketServer'):
        """Initialize with server reference.

        Args:
            server: The WebSocketServer instance for accessing cli_manager
                and broadcasting messages.
        """
        self._server = server

    async def pre_handle(self, ctx: MessageContext) -> None:
        """Ensure project and CLI provider are ready for handlers that require them.

        Logic:
        0. If handler requires a project and none is selected -> reject.
        1. If handler doesn't require CLI -> pass through.
        2. Extract cli_name from message payload.
        3. If no provider exists -> trigger initialization via _ensure_provider.
        4. After init, check lifecycle state:
           - READY -> pass through.
           - AUTH_REQUIRED -> push auth_required to frontend, cancel request.
           - FAILED/None -> cancel request (init failed).

        This ensures ALL requires_cli handlers are protected — no handler
        needs to call _ensure_provider itself.

        Args:
            ctx: The message context.
        """
        # Project check — reject handlers that need a project when none is selected
        if ctx.requires_project and not self._server.config.work_dir:
            logger.info(
                f"拦截器阻止请求: handler={ctx.handler_name}, "
                f"原因=未选择项目"
            )
            await ctx.ws.send(Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=t("backend.addProjectFirst")),
            ).model_dump_json())
            ctx.cancelled = True
            return

        if not ctx.requires_cli:
            return

        cli_name = (
            ctx.msg.payload.get("cli")
            or self._server.config.default_cli
        )
        ctx.metadata["cli_name"] = cli_name

        key = (ctx.client_id, cli_name)
        cli_mgr = self._server.cli_manager

        provider = cli_mgr._sessions.get(key)

        # No provider yet — trigger initialization
        if not provider:
            logger.info(
                f"拦截器触发 provider 初始化: handler={ctx.handler_name}, "
                f"cli={cli_name}"
            )
            provider = await cli_mgr._ensure_provider(
                ctx.client_id, cli_name
            )
            if not provider:
                # Init failed (binary not found, timeout, etc.)
                # _init_provider already pushed "failed" status
                logger.warning(
                    f"拦截器: provider 初始化失败: cli={cli_name}"
                )
                ctx.cancelled = True
                return

        # Provider exists — check auth state
        if provider._lifecycle_state == ProviderLifecycleState.AUTH_REQUIRED:
            logger.info(
                f"拦截器阻止请求: handler={ctx.handler_name}, "
                f"cli={cli_name}, 原因=需要认证"
            )
            await cli_mgr._push_status(
                key, "auth_required", t("backend.authRequired")
            )
            ctx.cancelled = True

    async def on_error(
        self, ctx: MessageContext, error: Exception
    ) -> None:
        """Catch AuthRequiredError and transition CLI to auth_required.

        When any handler raises AuthRequiredError (thrown by cli_manager
        when ACP returns -32000), this interceptor:
        1. Sets the provider lifecycle state to AUTH_REQUIRED.
        2. Pushes auth_required status with auth methods to frontend.

        Args:
            ctx: The message context.
            error: The exception raised by the handler.
        """
        if not isinstance(error, AuthRequiredError):
            return

        cli_name = ctx.metadata.get("cli_name") or (
            ctx.msg.payload.get("cli")
            or self._server.config.default_cli
        )
        key = (ctx.client_id, cli_name)
        cli_mgr = self._server.cli_manager

        logger.info(
            f"拦截器捕获认证错误: handler={ctx.handler_name}, "
            f"cli={cli_name}"
        )

        # Set provider state to auth_required
        provider = cli_mgr._sessions.get(key)
        if provider:
            provider._lifecycle_state = ProviderLifecycleState.AUTH_REQUIRED

        # Push auth_required to frontend (includes auth_methods via _push_status)
        await cli_mgr._push_status(
            key, "auth_required", t("backend.authRequired")
        )
