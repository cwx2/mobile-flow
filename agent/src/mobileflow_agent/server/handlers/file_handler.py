"""File operations and diff management handler.

Module: server/handlers/
Responsibility:
    Handle file.tree, file.read, file.write, file.search, file.create,
    file.rename, file.delete, diff.apply, and diff.reject messages.
"""

from __future__ import annotations

import asyncio

from loguru import logger

from mobileflow_protocol.envelope import Message
from mobileflow_protocol.errors import PayloadValidationError
from mobileflow_protocol.payloads.diff import DiffApplyPayload, DiffRejectPayload
from mobileflow_protocol.payloads.file import (
    FileCreatePayload,
    FileCreateResultPayload,
    FileDeletePayload,
    FileDeleteResultPayload,
    FileReadPayload,
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
from mobileflow_protocol.types import MessageType

from .base import BaseHandler


class FileHandler(BaseHandler):
    """Handles file CRUD operations, streaming search, and diff accept/reject.

    Diff operations follow the VS Code ChatEditingTextModelChangeService
    pattern with three snapshot levels: editBaseline, promptBaseline, and
    initialContent.
    """

    def __init__(self, server):
        super().__init__(server)
        # Per-client cancel event for search cancellation (instance variable,
        # not class variable, to avoid shared mutable state across instances)
        self._search_cancels: dict[str, asyncio.Event] = {}

    async def handle_file_tree(self, client_id, ws, msg):
        """Return the directory tree starting at the requested path.

        Uses cached tree data when available. Cache is invalidated
        automatically by RefreshScheduler on file create/delete events.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path`` and ``depth`` in the payload.
        """
        try:
            payload = msg.typed_payload(FileTreePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ file.tree payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        tree = self.file_service.get_tree_cached(payload.path, payload.depth)
        await self.send(ws, Message.from_typed(
            type=MessageType.FILE_TREE_RESULT,
            payload=FileTreeResultPayload(
                data=[n.model_dump() for n in tree],
                req_path=payload.path,
            ),
        ))

    async def handle_file_read(self, client_id, ws, msg):
        """Read a single file and return its content.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path`` in the payload.
        """
        try:
            payload = msg.typed_payload(FileReadPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ file.read payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        path = self._normalize_file_path(payload.path)
        logger.debug(f"file.read: path={path}")
        result = self.file_service.read_file(path)
        await self.send(ws, Message(type=MessageType.FILE_READ_RESULT, payload=result.model_dump()))

    async def handle_file_write(self, client_id, ws, msg):
        """Write content to a file.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path`` and ``content`` in the payload.
        """
        try:
            payload = msg.typed_payload(FileWritePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ file.write payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        logger.debug(f"file.write: path={payload.path}, size={len(payload.content)}")
        success = self.file_service.write_file(payload.path, payload.content)
        await self.send(ws, Message.from_typed(
            type=MessageType.FILE_WRITE_RESULT,
            payload=FileWriteResultPayload(success=success, path=payload.path),
        ))

    async def handle_file_search(self, client_id, ws, msg):
        """Perform a streaming file search, pushing results in batches.

        Follows the VS Code ``progress.report()`` pattern: results are sent
        incrementally as they are found, with a final complete result at the end.
        A new search automatically cancels any in-progress search for the same
        client.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``query``, ``search_content``,
                ``is_regex``, ``case_sensitive``, and ``whole_word`` flags.
        """
        try:
            payload = msg.typed_payload(FileSearchPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ file.search payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        logger.debug(f"file.search: query={payload.query!r}, content={payload.search_content}, regex={payload.is_regex}")

        # Cancel any previous search for this client
        old_cancel = self._search_cancels.get(client_id)
        if old_cancel:
            old_cancel.set()

        # Create a new cancel event for this search
        cancel_event = asyncio.Event()
        self._search_cancels[client_id] = cancel_event

        # Register cancel event with client scope for auto-cleanup on disconnect
        scope = self.server._scopes.get(client_id)
        if scope:
            scope.on_dispose(lambda: cancel_event.set())

        all_results: list[dict] = []

        # Streaming callback: push each batch to the App as it arrives
        async def on_batch(batch: list[dict]):
            if cancel_event.is_set():
                return
            all_results.extend(batch)
            await self.send(ws, Message.from_typed(
                type=MessageType.FILE_SEARCH_STREAM,
                payload=FileSearchStreamPayload(results=batch, total=len(all_results)),
            ))

        # Execute the search (streaming or one-shot)
        results = await self.file_service.search(
            payload.query, payload.search_content, cancel_event, on_batch=on_batch,
            is_regex=payload.is_regex, case_sensitive=payload.case_sensitive,
            whole_word=payload.whole_word,
        )

        # Do not send the completion signal if the search was cancelled
        if cancel_event.is_set():
            return

        # Cleanup
        if self._search_cancels.get(client_id) is cancel_event:
            del self._search_cancels[client_id]
        logger.info(f"file.search 完成: query={payload.query!r}, results={len(results)}")
        await self.send(ws, Message.from_typed(
            type=MessageType.FILE_SEARCH_RESULT,
            payload=FileSearchResultPayload(results=results),
        ))

    async def handle_file_create(self, client_id, ws, msg):
        """Create a new file or directory.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path``, ``name``, and ``type``
                (``"file"`` or ``"directory"``).
        """
        try:
            payload = msg.typed_payload(FileCreatePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ file.create payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        result = self.file_service.create_file(payload.path, payload.name, payload.type)
        await self.send(ws, Message(type=MessageType.FILE_CREATE_RESULT, payload=result))

    async def handle_file_rename(self, client_id, ws, msg):
        """Rename a file or directory.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path`` and ``new_name``.
        """
        try:
            payload = msg.typed_payload(FileRenamePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ file.rename payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        result = self.file_service.rename_file(payload.path, payload.new_name)
        await self.send(ws, Message(type=MessageType.FILE_RENAME_RESULT, payload=result))

    async def handle_file_delete(self, client_id, ws, msg):
        """Delete a file or directory.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``path``.
        """
        try:
            payload = msg.typed_payload(FileDeletePayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ file.delete payload 校验失败: client={client_id}, {e}")
            await self.send_error(ws, f"Invalid payload: {e}")
            return

        logger.debug(f"file.delete: path={payload.path}")
        result = self.file_service.delete_file(payload.path)
        await self.send(ws, Message(type=MessageType.FILE_DELETE_RESULT, payload=result))

    async def handle_diff_apply(self, client_id, ws, msg):
        """Accept a diff: confirm the modification made by the AI CLI.

        The file has already been written by the CLI.  This updates the
        ``promptBaseline`` to the current on-disk content so that a future
        Reject uses the post-accept state as its baseline.  ``initialContent``
        is preserved for Undo All.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``file_path``.
        """
        try:
            payload = msg.typed_payload(DiffApplyPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ diff.apply payload 校验失败: client={client_id}, {e}")
            return

        logger.info(f"✅ Accept: {payload.file_path}")
        store = self._get_snapshot_store()
        if store:
            # Read current disk content and update promptBaseline
            from pathlib import Path as P
            resolved = P(self.config.work_dir) / payload.file_path
            try:
                current = resolved.read_text(encoding="utf-8")
                entry = store.get_file_history(payload.file_path)
                if entry:
                    entry.prompt_baseline = current
                    entry.edit_baseline = current
            except Exception:
                pass

    async def handle_diff_reject(self, client_id, ws, msg):
        """Reject a diff: roll back to the pre-edit content (editBaseline).

        Follows the VS Code ``ChatEditingTextModelChangeService.undo()`` pattern.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``file_path``.
        """
        try:
            payload = msg.typed_payload(DiffRejectPayload)
        except PayloadValidationError as e:
            logger.warning(f"⚠️ diff.reject payload 校验失败: client={client_id}, {e}")
            return

        logger.info(f"❌ Reject: {payload.file_path}")
        store = self._get_snapshot_store()
        if not store:
            logger.warning("SnapshotStore 不可用")
            return
        baseline = store.get_edit_baseline(payload.file_path)
        if baseline is None:
            logger.warning(f"没有 editBaseline: {payload.file_path}")
            return
        self._write_file(payload.file_path, baseline, "reject")

    async def handle_diff_undo_prompt(self, client_id, ws, msg):
        """Undo the entire prompt: roll back to the pre-prompt content (promptBaseline).

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``file_path``.
        """
        file_path = msg.payload.get("file_path", "")
        logger.info(f"⏪ Undo Prompt: {file_path}")
        store = self._get_snapshot_store()
        if not store:
            return
        baseline = store.get_prompt_baseline(file_path)
        if baseline is None:
            logger.warning(f"没有 promptBaseline: {file_path}")
            return
        self._write_file(file_path, baseline, "undo_prompt")

    async def handle_diff_undo_all(self, client_id, ws, msg):
        """Undo all AI changes: restore the file to its original content (initialContent).

        Follows the VS Code ``initialContent`` / ``resetToInitialContent`` pattern.
        Clears all snapshots for the file after restoration.

        Args:
            client_id: Identifier of the requesting client.
            ws: The client's WebSocket connection.
            msg: Protocol message with ``file_path``.
        """
        file_path = msg.payload.get("file_path", "")
        logger.info(f"⏮️ Undo All: {file_path}")
        store = self._get_snapshot_store()
        if not store:
            return
        initial = store.get_initial_content(file_path)
        if initial is None:
            logger.warning(f"没有 initialContent: {file_path}")
            return
        self._write_file(file_path, initial, "undo_all")
        # Clear all snapshots for this file (restore to pre-AI state)
        store.clear_file(file_path)

    def _write_file(self, file_path: str, content: str, action: str):
        """Write content to a file on disk.

        Args:
            file_path: Relative path within the working directory.
            content: File content to write.
            action: Label for logging (e.g. "reject", "undo_all").
        """
        from pathlib import Path as P
        resolved = P(self.config.work_dir) / file_path
        try:
            resolved.write_text(content, encoding="utf-8")
            logger.info(f"已{action}: {file_path} ({len(content)} chars)")
        except Exception as e:
            logger.error(f"{action}失败: {file_path} — {e}")

    def _get_snapshot_store(self):
        """Retrieve the SnapshotStore from the active CLIManager provider.

        Returns:
            The SnapshotStore instance, or None if unavailable.
        """
        try:
            for provider in self.cli_manager._sessions.values():
                if hasattr(provider, '_client_impl') and hasattr(provider._client_impl, '_snapshots'):
                    return provider._client_impl._snapshots
        except Exception:
            pass
        return None

    def _normalize_file_path(self, path: str) -> str:
        """Normalize a file path, converting WSL absolute paths to relative paths.

        For WSL paths (``/mnt/...``), converts to Windows format first.
        For Windows absolute paths, strips the work_dir prefix to get a
        relative path. Relative paths are returned as-is (they will be
        resolved by FileService._resolve_path against the project root).

        Args:
            path: Raw file path from the App (relative or absolute).

        Returns:
            A relative path within the working directory, using forward slashes.
        """
        if not path:
            return path
        from ...utils.path import wsl_to_win
        if path.startswith("/mnt/"):
            path = wsl_to_win(path)
        from pathlib import Path as P
        p = P(path)
        # Only normalize absolute paths — relative paths are already correct
        # and should NOT be resolved against CWD (which may differ from work_dir)
        if not p.is_absolute():
            return path.replace("\\", "/")
        try:
            work_dir = P(self.config.work_dir).resolve()
            return str(p.resolve().relative_to(work_dir)).replace("\\", "/")
        except (ValueError, OSError):
            return path
