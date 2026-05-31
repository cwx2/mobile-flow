"""Chat and session management handler.

Module: server/handlers/
Responsibility:
    - chat.send  → forward user message to the AI CLI, stream back the reply.
    - chat.cancel → cancel the current AI operation.
    - chat.history → retrieve conversation history.
    - session.list / session.new / session.switch → session lifecycle.

Dependencies:
    CLIManager (accessed via ``BaseHandler.cli_manager``).
"""

from __future__ import annotations

from pathlib import Path

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.errors import PayloadValidationError
from mobileflow_protocol.payloads.chat import (
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
from mobileflow_protocol.payloads.session import (
    SessionClosePayload,
    SessionListPayload,
    SessionListResultPayload,
    SessionNewPayload,
    SessionSwitchPayload,
)
from mobileflow_protocol.types import MessageType

from ...core.errors import AuthRequiredError
from ...services.context_resolver import ContextReferenceModel, ContextResolver
from .base import BaseHandler


class ChatHandler(BaseHandler):
    """Handles chat messaging and session management over WebSocket.

    Delegates AI interaction to CLIManager and streams results back to the
    mobile App.
    """

    async def handle_chat_send(self, client_id, ws, msg):
        """Forward a chat message to the AI CLI and stream the response back.

        Uses StreamReplay to buffer every chunk so that a reconnecting
        client can catch up on missed output.  When ws.send() fails
        (client disconnected), the loop continues consuming ACP events
        into the buffer — the AI operation is never interrupted.

        Supports multimodal attachments matching ACP ContentBlock types:
          - image:  ``{type, mime_type, content (base64)}``
          - audio:  ``{type, mime_type, content (base64)}``
          - resource: ``{type, uri, content, mime_type}``
          - resource_link: ``{type, uri, name, mime_type}``

        Args:
            client_id: Identifier of the sending client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``message``, ``cli``, ``context``,
                and optional ``attachments`` in the payload.
        """
        try:
            payload = msg.typed_payload(ChatSendPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ chat.send payload 校验失败: client={client_id}, {e}")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=str(e)),
            ))
            return

        cli_name = payload.cli or self.config.default_cli
        message = payload.message
        context = payload.context
        attachments = payload.attachments

        logger.info(f"💬 [{cli_name}] {message[:50]}...")
        if attachments:
            logger.info(f"📎 附件: {len(attachments)} 个")

        # Get the StreamReplay buffer for this client (created with scope)
        replay = self.server.get_stream_replay(client_id)
        if replay:
            replay.begin_turn(cli_name=cli_name)

        try:
            # Parse attachments into typed lists for ACP ContentBlock
            images: list[dict] | None = None
            audio_files: list[dict] | None = None
            resources: list[dict] | None = None

            if attachments:
                import base64
                images = []
                audio_files = []
                resources = []
                att_cfg = self.config.attachments
                for att in attachments:
                    att_type = att.get("type", "")
                    try:
                        if att_type == "image" and att.get("content"):
                            # Pre-decode size check: base64 encodes 3 bytes as 4 chars,
                            # so decoded_size ≈ len(b64_str) * 3/4.
                            b64_str = att["content"]
                            estimated_mb = len(b64_str) * 0.75 / (1024 * 1024)
                            if estimated_mb > att_cfg.max_image_size_mb:
                                logger.warning(f"图片过大（预检）: ~{estimated_mb:.1f}MB > {att_cfg.max_image_size_mb}MB，已跳过")
                                continue
                            raw = base64.b64decode(b64_str)
                            mime = att.get("mime_type", "image/png")
                            images.append({"data": raw, "mime_type": mime})
                        elif att_type == "audio" and att.get("content"):
                            b64_str = att["content"]
                            estimated_mb = len(b64_str) * 0.75 / (1024 * 1024)
                            if estimated_mb > att_cfg.max_audio_size_mb:
                                logger.warning(f"音频过大（预检）: ~{estimated_mb:.1f}MB > {att_cfg.max_audio_size_mb}MB，已跳过")
                                continue
                            raw = base64.b64decode(b64_str)
                            mime = att.get("mime_type", "audio/wav")
                            audio_files.append({"data": raw, "mime_type": mime})
                        elif att_type == "resource":
                            resources.append({
                                "type": "resource",
                                "uri": att.get("uri", ""),
                                "content": att.get("content", ""),
                                "mime_type": att.get("mime_type", ""),
                            })
                        elif att_type == "resource_link":
                            resources.append({
                                "type": "resource_link",
                                "uri": att.get("uri", ""),
                                "name": att.get("name", ""),
                                "mime_type": att.get("mime_type", ""),
                            })
                        else:
                            logger.warning(f"未知附件类型: {att_type}")
                    except Exception as e:
                        logger.warning(f"附件解码失败: type={att_type}, error={e}")

                if not images: images = None
                if not audio_files: audio_files = None
                if not resources: resources = None

            # Resolve structured context references from the App.
            # References are lightweight descriptors (type + path); the Agent
            # resolves them to actual content and prepends to the user message
            # before forwarding to the AI CLI. This keeps the App thin (zero
            # data storage) and centralises token budget enforcement here.
            context_references = payload.context_references
            if context_references:
                try:
                    refs = [ContextReferenceModel(**r) for r in context_references]
                    logger.debug(f"上下文引用解析: count={len(refs)}")

                    # TerminalManager doesn't buffer output history, so we
                    # pass an empty dict. Terminal context resolution will
                    # return "(no terminal output)" — acceptable until a
                    # terminal output buffer is implemented.
                    terminal_outputs: dict[str, list[str]] = {}

                    resolver = ContextResolver(
                        config=self.config.context,
                        file_service=self.file_service,
                        git_service=self.server.git_service,
                        terminal_outputs=terminal_outputs,
                        work_dir=Path(self.config.work_dir),
                    )
                    context_text = await resolver.resolve(refs)
                    if context_text:
                        message = f"{context_text}\n\n{message}"
                        logger.info(f"上下文已注入消息: refs={len(refs)}, context_chars={len(context_text)}")
                except Exception as e:
                    # Never block the message — if context resolution fails,
                    # log and proceed with the original message as-is.
                    logger.warning(f"上下文引用解析失败，跳过: error={e}")

            chunk_count = 0
            send_failures = 0
            async for chunk in self.cli_manager.send_message(
                client_id=client_id, cli_name=cli_name,
                message=message, context=context, work_dir=self.config.work_dir,
                images=images, audio_files=audio_files, resources=resources,
            ):
                chunk_count += 1
                stream_msg = Message.from_typed(
                    type=MessageType.CHAT_STREAM,
                    payload=ChatStreamPayload(chunk=chunk.model_dump()),
                )
                # Always buffer the chunk for replay on reconnect
                if replay:
                    replay.push(stream_msg.model_dump())
                # Try to send; on failure, continue consuming ACP events
                # into the buffer — the AI operation must not be interrupted.
                try:
                    await self.send(ws, stream_msg)
                except Exception:
                    send_failures += 1
                    if send_failures == 1:
                        logger.info(
                            f"客户端断连，继续缓冲 AI 输出: "
                            f"cli={cli_name}, client={client_id[:8]}..."
                        )

            # Turn complete — buffer the done message
            done_msg = Message.from_typed(
                type=MessageType.CHAT_DONE,
                payload=ChatDonePayload(),
            )
            if replay:
                replay.push(done_msg.model_dump())
                replay.finish_turn(done_payload=done_msg.model_dump())

            if send_failures > 0:
                logger.info(
                    f"chat.done: {chunk_count} chunks, "
                    f"{send_failures} 未送达（已缓冲）: cli={cli_name}"
                )
            else:
                logger.info(f"chat.done: {chunk_count} chunks sent")

            # Always try to send chat.done — even if some chunks failed,
            # the client may still be connected (transient network blip).
            # If the client is truly gone, the exception is harmless.
            try:
                await self.send(ws, done_msg)
            except Exception:
                pass

        except AuthRequiredError:
            # Let interceptor chain handle auth — don't send CHAT_ERROR
            if replay:
                replay.finish_turn()
            raise
        except Exception as e:
            logger.error(f"handle_chat_send error: {e}")
            if replay:
                replay.finish_turn()
            try:
                await self.send(ws, Message.from_typed(
                    type=MessageType.CHAT_ERROR,
                    payload=ChatErrorPayload(error=f"Error: {e}"),
                ))
                await self.send(ws, Message.from_typed(
                    type=MessageType.CHAT_DONE,
                    payload=ChatDonePayload(),
                ))
            except Exception:
                pass  # WebSocket may already be disconnected

    async def handle_chat_history(self, client_id, ws, msg):
        """Retrieve and return paginated chat history for a session.

        Returns only the last page of messages plus total count and
        has_more flag. The App can request older pages via
        chat.history.more.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``cli`` and ``session_id``.
        """
        try:
            payload = msg.typed_payload(ChatHistoryPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ chat.history payload 校验失败: client={client_id}, {e}")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=str(e)),
            ))
            return

        cli_name = payload.cli or self.config.default_cli
        session_id = payload.session_id
        logger.info(f"[chat.history] cli={cli_name}, session_id={session_id}")
        result = await self.cli_manager.read_history(cli_name, client_id, session_id)
        resumed = result.get("resumed", False)
        logger.info(f"[chat.history] 返回 {len(result.get('messages', []))} 条 (total={result.get('total', 0)}, has_more={result.get('has_more', False)}, resumed={resumed})")
        await self.send(ws, Message.from_typed(
            type=MessageType.CHAT_HISTORY_RESULT,
            payload=ChatHistoryResultPayload(
                messages=result.get("messages", []),
                total=result.get("total", 0),
                has_more=result.get("has_more", False),
                cli=cli_name,
                resumed=resumed,
            ),
        ))

    async def handle_chat_history_more(self, client_id, ws, msg):
        """Return the next page of older history messages.

        Called when the App scrolls to the top and needs more messages.
        Reads from the in-memory cache populated by the initial
        chat.history load.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``cli``, ``offset``, and ``limit``.
        """
        try:
            payload = msg.typed_payload(ChatHistoryMorePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ chat.history.more payload 校验失败: client={client_id}, {e}")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=str(e)),
            ))
            return

        cli_name = payload.cli or self.config.default_cli
        offset = payload.offset
        limit = payload.limit or self.config.history.page_size
        logger.info(f"[chat.history.more] cli={cli_name}, offset={offset}, limit={limit}")
        result = await self.cli_manager.read_history_page(cli_name, client_id, offset, limit)
        logger.info(f"[chat.history.more] 返回 {len(result.get('messages', []))} 条, has_more={result.get('has_more', False)}")
        await self.send(ws, Message.from_typed(
            type=MessageType.CHAT_HISTORY_MORE_RESULT,
            payload=ChatHistoryMoreResultPayload(
                messages=result.get("messages", []),
                total=result.get("total", 0),
                has_more=result.get("has_more", False),
                cli=cli_name,
            ),
        ))

    async def handle_session_list(self, client_id, ws, msg):
        """List all available sessions for the given CLI.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``cli``.
        """
        try:
            payload = msg.typed_payload(SessionListPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ session.list payload 校验失败: client={client_id}, {e}")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=str(e)),
            ))
            return

        cli_name = payload.cli or self.config.default_cli
        logger.info(f"[session.list] 收到请求: cli={cli_name}, client={client_id[:8]}...")
        sessions = await self.cli_manager.list_sessions(cli_name, client_id)
        logger.info(f"[session.list] 返回 {len(sessions)} 个会话")
        for i, s in enumerate(sessions):
            logger.debug(f"  [{i}] id={str(s.get('id', s.get('session_id', '')))[:12]}... preview={str(s.get('preview', s.get('title', '')))[:30]} updated_at={s.get('updated_at', '')}")
        await self.send(ws, Message.from_typed(
            type=MessageType.SESSION_LIST_RESULT,
            payload=SessionListResultPayload(sessions=sessions, cli=cli_name),
        ))

    async def handle_session_new(self, client_id, ws, msg):
        """Create a new session and return an empty history.

        Cancels any in-progress prompt before creating the new session
        to prevent stale stream chunks from leaking into the new context.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``cli``.
        """
        try:
            payload = msg.typed_payload(SessionNewPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ session.new payload 校验失败: client={client_id}, {e}")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=str(e)),
            ))
            return

        cli_name = payload.cli or self.config.default_cli
        await self.cli_manager.cancel_current(cli_name, client_id)
        await self.cli_manager.new_session(cli_name, client_id)
        await self.send(ws, Message.from_typed(
            type=MessageType.CHAT_HISTORY_RESULT,
            payload=ChatHistoryResultPayload(messages=[], cli=cli_name),
        ))

    async def handle_session_switch(self, client_id, ws, msg):
        """Switch to an existing session and return its paginated history.

        Cancels any in-progress prompt before switching to prevent stale
        stream chunks from leaking into the switched session's context.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``session_id`` and optional ``cli``.
        """
        try:
            payload = msg.typed_payload(SessionSwitchPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ session.switch payload 校验失败: client={client_id}, {e}")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=str(e)),
            ))
            return

        cli_name = payload.cli or self.config.default_cli
        session_id = payload.session_id
        logger.info(f"[session.switch] 切换会话: {session_id[:16]}...")
        await self.cli_manager.cancel_current(cli_name, client_id)
        result = await self.cli_manager.switch_session(cli_name, client_id, session_id)
        messages = result.get("messages", [])
        if not messages and session_id:
            logger.warning(f"[session.switch] 会话无历史或不可用: {session_id[:16]}...")
        logger.info(f"[session.switch] 返回 {len(messages)} 条 (total={result.get('total', 0)})")
        await self.send(ws, Message.from_typed(
            type=MessageType.CHAT_HISTORY_RESULT,
            payload=ChatHistoryResultPayload(
                messages=messages,
                total=result.get("total", 0),
                has_more=result.get("has_more", False),
                cli=cli_name,
            ),
        ))

    async def handle_session_close(self, client_id, ws, msg):
        """Close (delete) a session.

        Calls ACP close_session if supported, then removes the session
        from SessionStore so it no longer appears in the session list.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``session_id`` and optional ``cli``.
        """
        try:
            payload = msg.typed_payload(SessionClosePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ session.close payload 校验失败: client={client_id}, {e}")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=str(e)),
            ))
            return

        cli_name = payload.cli or self.config.default_cli
        session_id = payload.session_id
        logger.info(f"[session.close] 删除会话: {session_id[:16]}...")
        await self.cli_manager.close_session(cli_name, client_id, session_id)
        # Refresh session list for the App
        sessions = await self.cli_manager.list_sessions(cli_name, client_id)
        await self.send(ws, Message.from_typed(
            type=MessageType.SESSION_LIST_RESULT,
            payload=SessionListResultPayload(sessions=sessions, cli=cli_name),
        ))

    async def handle_chat_cancel(self, client_id, ws, msg):
        """Cancel the current AI operation.

        Follows the CancellableRequest.cancel pattern:
        1. Call ACP session/cancel on the active CLI.
        2. Resolve all pending permission futures as cancelled (ACP spec requirement).
        3. Send chat.done to the App to signal the turn is over.
        4. Clear the StreamReplay buffer (cancelled turn has no useful output).

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``cli``.
        """
        try:
            payload = msg.typed_payload(ChatCancelPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ chat.cancel payload 校验失败: client={client_id}, {e}")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=str(e)),
            ))
            return

        cli_name = payload.cli or self.config.default_cli
        logger.info(f"⏹ 用户取消: [{cli_name}]")

        # 1. ACP session/cancel
        await self.cli_manager.cancel_current(cli_name, client_id)

        # 2. Resolve all pending permission futures as cancelled (ACP spec)
        for req_id, future in list(self.server._permission_futures.items()):
            if not future.done():
                future.set_result({"outcome": {"outcome": "cancelled"}})
                logger.debug(f"Permission cancelled: {req_id}")

        # 3. Notify the App that the current turn has ended
        await self.send(ws, Message.from_typed(
            type=MessageType.CHAT_DONE,
            payload=ChatDonePayload(cancelled=True),
        ))

        # 4. Clear replay buffer — cancelled turn output is not useful
        replay = self.server.get_stream_replay(client_id)
        if replay:
            replay.clear()

    async def handle_chat_replay(self, client_id, ws, msg):
        """Replay buffered stream chunks to a reconnected client.

        Called by the App after reconnecting when the Agent indicates
        that a streaming turn is active or recently finished. Sends
        all buffered chunks after the given sequence number, followed
        by chat.done if the turn has already completed.

        Note: the entire replay is sent as a single JSON message.
        With max_chunks=500 and ~1KB/chunk, this is ~500KB — well
        within the WebSocket max_message_size (10MB). If future use
        cases require larger buffers, consider paginated replay.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with optional ``after_seq``.
        """
        try:
            payload = msg.typed_payload(ChatReplayPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ chat.replay payload 校验失败: client={client_id}, {e}")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_ERROR,
                payload=ChatErrorPayload(error=str(e)),
            ))
            return

        after_seq = payload.after_seq
        replay = self.server.get_stream_replay(client_id)

        if not replay:
            logger.debug(f"chat.replay: 无 replay buffer: client={client_id[:8]}...")
            await self.send(ws, Message.from_typed(
                type=MessageType.CHAT_REPLAY_RESULT,
                payload=ChatReplayResultPayload(chunks=[], streaming=False, seq=0),
            ))
            return

        chunks = replay.get_replay(after_seq=after_seq)
        logger.info(
            f"chat.replay: 补发 {len(chunks)} chunks "
            f"(after_seq={after_seq}, active={replay.is_active}, "
            f"finished={replay.is_finished}): client={client_id[:8]}..."
        )

        # Send replayed chunks as a batch
        await self.send(ws, Message.from_typed(
            type=MessageType.CHAT_REPLAY_RESULT,
            payload=ChatReplayResultPayload(
                chunks=chunks,
                streaming=replay.is_active,
                seq=replay.seq,
            ),
        ))
