#!/usr/bin/env python3
"""Generate Dart protocol definitions from the Python protocol package.

Reads MessageType enum from mobileflow_protocol.types and generates
the Dart MessageType class in app/lib/models/protocol_types.g.dart.

Usage:
    python generate_dart.py

The generated file contains ONLY the MessageType constants. Hand-written
Dart classes (WsMessage, CliCapabilities, ConfigOption) remain in
protocol.dart and are not affected.

This script is the single source of truth bridge between the Python
protocol package and the Dart app. Run it after adding or modifying
message types in types.py.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Ensure the protocol package is importable
PROTOCOL_SRC = Path(__file__).parent / "src"
sys.path.insert(0, str(PROTOCOL_SRC))

from mobileflow_protocol.types import MessageType, get_message_pattern, MessagePattern
from mobileflow_protocol.version import PROTOCOL_VERSION


def _snake_to_camel(name: str) -> str:
    """Convert UPPER_SNAKE_CASE enum name to lowerCamelCase Dart constant.

    Examples:
        AUTH_PAIR -> authPair
        CLI_LIST_RESULT -> cliListResult
        FILE_TREE -> fileTree
        GIT_DIFF_COMMIT_RESULT -> gitDiffCommitResult
    """
    parts = name.lower().split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def _extract_direction(member: MessageType) -> str:
    """Extract direction comment from the enum member's Python source comment.

    Parses the '# App -> Agent' or '# Agent -> App' annotation from types.py.
    Returns empty string if no direction comment found.
    """
    # Read the source file and find the line for this member
    types_file = PROTOCOL_SRC / "mobileflow_protocol" / "types.py"
    source = types_file.read_text(encoding="utf-8")
    # Match: MEMBER_NAME = "value"  # direction comment
    pattern = rf'{member.name}\s*=\s*"[^"]+"\s*#\s*(.+)'
    match = re.search(pattern, source)
    if match:
        return match.group(1).strip()
    return ""


def _pattern_label(pattern: str) -> str:
    """Convert pattern constant to a short label for Dart comments."""
    return {
        MessagePattern.REQUEST: "request",
        MessagePattern.NOTIFICATION: "notification",
        MessagePattern.COMMAND: "command",
    }.get(pattern, "unknown")


def generate() -> str:
    """Generate the Dart source code for protocol_types.g.dart."""
    lines: list[str] = []

    # File header
    lines.append("// GENERATED CODE — DO NOT EDIT BY HAND")
    lines.append(f"// Generated from mobileflow_protocol v{PROTOCOL_VERSION}")
    lines.append("//")
    lines.append("// To regenerate, run from pocket-coder/protocol/:")
    lines.append("//   python generate_dart.py")
    lines.append("//")
    lines.append("// Source: protocol/src/mobileflow_protocol/types.py")
    lines.append("")
    lines.append(f"/// Protocol version for App-Agent WebSocket communication.")
    lines.append(f"const int protocolVersion = {PROTOCOL_VERSION};")
    lines.append("")
    lines.append("/// All WebSocket message type constants.")
    lines.append("///")
    lines.append("/// Auto-generated from the Python mobileflow_protocol package.")
    lines.append("/// Each constant maps to a protocol message exchanged between")
    lines.append("/// the Flutter app and the Python agent over WebSocket.")
    lines.append("class MessageType {")

    # Group members by domain (extract from the enum value prefix)
    current_domain = ""
    for member in MessageType:
        # Determine domain from the wire value (e.g. "auth.pair" -> "auth")
        wire_value = member.value
        domain = wire_value.split(".")[0]

        # Add domain separator comment
        if domain != current_domain:
            if current_domain:
                lines.append("")
            domain_labels = {
                "auth": "Authentication",
                "chat": "Chat",
                "session": "Session",
                "mode": "ACP Configuration",
                "config": "ACP Configuration",
                "file": "File Operations",
                "diff": "Diff Operations",
                "git": "Git Operations",
                "terminal": "Terminal",
                "cli": "CLI Management",
                "permission": "Permissions",
                "confirm": "Confirm (legacy)",
                "project": "Project Management",
                "plugin": "Plugin Management",
                "status": "Heartbeat",
                "state": "State Push",
            }
            label = domain_labels.get(domain, domain.capitalize())
            # Skip duplicate domain header for config (same section as mode)
            if not (domain == "config" and current_domain == "mode"):
                lines.append(f"  // ── {label} ──")
            current_domain = domain

        # Generate the constant
        dart_name = _snake_to_camel(member.name)
        direction = _extract_direction(member)
        pattern = get_message_pattern(member)
        pattern_label = _pattern_label(pattern)

        # Build comment: direction + pattern
        comment_parts = []
        if direction:
            comment_parts.append(direction)
        comment_parts.append(f"[{pattern_label}]")
        comment = " ".join(comment_parts)

        lines.append(f"  static const {dart_name} = '{wire_value}'; // {comment}")

    lines.append("}")
    lines.append("")

    return "\n".join(lines)


def main():
    """Generate and write the Dart protocol types file."""
    dart_code = generate()

    # Output path: app/lib/models/protocol_types.g.dart
    output = Path(__file__).parent.parent / "app" / "lib" / "models" / "protocol_types.g.dart"
    output.write_text(dart_code, encoding="utf-8")

    # Count generated constants
    count = sum(1 for _ in MessageType)
    print(f"Generated {output.relative_to(Path(__file__).parent.parent)}")
    print(f"  {count} message type constants")
    print(f"  Protocol version: {PROTOCOL_VERSION}")


if __name__ == "__main__":
    main()
