"""
ACP Event Converter

Converts ACP SDK session/update objects directly to internal AgentEvent.
Uses official ACP SDK Pydantic models — no custom parsing layer needed.

Called by: acp_client.py session_update callback
Depends on: acp SDK (agent-client-protocol), base.py (AgentEvent)
"""

from __future__ import annotations

import json
from typing import Any, Optional

from loguru import logger

from .base import AgentEvent, AgentEventType
from ..utils.strings import safe_str


def serialize_config_options(opts_raw: list) -> list[dict]:
    """Serialize ACP SessionConfigOption SDK objects to plain dicts.

    Handles both SessionConfigOptionSelect (type="select") and
    SessionConfigOptionBoolean (type="boolean"). For select options,
    flattens grouped options (SessionConfigSelectGroup) into a single
    list so the App doesn't need to handle nested groups.

    Per ACP spec, each config option has: id, name, type, currentValue,
    and optionally description, category, options (for select type).

    Args:
        opts_raw: List of ACP SDK config option objects
            (SessionConfigOptionSelect | SessionConfigOptionBoolean).

    Returns:
        List of plain dicts ready for JSON serialization to the App.
    """
    results = []
    for o in opts_raw:
        opt_type = safe_str(getattr(o, "type", "select"))
        entry: dict = {
            "id": safe_str(getattr(o, "id", "")),
            "name": safe_str(getattr(o, "name", "")),
            "type": opt_type,
            "current_value": getattr(o, "current_value", getattr(o, "value", "")),
        }
        # Optional fields — only include when present
        desc = getattr(o, "description", None)
        if desc:
            entry["description"] = safe_str(desc)
        cat = getattr(o, "category", None)
        if cat:
            entry["category"] = safe_str(cat)

        # For select type: flatten options (may be flat list or grouped)
        if opt_type == "select":
            raw_options = getattr(o, "options", []) or []
            flat_options: list[dict] = []
            for item in raw_options:
                # SessionConfigSelectGroup has a nested `options` list
                nested = getattr(item, "options", None)
                if nested is not None:
                    # Grouped options — flatten into a single list
                    for sub in nested:
                        flat_options.append({
                            "value": safe_str(getattr(sub, "value", "")),
                            "name": safe_str(getattr(sub, "name", "")),
                            **({"description": safe_str(getattr(sub, "description", ""))}
                               if getattr(sub, "description", None) else {}),
                        })
                else:
                    # Flat SessionConfigSelectOption
                    flat_options.append({
                        "value": safe_str(getattr(item, "value", "")),
                        "name": safe_str(getattr(item, "name", "")),
                        **({"description": safe_str(getattr(item, "description", ""))}
                           if getattr(item, "description", None) else {}),
                    })
            entry["options"] = flat_options

        # For boolean type: ensure current_value is a proper bool
        if opt_type == "boolean":
            cv = getattr(o, "current_value", False)
            entry["current_value"] = bool(cv) if not isinstance(cv, bool) else cv

        results.append(entry)
    return results


class ACPEventConverter:
    """Convert ACP SessionUpdate SDK objects to internal AgentEvent.

    Handles all ACP update types: text chunks, thoughts, tool calls,
    plan updates, mode changes, config updates, session info, etc.
    """

    def convert(self, update: Any) -> Optional[AgentEvent]:
        """Convert a single ACP session/update to an AgentEvent.

        Args:
            update: ACP SDK update object (AgentMessageChunk, ToolCallStart, etc.).

        Returns:
            AgentEvent, or None if the update type is not recognized or has no content.
        """
        update_type = getattr(update, "session_update", None) or type(update).__name__

        try:
            # ── Text message ──
            if update_type in ("agent_message_chunk", "AgentMessageChunk"):
                content = getattr(update, "content", None)
                text = safe_str(getattr(content, "text", "")) if content else ""
                if text:
                    return AgentEvent(type=AgentEventType.TEXT_CHUNK, data={"text": text})
                return None

            # ── User message (needed for session replay) ──
            if update_type in ("user_message_chunk", "UserMessageChunk"):
                content = getattr(update, "content", None)
                text = safe_str(getattr(content, "text", "")) if content else ""
                if text:
                    return AgentEvent(type=AgentEventType.USER_MESSAGE, data={"text": text})
                return None

            # ── AI thought ──
            if update_type in ("agent_thought_chunk", "AgentThoughtChunk"):
                content = getattr(update, "content", None)
                text = safe_str(getattr(content, "text", "")) if content else ""
                if text:
                    return AgentEvent(type=AgentEventType.THOUGHT_CHUNK, data={"text": text})
                return None

            # ── Tool call start ──
            if update_type in ("tool_call", "ToolCallStart"):
                return self._convert_tool_call(update, is_update=False)

            # ── Tool call progress/result ──
            if update_type in ("tool_call_update", "ToolCallProgress"):
                return self._convert_tool_call(update, is_update=True)

            # ── Plan update ──
            if update_type in ("plan_update", "plan", "AgentPlanUpdate"):
                entries_raw = getattr(update, "entries", []) or []
                entries = [
                    {
                        "title": safe_str(getattr(e, "content", "")),
                        "status": safe_str(getattr(e, "status", "")),
                        "priority": safe_str(getattr(e, "priority", "")),
                    }
                    for e in entries_raw
                ]
                return AgentEvent(type=AgentEventType.PLAN_UPDATE, data={"entries": entries})

            # ── Available commands ──
            if update_type in ("available_commands_update", "AvailableCommandsUpdate"):
                cmds_raw = getattr(update, "available_commands", []) or []
                commands = [
                    {"name": safe_str(getattr(c, "name", "")), "description": safe_str(getattr(c, "description", ""))}
                    for c in cmds_raw
                ]
                return AgentEvent(type=AgentEventType.COMMANDS_AVAILABLE, data={"commands": commands})

            # ── Mode change ──
            if update_type in ("current_mode_update", "CurrentModeUpdate"):
                mode_id = safe_str(getattr(update, "mode_id", getattr(update, "modeId", "")))
                return AgentEvent(type=AgentEventType.MODE_CHANGE, data={"mode_id": mode_id})

            # ── Session info ──
            if update_type in ("session_info_update", "SessionInfoUpdate"):
                title = safe_str(getattr(update, "title", ""))
                updated_at = safe_str(getattr(update, "updated_at", ""))
                ctx_usage = getattr(update, "context_usage_percentage", 0) or 0.0
                logger.debug(f"session_info: title={title!r}, updated_at={updated_at!r}, context_usage={ctx_usage}")
                return AgentEvent(type=AgentEventType.SESSION_INFO, data={
                    "title": title, "updated_at": updated_at, "context_usage": ctx_usage,
                })

            # ── Config option update ──
            if update_type in ("config_option_update", "ConfigOptionUpdate"):
                opts_raw = getattr(update, "config_options", []) or []
                options = serialize_config_options(opts_raw)
                return AgentEvent(type=AgentEventType.CONFIG_UPDATE, data={"options": options})

            logger.debug(f"ACP 未处理 update: {update_type}")
            return None

        except Exception as e:
            logger.error(f"ACP 转换出错: {update_type} — {e}")
            return None

    def _convert_tool_call(self, update: Any, is_update: bool) -> AgentEvent:
        """Convert SDK ToolCallStart/ToolCallProgress to AgentEvent.

        Handles content blocks (diff, terminal, text/image/resource), locations,
        raw_input/raw_output serialization, and status normalization.

        Args:
            update: ACP SDK ToolCallStart or ToolCallProgress object.
            is_update: True for progress/result, False for initial start.

        Returns:
            TOOL_CALL_START, TOOL_CALL_UPDATE, or FILE_EDIT event.
        """
        tool_call_id = safe_str(getattr(update, "tool_call_id", ""))
        title = safe_str(getattr(update, "title", ""))
        kind = safe_str(getattr(update, "kind", ""))
        status = safe_str(getattr(update, "status", ""))
        raw_input = getattr(update, "raw_input", None)
        raw_output = getattr(update, "raw_output", None)
        content_list = getattr(update, "content", []) or []
        locations_raw = getattr(update, "locations", []) or []

        # Convert Pydantic models to plain dicts
        if raw_input and hasattr(raw_input, "model_dump"):
            raw_input = raw_input.model_dump()
        elif raw_input and not isinstance(raw_input, dict):
            try:
                raw_input = dict(raw_input)
            except Exception:
                raw_input = {}
        if raw_output and hasattr(raw_output, "model_dump"):
            raw_output = raw_output.model_dump()
        elif raw_output and not isinstance(raw_output, dict):
            try:
                raw_output = dict(raw_output)
            except Exception:
                raw_output = {}

        # Log (truncated)
        log_ri = json.dumps(raw_input, ensure_ascii=False, default=str)[:300] if raw_input else ""
        logger.info(f"tool_call {'update' if is_update else 'start'}: id={tool_call_id}, title={title}, status={status}, ri={log_ri}")

        # Parse locations
        locations = []
        for loc in locations_raw:
            path = safe_str(getattr(loc, "path", ""))
            line = getattr(loc, "line", None)
            loc_dict: dict = {"path": path}
            if line is not None:
                loc_dict["line"] = line
            locations.append(loc_dict)

        file_path = locations[0]["path"] if locations else ""
        if not file_path and isinstance(raw_input, dict):
            file_path = raw_input.get("path", "")

        # Parse content blocks from SDK ToolCallContent union types
        content_blocks: list[dict] = []
        diff_content = None
        terminal_id = ""
        text_parts: list[str] = []

        for c in content_list:
            c_type = safe_str(getattr(c, "type", ""))
            if c_type == "diff":
                diff_content = c
            elif c_type == "terminal":
                terminal_id = safe_str(getattr(c, "terminal_id", ""))
                content_blocks.append({"type": "terminal", "terminal_id": terminal_id})
            elif c_type == "content":
                inner = getattr(c, "content", None)
                if inner:
                    block = _serialize_content_block(inner)
                    if block:
                        content_blocks.append(block)
                        if block.get("type") == "text" and block.get("text"):
                            text_parts.append(block["text"])

        # diff → FILE_EDIT event
        if diff_content:
            return AgentEvent(type=AgentEventType.FILE_EDIT, data={
                "path": safe_str(getattr(diff_content, "path", "")) or file_path,
                "full_old": safe_str(getattr(diff_content, "old_text", "")),
                "full_new": safe_str(getattr(diff_content, "new_text", "")),
            })

        # Fallback: raw_output as content block
        if not content_blocks and raw_output:
            content_blocks = _extract_content_from_raw_output(raw_output)

        text = "\n".join(text_parts)
        raw_input_str = _serialize_dict(raw_input)

        if is_update:
            is_done = status in ("completed", "done", "success")
            is_failed = status in ("failed", "error")
            chunk_status = "failed" if is_failed else ("completed" if is_done else "running")
            return AgentEvent(type=AgentEventType.TOOL_CALL_UPDATE, data={
                "id": tool_call_id, "name": title, "status": chunk_status,
                "progress": text, "raw_output": _serialize_dict(raw_output),
                "content_blocks": content_blocks,
                "file_path": file_path, "locations": locations,
            })
        else:
            return AgentEvent(type=AgentEventType.TOOL_CALL_START, data={
                "name": title, "kind": kind, "id": tool_call_id,
                "status": status, "file_path": file_path,
                "raw_input": raw_input_str,
                "tool_input": _extract_tool_input(raw_input, locations, content_list),
                "content_blocks": content_blocks,
                "locations": locations, "terminal_id": terminal_id, "text": text,
            })


# ── Helper functions ──

def _serialize_content_block(block: Any) -> Optional[dict]:
    """Serialize an ACP SDK ContentBlock to a dict for frontend rendering."""
    block_type = safe_str(getattr(block, "type", ""))
    if not block_type:
        block_type = type(block).__name__.lower()

    if block_type == "text":
        return {"type": "text", "text": safe_str(getattr(block, "text", ""))}
    elif block_type == "image":
        return {"type": "image", "mime_type": safe_str(getattr(block, "mime_type", "")), "data": safe_str(getattr(block, "data", ""))}
    elif block_type == "audio":
        return {"type": "audio", "mime_type": safe_str(getattr(block, "mime_type", "")), "data": safe_str(getattr(block, "data", ""))}
    elif block_type == "resource":
        resource = getattr(block, "resource", None)
        uri = safe_str(getattr(resource, "uri", "")) if resource else ""
        text = ""
        contents = getattr(resource, "contents", None)
        if contents:
            text = safe_str(getattr(contents, "text", ""))
        return {"type": "resource", "uri": uri, "text": text}
    elif block_type == "resource_link":
        return {
            "type": "resource_link",
            "uri": safe_str(getattr(block, "uri", "")),
            "name": safe_str(getattr(block, "name", "")),
            "title": safe_str(getattr(block, "title", "")),
            "description": safe_str(getattr(block, "description", "")),
        }
    else:
        text = safe_str(getattr(block, "text", ""))
        if text:
            return {"type": "text", "text": text}
        return None


def _extract_content_from_raw_output(raw: Any) -> list[dict]:
    """When content[] is empty, pass raw_output as a 'raw_output' typed block."""
    if not raw:
        return []
    try:
        serializable = json.loads(json.dumps(raw, default=str))
    except Exception:
        serializable = {"_error": "raw_output not serializable"}
    return [{"type": "raw_output", "data": serializable}]


def _serialize_dict(d: Any) -> str:
    """Serialize dict to a short summary string for display."""
    if not d or not isinstance(d, dict):
        return ""
    try:
        truncated = _truncate_for_summary(d)
        return json.dumps(truncated, ensure_ascii=False, default=str)[:2000]
    except (TypeError, ValueError):
        return str(d)[:2000]


def _truncate_for_summary(obj: Any, max_str: int = 200, depth: int = 0) -> Any:
    """Recursively truncate large values for summary display."""
    if depth > 5:
        return "..."
    if isinstance(obj, str):
        return obj[:max_str] + "..." if len(obj) > max_str else obj
    if isinstance(obj, dict):
        return {k: _truncate_for_summary(v, max_str, depth + 1) for k, v in list(obj.items())[:20]}
    if isinstance(obj, list):
        items = [_truncate_for_summary(i, max_str, depth + 1) for i in obj[:5]]
        if len(obj) > 5:
            items.append(f"...({len(obj)} items)")
        return items
    return obj


def _extract_tool_input(raw_input: Any, locations: list[dict], content_list: Any) -> str:
    """Extract a human-readable tool input summary."""
    if raw_input and isinstance(raw_input, dict):
        cmd = raw_input.get("command")
        if cmd is not None:
            if isinstance(cmd, list):
                return " ".join(str(c) for c in cmd)
            return str(cmd)
        path = raw_input.get("path")
        if path:
            return str(path)
        for k in ("query", "url", "pattern", "content", "text"):
            if k in raw_input:
                val = str(raw_input[k])
                return val[:200]
        return _serialize_dict(raw_input)[:200]
    if locations:
        return locations[0].get("path", "")
    return ""
