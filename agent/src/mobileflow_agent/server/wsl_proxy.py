"""WSL Agent message proxy — transparent forwarding between parent and child Agent.

Module: server/
Responsibility:
    When the active CLI runs in WSL, this proxy forwards CLI-related
    messages to the WSL child Agent and relays responses back to the App.
    Non-CLI messages (file, git, project) are handled locally by the
    parent Agent and never forwarded.
"""

from __future__ import annotations

import asyncio
import json

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.payloads.cli import CliStatusPayload
from mobileflow_protocol.types import MessageType

from ..utils.i18n import t


# Message types forwarded to WSL child Agent.
# IMPORTANT: Keep in sync with MessageType enum in mobileflow_protocol.
_FORWARDED_TYPES: set[str] = {
    MessageType.CHAT_SEND.value,
    MessageType.CHAT_CANCEL.value,
    MessageType.CHAT_HISTORY.value,
    MessageType.CHAT_HISTORY_MORE.value,
    MessageType.SESSION_LIST.value,
    MessageType.SESSION_NEW.value,
    MessageType.SESSION_SWITCH.value,
    MessageType.SESSION_CLOSE.value,
    MessageType.TERMINAL_START.value,
    MessageType.TERMINAL_INPUT.value,
    MessageType.TERMINAL_RESIZE.value,
    MessageType.TERMINAL_STOP.value,
    MessageType.PERMISSION_RESPONSE.value,
    MessageType.AUTH_SUBMIT.value,
    MessageType.MODE_SET.value,
    MessageType.CONFIG_SET.value,
}

# Message types relayed from child Agent back to App.
# IMPORTANT: Keep in sync with MessageType enum in mobileflow_protocol.
_RELAYED_TYPES: set[str] = {
    MessageType.CHAT_STREAM.value,
    MessageType.CHAT_DONE.value,
    MessageType.CHAT_ERROR.value,
    MessageType.CHAT_HISTORY_RESULT.value,
    MessageType.CHAT_HISTORY_MORE_RESULT.value,
    MessageType.SESSION_LIST_RESULT.value,
    MessageType.TERMINAL_OUTPUT.value,
    MessageType.TERMINAL_STARTED.value,
    MessageType.CLI_STATUS.value,
    MessageType.PERMISSION_REQUEST.value,
}


class WslProxy:
    """Transparent message proxy between parent Agent and WSL child Agent."""

    def __init__(self, wsl_manager, broadcast_fn) -> None:
        from ..services.wsl_agent_manager import WslAgentManager
        self._wsl_manager: WslAgentManager = wsl_manager
        self._broadcast_fn = broadcast_fn
        self._active = False
        self._relay_task: asyncio.Task | None = None

    @property
    def is_active(self) -> bool:
        return self._active

    def should_forward(self, msg_type: str) -> bool:
        return self._active and msg_type in _FORWARDED_TYPES

    async def activate(self) -> bool:
        if self._active:
            return True
        if not await self._wsl_manager.ensure_started():
            logger.error("[WslProxy] 无法启动 WSL 子 Agent，代理激活失败")
            return False
        self._active = True
        self._relay_task = asyncio.create_task(self._relay_loop())
        logger.info("[WslProxy] 代理已激活，消息将转发到 WSL 子 Agent")
        return True

    async def deactivate(self) -> None:
        self._active = False
        if self._relay_task and not self._relay_task.done():
            self._relay_task.cancel()
            try:
                await self._relay_task
            except asyncio.CancelledError:
                pass
        self._relay_task = None
        logger.info("[WslProxy] 代理已停用")

    async def forward(self, msg: Message) -> None:
        if not self._wsl_manager.is_connected:
            logger.warning(f"[WslProxy] 转发失败（未连接）: type={msg.type}")
            return
        try:
            await self._wsl_manager.send(msg.model_dump_json())
            logger.debug(f"[WslProxy] → WSL: {msg.type}")
        except Exception as e:
            logger.error(f"[WslProxy] 转发到 WSL 失败: type={msg.type}, error={e}")

    async def _relay_loop(self) -> None:
        logger.debug("[WslProxy] 开始中继循环")
        try:
            while self._active and self._wsl_manager.is_connected:
                try:
                    raw = await asyncio.wait_for(self._wsl_manager.recv(), timeout=30.0)
                except asyncio.TimeoutError:
                    continue
                try:
                    data = json.loads(raw)
                    msg_type = data.get("type", "")
                    if msg_type in _RELAYED_TYPES:
                        await self._broadcast_fn(raw)
                        logger.debug(f"[WslProxy] ← WSL: {msg_type}")
                except json.JSONDecodeError:
                    logger.warning("[WslProxy] 子 Agent 返回无效 JSON")
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning(f"[WslProxy] 中继循环出错: {e}")
            try:
                error_msg = Message.from_typed(
                    type=MessageType.CLI_STATUS,
                    payload=CliStatusPayload(
                        cli="", state="failed",
                        message=t("backend.wslAgentDisconnected", error=str(e)), error=str(e),
                    ),
                )
                await self._broadcast_fn(error_msg.model_dump_json())
            except Exception:
                pass
        finally:
            logger.debug("[WslProxy] 中继循环结束")

    async def shutdown(self) -> None:
        await self.deactivate()
        await self._wsl_manager.stop()
        logger.info("[WslProxy] 已关闭")
