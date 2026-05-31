"""
ACP Client implementation (the "switchboard operator").

Receives callback requests from the ACP CLI process and delegates them
to the appropriate service. Does NOT contain business logic — only routing.

ACP spec requires the Client to implement:
  - session_update: receive streaming events → delegate to ACPEventConverter
  - request_permission: permission management → delegate to EventBus
  - read_text_file / write_text_file: filesystem → direct I/O (with snapshot)
  - terminal/*: terminal operations → subprocess management
"""

from __future__ import annotations

import asyncio
import os
from pathlib import Path
from typing import Any, Optional

from loguru import logger

from .base import AgentEvent, AgentEventType


class ACPEventCollector:
    """Thread-safe async event queue consumed by ACPProvider.prompt().

    Events are put by ACPClientImpl.session_update() and consumed by
    ACPProvider._consume_events(). The queue is cleared before each
    new prompt or session load to avoid stale events.
    """

    def __init__(self):
        self.events: asyncio.Queue[AgentEvent] = asyncio.Queue()

    def put(self, event: AgentEvent):
        self.events.put_nowait(event)

    def clear(self):
        while not self.events.empty():
            try:
                self.events.get_nowait()
            except asyncio.QueueEmpty:
                break


class ACPClientImpl:
    """ACP Client switchboard — routes CLI callbacks to handlers.

    Each ACP callback (session_update, request_permission, read_text_file, etc.)
    is routed here by the SDK, then delegated to the appropriate handler.

    Args:
        collector: Event queue for streaming events to ACPProvider.
        event_bus: Application EventBus for permission requests.
    """

    def __init__(self, collector: ACPEventCollector, event_bus=None):
        self._collector = collector
        self._event_bus = event_bus
        self._work_dir = ""
        self._permission_policy = "auto_approve"
        # 缓存最近的 ToolCallStart 的 raw_input（request_permission 时用）
        self._last_tool_raw_input: dict | None = None

        # 事件转换器
        from .acp_converter import ACPEventConverter
        self._converter = ACPEventConverter()

        # 文件快照存储（每次写入前保存旧内容，用于全文 diff）
        from ..services.snapshot_store import SnapshotStore
        self._snapshots = SnapshotStore()

        # 终端管理（ACP 终端，不是用户终端）
        self._terminals: dict[str, asyncio.subprocess.Process] = {}
        self._terminal_outputs: dict[str, list[str]] = {}
        self._terminal_counter = 0

        # Log throttle: suppress repeated same-type event logs
        self._last_event_type: str = ""
        self._repeat_count: int = 0

    def set_work_dir(self, cwd: str):
        self._work_dir = cwd
        logger.debug(f"ACP Client 工作目录: {cwd}")

    # ══════════════════════════════════════════════════════════
    # 事件接收（CLI → Client）
    # ══════════════════════════════════════════════════════════

    async def session_update(self, session_id: str, update: Any, **kwargs):
        """Receive a streaming event from the ACP CLI and route it.

        Converts the raw ACP update to an AgentEvent via ACPEventConverter,
        then puts it into the collector queue. For "edit" kind tool calls,
        also captures before/after file snapshots to construct full diffs
        (some ACP CLIs don't send diff content or call write_text_file).

        Args:
            session_id: Active session ID.
            update: ACP SDK update object (AgentMessageChunk, ToolCallStart, etc.).
        """
        # 缓存 raw_input（ToolCallStart 时）
        raw_input = getattr(update, "raw_input", None)
        if raw_input and isinstance(raw_input, dict):
            self._last_tool_raw_input = raw_input

        # 对 edit 类型：ToolCallStart 时保存 before 快照
        kind = str(getattr(update, "kind", "") or "")
        status = str(getattr(update, "status", "") or "")
        from acp.helpers import ToolCallStart, ToolCallProgress

        if isinstance(update, ToolCallStart) and kind == "edit" and raw_input:
            path = raw_input.get("path", "")
            if path:
                resolved = self._resolve_path(path)
                try:
                    old_content = Path(resolved).read_text(encoding="utf-8")
                except Exception:
                    old_content = ""
                self._snapshots.capture_before_edit(path, old_content)
                logger.debug(f"Edit before 快照: {path} ({len(old_content)} chars)")

        event = self._converter.convert(update)
        if event:
            # Throttle repeated same-type events (e.g. text_chunk floods)
            # to keep terminal output readable. Log first occurrence,
            # then a summary every 50 repeats, and a final count on type change.
            etype = event.type.value
            if etype == self._last_event_type:
                self._repeat_count += 1
                if self._repeat_count == 50:
                    logger.debug(f"ACP event → collector: type={etype} (×{self._repeat_count}, 后续省略...)")
            else:
                # Type changed — flush previous repeat count if any
                if self._repeat_count > 1:
                    logger.debug(f"ACP event → collector: type={self._last_event_type} 连续 {self._repeat_count} 次")
                logger.debug(f"ACP event → collector: type={etype}")
                self._last_event_type = etype
                self._repeat_count = 1
            self._collector.put(event)

        # 对 edit 类型：ToolCallProgress(completed) 时读 after，构建完整 diff
        if isinstance(update, ToolCallProgress) and kind == "edit" and status in ("completed", "ToolCallStatus.COMPLETED"):
            # 从 raw_input 或 locations 提取路径
            ri = getattr(update, "raw_input", None) or {}
            path = ri.get("path", "") if isinstance(ri, dict) else ""
            if not path:
                locs = getattr(update, "locations", None) or []
                if locs:
                    first = locs[0] if isinstance(locs, list) else locs
                    path = getattr(first, "path", "")
            if path:
                resolved = self._resolve_path(path)
                try:
                    new_content = Path(resolved).read_text(encoding="utf-8")
                except Exception:
                    new_content = ""
                old_content = self._snapshots.get_edit_baseline(path) or ""
                # 只有当 converter 没有产生 FILE_EDIT（content 为 None 的情况）才注入
                if not event or event.type != AgentEventType.FILE_EDIT:
                    self._collector.put(AgentEvent(
                        type=AgentEventType.FILE_EDIT,
                        data={
                            "path": path,
                            "full_old": old_content,
                            "full_new": new_content,
                        },
                    ))
                    logger.debug(f"磁盘 diff 注入: {path}, old={len(old_content)}, new={len(new_content)}")

    # ══════════════════════════════════════════════════════════
    # 权限管理（CLI → Client → EventBus → 手机 App）
    # ══════════════════════════════════════════════════════════

    async def request_permission(self, options: Any, session_id: str, tool_call: Any, **kwargs) -> dict:
        """Handle ACP permission request: classify and auto-approve or ask user.

        Follows the IDE's resolvePermissionRequest pattern:
        1. auto_approve policy → approve everything.
        2. ask_user policy → run through approval_classifier first:
           - Safe read/search operations → auto-approve.
           - Dangerous write/exec operations → push to phone via EventBus.

        Args:
            options: ACP permission options (list of allowed actions).
            session_id: Active session ID.
            tool_call: ACP tool call object with name, kind, raw_input, etc.

        Returns:
            Dict with "outcome" key: {"outcome": "selected", "optionId": "..."} or
            {"outcome": "cancelled"}.
        """
        tool_name = getattr(tool_call, "title", getattr(tool_call, "name", "unknown"))
        tool_kind = str(getattr(tool_call, "kind", "") or "")
        description = self._extract_permission_description(tool_call)
        option_list = self._parse_permission_options(options)

        logger.info(f"ACP 权限请求: tool={tool_name}, kind={tool_kind}, desc={description[:80]}")

        # 策略 1: auto_approve → 全部自动批准
        if self._permission_policy == "auto_approve":
            option_id = option_list[0]["id"] if option_list else "allow_once"
            logger.debug(f"权限自动批准 (auto_approve 策略): {tool_name}")
            return {"outcome": {"outcome": "selected", "optionId": option_id}}

        # 策略 2: ask_user → 先过分类器（参照 IDE 的 classifyAcpToolApproval）
        from .approval_classifier import classify_tool_approval
        classification = classify_tool_approval(tool_call, cwd=self._work_dir)
        logger.debug(
            f"权限分类: tool={classification.tool_name}, "
            f"class={classification.approval_class}, "
            f"auto={classification.auto_approve}"
        )

        if classification.auto_approve:
            option_id = option_list[0]["id"] if option_list else "allow_once"
            logger.info(f"权限自动批准 (分类器: {classification.approval_class}): {tool_name}")
            return {"outcome": {"outcome": "selected", "optionId": option_id}}

        # 通过 EventBus 推送到手机
        if self._event_bus:
            from ..core.events import Events
            try:
                result = await self._event_bus.emit_and_wait(
                    Events.PERMISSION_REQUEST,
                    {
                        "session_id": session_id,
                        "tool_name": tool_name,
                        "tool_kind": tool_kind,
                        "description": description,
                        "options": option_list,
                    },
                    timeout=120,
                )
                if result:
                    return result
                logger.warning("权限请求无回复，自动拒绝")
                return {"outcome": {"outcome": "cancelled"}}
            except Exception as e:
                logger.error(f"权限请求出错: {e}")
                return {"outcome": {"outcome": "cancelled"}}

        # 没有 EventBus，自动批准
        option_id = option_list[0]["id"] if option_list else "allow_once"
        return {"outcome": {"outcome": "selected", "optionId": option_id}}

    # ══════════════════════════════════════════════════════════
    # 文件系统（CLI → Client）
    # ══════════════════════════════════════════════════════════

    async def read_text_file(self, path: str, **kwargs) -> dict:
        resolved = self._resolve_path(path)
        logger.debug(f"ACP fs/read: {resolved}")
        try:
            content = Path(resolved).read_text(encoding="utf-8")
            return {"content": content}
        except UnicodeDecodeError:
            return {"content": Path(resolved).read_text(encoding="latin-1")}
        except FileNotFoundError:
            return {"content": "", "error": f"File not found: {path}"}
        except Exception as e:
            return {"content": "", "error": str(e)}

    async def write_text_file(self, path: str, content: str, **kwargs) -> dict:
        """ACP write file callback.

        Captures a before-snapshot, writes the file, then injects a FILE_EDIT
        event into the collector queue so the full diff flows through the same
        path as chat.stream events. Inspired by VS Code's
        ChatEditingModifiedDocumentEntry.initialContent pattern.

        Args:
            path: File path (relative to work_dir or absolute).
            content: New file content to write.

        Returns:
            Empty dict on success, or {"error": "..."} on failure.
        """
        resolved = self._resolve_path(path)
        logger.debug(f"ACP fs/write: {resolved} ({len(content)} chars)")
        try:
            # 写入前保存快照（用于全文 diff 和回滚）
            old_content = ""
            if Path(resolved).exists():
                try:
                    old_content = Path(resolved).read_text(encoding="utf-8")
                except Exception:
                    old_content = ""
            self._snapshots.capture_before_edit(path, old_content)

            # 写入新内容
            Path(resolved).parent.mkdir(parents=True, exist_ok=True)
            Path(resolved).write_text(content, encoding="utf-8")

            # 直接往 collector 注入 FILE_EDIT 事件（和 chat.stream 走同一条路径）
            # path 参数就是 ACP CLI 传入的路径，和 ToolCallStart 的 locations 一致
            from .base import AgentEvent, AgentEventType
            self._collector.put(AgentEvent(
                type=AgentEventType.FILE_EDIT,
                data={
                    "path": path,
                    "full_old": old_content,
                    "full_new": content,
                    "description": f"Write: {path}",
                },
            ))
            logger.debug(f"FILE_EDIT 注入 collector: {path}, old={len(old_content)}, new={len(content)}")

            return {}
        except Exception as e:
            return {"error": str(e)}

    # ══════════════════════════════════════════════════════════
    # 终端（CLI → Client）
    # ══════════════════════════════════════════════════════════

    async def create_terminal(self, command: str, **kwargs) -> dict:
        self._terminal_counter += 1
        tid = f"term_{self._terminal_counter}"
        logger.debug(f"ACP terminal/create: {tid}, cmd={command[:80]}")
        try:
            proc = await asyncio.create_subprocess_shell(
                command, cwd=self._work_dir or None,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                stdin=asyncio.subprocess.PIPE,
            )
            self._terminals[tid] = proc
            self._terminal_outputs[tid] = []
            asyncio.create_task(self._read_terminal(tid, proc))
            return {"terminal_id": tid}
        except Exception as e:
            return {"terminal_id": tid, "error": str(e)}

    async def terminal_output(self, terminal_id: str, **kwargs) -> dict:
        lines = self._terminal_outputs.get(terminal_id, [])
        return {"output": "\n".join(lines)}

    async def wait_for_terminal_exit(self, terminal_id: str, **kwargs) -> dict:
        proc = self._terminals.get(terminal_id)
        if not proc:
            return {"exit_code": -1, "error": "terminal not found"}
        try:
            code = await asyncio.wait_for(proc.wait(), timeout=120)
            return {"exit_code": code}
        except asyncio.TimeoutError:
            return {"exit_code": -1, "error": "timeout"}

    async def kill_terminal(self, terminal_id: str, **kwargs) -> dict:
        proc = self._terminals.pop(terminal_id, None)
        if proc:
            from ..utils.process import kill_process_tree_sync
            kill_process_tree_sync(proc.pid)
        return {}

    async def release_terminal(self, terminal_id: str, **kwargs) -> dict:
        self._terminals.pop(terminal_id, None)
        self._terminal_outputs.pop(terminal_id, None)
        return {}

    # ══════════════════════════════════════════════════════════
    # 内部工具方法
    # ══════════════════════════════════════════════════════════

    async def _read_terminal(self, tid: str, proc: asyncio.subprocess.Process):
        try:
            assert proc.stdout is not None
            while True:
                line = await proc.stdout.readline()
                if not line:
                    break
                text = line.decode("utf-8", errors="replace").rstrip("\n\r")
                self._terminal_outputs.setdefault(tid, []).append(text)
                # 通过 EventBus 实时推送终端输出到 App
                if self._event_bus:
                    await self._event_bus.emit("terminal.output", {
                        "terminal_id": tid,
                        "text": text,
                    })
        except Exception as e:
            logger.debug(f"ACP 终端读取结束: {tid} - {e}")

    def _resolve_path(self, path: str) -> str:
        if os.path.isabs(path):
            return path
        if self._work_dir:
            return os.path.join(self._work_dir, path)
        return os.path.abspath(path)

    def _extract_permission_description(self, tool_call: Any) -> str:
        """Extract a human-readable description from a tool_call for permission UI.

        Tries multiple sources: raw_input (command/path), cached ToolCallStart
        raw_input, content attributes, and title prefix.

        Args:
            tool_call: ACP tool call object.

        Returns:
            Description string (may be empty if nothing extractable).
        """
        raw_input = getattr(tool_call, "raw_input", None)
        content = getattr(tool_call, "content", None)
        title = getattr(tool_call, "title", "")

        # 从 raw_input 提取
        if raw_input and isinstance(raw_input, dict):
            if "command" in raw_input:
                return raw_input["command"]
            if "path" in raw_input:
                return f"Edit: {raw_input['path']}"
            return str(raw_input)[:200]

        # 从缓存的 ToolCallStart raw_input 提取
        if self._last_tool_raw_input:
            cached = self._last_tool_raw_input
            if "command" in cached:
                return cached["command"]
            if "path" in cached:
                return f"Edit: {cached['path']}"

        # 从 content 提取
        if content:
            if hasattr(content, "command"):
                return getattr(content, "command", "")
            if hasattr(content, "text"):
                return getattr(content, "text", "")[:200]

        # 从 title 提取
        if title.startswith("Running: "):
            return title[9:]

        return ""

    @staticmethod
    def _parse_permission_options(options: Any) -> list[dict]:
        """Parse ACP permission options into a list of dicts for frontend rendering.

        Args:
            options: List of ACP option objects with option_id, name, kind.

        Returns:
            List of dicts with id, name, kind keys.
        """
        if not options or not isinstance(options, list):
            return []
        return [
            {
                "id": getattr(opt, "option_id", getattr(opt, "id", "")),
                "name": getattr(opt, "name", ""),
                "kind": str(getattr(opt, "kind", "")),
            }
            for opt in options
        ]
