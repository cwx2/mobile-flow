#!/usr/bin/env python3
"""Generate Dart payload data classes from Python Pydantic payload models.

Reads all PayloadBase subclasses registered in PAYLOAD_REGISTRY and
generates typed Dart classes with fromJson/toJson methods.  Output is
one file per domain under app/lib/models/payloads/{domain}_payloads.g.dart
plus a barrel file payloads.g.dart that re-exports everything.

Usage:
    cd pocket-coder/protocol
    python generate_dart_payloads.py

The generated Dart classes mirror the Python Pydantic models exactly:
  - Field names are converted from snake_case to lowerCamelCase
  - fromJson reads snake_case keys from the wire JSON
  - toJson writes snake_case keys for the wire JSON
  - Python defaults are replicated in Dart constructors
  - Optional[T] becomes T? (nullable) in Dart

This script is the single source of truth bridge for payload models
between the Python protocol package and the Dart app.
"""

from __future__ import annotations

import enum
import importlib
import re
import sys
import types as builtin_types
from pathlib import Path
from typing import Any, Optional, Union, get_args, get_origin

from pydantic import BaseModel

# Ensure the protocol package is importable
PROTOCOL_SRC = Path(__file__).parent / "src"
sys.path.insert(0, str(PROTOCOL_SRC))

from mobileflow_protocol.payload_registry import PAYLOAD_REGISTRY
from mobileflow_protocol.payloads.base import PayloadBase
from mobileflow_protocol.version import PROTOCOL_VERSION

# ── Import all domain modules to populate the registry ──
# Each domain module calls register_payload() at import time.
_DOMAIN_MODULES = [
    "mobileflow_protocol.payloads.auth",
    "mobileflow_protocol.payloads.cli",
    "mobileflow_protocol.payloads.chat",
    "mobileflow_protocol.payloads.session",
    "mobileflow_protocol.payloads.permission",
    "mobileflow_protocol.payloads.file",
    "mobileflow_protocol.payloads.diff",
    "mobileflow_protocol.payloads.git",
    "mobileflow_protocol.payloads.terminal",
    "mobileflow_protocol.payloads.project",
    "mobileflow_protocol.payloads.plugin",
    "mobileflow_protocol.payloads.state",
]

for _mod_name in _DOMAIN_MODULES:
    importlib.import_module(_mod_name)


# ── Type mapping helpers ──


def _snake_to_lower_camel(name: str) -> str:
    """Convert snake_case to lowerCamelCase for Dart field names.

    Examples:
        session_token -> sessionToken
        device_name -> deviceName
        cli -> cli
    """
    parts = name.split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


def _is_optional(annotation: Any) -> tuple[bool, Any]:
    """Check if a type annotation is Optional[T] and extract the inner type.

    Returns:
        (is_optional, inner_type) — if not optional, inner_type is the
        original annotation unchanged.
    """
    origin = get_origin(annotation)
    args = get_args(annotation)

    # Optional[T] is Union[T, None] in typing
    if origin is Union:
        non_none = [a for a in args if a is not type(None)]
        if len(non_none) == 1 and type(None) in args:
            return True, non_none[0]

    return False, annotation


def _is_pydantic_model(tp: Any) -> bool:
    """Check if a type is a Pydantic BaseModel subclass (not PayloadBase itself)."""
    try:
        return (
            isinstance(tp, type)
            and issubclass(tp, BaseModel)
            and tp is not BaseModel
            and tp is not PayloadBase
        )
    except TypeError:
        return False


def _is_enum_type(tp: Any) -> bool:
    """Check if a type is an Enum subclass."""
    try:
        return isinstance(tp, type) and issubclass(tp, enum.Enum)
    except TypeError:
        return False


def _map_python_type_to_dart(annotation: Any) -> str:
    """Map a Python type annotation to its Dart equivalent.

    Handles primitives, Optional, list, dict, nested Pydantic models,
    and Enum subclasses.  Falls back to 'dynamic' for unknown types.

    Args:
        annotation: A Python type annotation from model_fields.

    Returns:
        Dart type string (e.g. "String", "int", "List<Map<String, dynamic>>").
    """
    # Handle NoneType
    if annotation is type(None):
        return "dynamic"

    # Unwrap Optional — caller handles nullability suffix
    is_opt, inner = _is_optional(annotation)
    if is_opt:
        dart_inner = _map_python_type_to_dart(inner)
        return dart_inner

    origin = get_origin(annotation)
    args = get_args(annotation)

    # list[T] -> List<DartT>
    if origin is list:
        if args:
            inner_dart = _map_python_type_to_dart(args[0])
            return f"List<{inner_dart}>"
        return "List<dynamic>"

    # dict[K, V] -> Map<DartK, DartV>
    if origin is dict:
        if args and len(args) == 2:
            key_dart = _map_python_type_to_dart(args[0])
            val_dart = _map_python_type_to_dart(args[1])
            return f"Map<{key_dart}, {val_dart}>"
        return "Map<String, dynamic>"

    # Primitive types
    if annotation is str:
        return "String"
    if annotation is int:
        return "int"
    if annotation is float:
        return "double"
    if annotation is bool:
        return "bool"

    # typing.Any -> dynamic
    if annotation is Any:
        return "dynamic"

    # Enum subclass -> String (wire value)
    if _is_enum_type(annotation):
        return "String"

    # Nested Pydantic model -> Dart class name
    if _is_pydantic_model(annotation):
        return annotation.__name__

    # Fallback
    return "dynamic"


def _dart_default_value(default: Any, dart_type: str, is_optional: bool) -> str | None:
    """Convert a Python default value to a Dart literal string.

    Returns None if there is no default (required field).

    Args:
        default: The Python default value.
        dart_type: The mapped Dart type string.
        is_optional: Whether the field is Optional[T].

    Returns:
        Dart literal string or None.
    """
    if default is None:
        if is_optional:
            return "null"
        return None

    if isinstance(default, bool):
        return "true" if default else "false"

    if isinstance(default, int):
        return str(default)

    if isinstance(default, float):
        return str(default)

    if isinstance(default, str):
        # Escape single quotes in the string
        escaped = default.replace("\\", "\\\\").replace("'", "\\'")
        return f"'{escaped}'"

    if isinstance(default, list):
        return "const []"

    if isinstance(default, dict):
        return "const {}"

    if isinstance(default, enum.Enum):
        # Enum defaults serialize as their string value
        escaped = str(default.value).replace("'", "\\'")
        return f"'{escaped}'"

    return None


# ── Dart code generation ──


class _FieldInfo:
    """Parsed field information for Dart code generation."""

    def __init__(
        self,
        python_name: str,
        dart_name: str,
        dart_type: str,
        is_optional: bool,
        default_literal: str | None,
        needs_cast: str,
        from_json_expr: str,
        to_json_expr: str,
    ):
        self.python_name = python_name
        self.dart_name = dart_name
        self.dart_type = dart_type
        self.is_optional = is_optional
        self.default_literal = default_literal
        self.needs_cast = needs_cast
        self.from_json_expr = from_json_expr
        self.to_json_expr = to_json_expr


def _build_from_json_expr(
    python_name: str,
    dart_type: str,
    is_optional: bool,
    annotation: Any,
) -> str:
    """Build the Dart expression for reading a field from a JSON map.

    Handles type casting, list conversion, map conversion, and nested
    model deserialization.

    Args:
        python_name: The snake_case key in the JSON map.
        dart_type: The Dart type string for this field.
        is_optional: Whether the field is nullable.
        annotation: The original Python type annotation.

    Returns:
        A Dart expression string like "json['field_name'] as String?".
    """
    _, inner_annotation = _is_optional(annotation)
    origin = get_origin(inner_annotation)
    args = get_args(inner_annotation)

    accessor = f"json['{python_name}']"

    # Nested Pydantic model
    if _is_pydantic_model(inner_annotation):
        model_name = inner_annotation.__name__
        if is_optional:
            return (
                f"{accessor} != null "
                f"? {model_name}.fromJson(Map<String, dynamic>.from({accessor} as Map)) "
                f": null"
            )
        return f"{model_name}.fromJson(Map<String, dynamic>.from({accessor} as Map))"

    # list[T]
    if origin is list and args:
        inner_arg = args[0]
        inner_origin = get_origin(inner_arg)
        inner_args = get_args(inner_arg)

        # list[dict[str, Any]] -> List<Map<String, dynamic>>
        if inner_origin is dict:
            if is_optional:
                return (
                    f"({accessor} as List?)"
                    f"?.map((e) => Map<String, dynamic>.from(e as Map))"
                    f".toList()"
                )
            return (
                f"({accessor} as List? ?? [])"
                f".map((e) => Map<String, dynamic>.from(e as Map))"
                f".toList()"
            )

        # list[PydanticModel]
        if _is_pydantic_model(inner_arg):
            model_name = inner_arg.__name__
            if is_optional:
                return (
                    f"({accessor} as List?)"
                    f"?.map((e) => {model_name}.fromJson(Map<String, dynamic>.from(e as Map)))"
                    f".toList()"
                )
            return (
                f"({accessor} as List? ?? [])"
                f".map((e) => {model_name}.fromJson(Map<String, dynamic>.from(e as Map)))"
                f".toList()"
            )

        # list[str] -> List<String>
        dart_inner = _map_python_type_to_dart(inner_arg)
        if is_optional:
            return (
                f"({accessor} as List?)"
                f"?.map((e) => e as {dart_inner})"
                f".toList()"
            )
        return (
            f"({accessor} as List? ?? [])"
            f".map((e) => e as {dart_inner})"
            f".toList()"
        )

    # dict[K, V]
    if origin is dict and args and len(args) == 2:
        key_dart = _map_python_type_to_dart(args[0])
        val_dart = _map_python_type_to_dart(args[1])
        if is_optional:
            return (
                f"{accessor} != null "
                f"? Map<{key_dart}, {val_dart}>.from({accessor} as Map) "
                f": null"
            )
        return f"Map<{key_dart}, {val_dart}>.from({accessor} as Map? ?? {{}})"

    # Enum -> String (wire value)
    if _is_enum_type(inner_annotation):
        if is_optional:
            return f"{accessor} as String?"
        return f"{accessor} as String? ?? ''"

    # Primitive types with simple cast
    null_suffix = "?" if is_optional else ""
    if dart_type in ("String", "int", "double", "bool"):
        if is_optional:
            return f"{accessor} as {dart_type}?"
        # For non-optional primitives, provide safe defaults
        defaults = {"String": "''", "int": "0", "double": "0.0", "bool": "false"}
        return f"{accessor} as {dart_type}? ?? {defaults[dart_type]}"

    # dynamic / fallback
    return accessor


def _build_to_json_expr(
    dart_name: str,
    python_name: str,
    dart_type: str,
    is_optional: bool,
    annotation: Any,
) -> str:
    """Build the Dart expression for writing a field to a JSON map.

    Args:
        dart_name: The lowerCamelCase Dart field name.
        python_name: The snake_case key for the JSON map.
        dart_type: The Dart type string.
        is_optional: Whether the field is nullable.
        annotation: The original Python type annotation.

    Returns:
        A Dart expression string for the toJson map entry value.
    """
    _, inner_annotation = _is_optional(annotation)

    # Nested Pydantic model
    if _is_pydantic_model(inner_annotation):
        if is_optional:
            return f"{dart_name}?.toJson()"
        return f"{dart_name}.toJson()"

    # list[PydanticModel]
    origin = get_origin(inner_annotation)
    args = get_args(inner_annotation)
    if origin is list and args and _is_pydantic_model(args[0]):
        if is_optional:
            return f"{dart_name}?.map((e) => e.toJson()).toList()"
        return f"{dart_name}.map((e) => e.toJson()).toList()"

    # Everything else serializes directly (primitives, List, Map)
    return dart_name


def _analyze_field(python_name: str, field_info: Any) -> _FieldInfo:
    """Analyze a Pydantic model field and produce Dart generation info.

    Args:
        python_name: The snake_case field name from the Pydantic model.
        field_info: The Pydantic FieldInfo object from model_fields.

    Returns:
        A _FieldInfo with all data needed for Dart code generation.
    """
    annotation = field_info.annotation
    is_opt, inner = _is_optional(annotation)

    dart_name = _snake_to_lower_camel(python_name)
    dart_type = _map_python_type_to_dart(annotation)
    full_dart_type = f"{dart_type}?" if is_opt else dart_type

    # Determine default value
    default = field_info.default
    if default is not None or is_opt:
        default_literal = _dart_default_value(default, dart_type, is_opt)
    else:
        default_literal = None

    from_json_expr = _build_from_json_expr(python_name, dart_type, is_opt, annotation)
    to_json_expr = _build_to_json_expr(dart_name, python_name, full_dart_type, is_opt, annotation)

    return _FieldInfo(
        python_name=python_name,
        dart_name=dart_name,
        dart_type=full_dart_type,
        is_optional=is_opt,
        default_literal=default_literal,
        needs_cast="",
        from_json_expr=from_json_expr,
        to_json_expr=to_json_expr,
    )


def _generate_dart_class(class_name: str, model_class: type[PayloadBase]) -> list[str]:
    """Generate Dart source lines for a single payload class.

    Produces a class with:
      - Final fields
      - Constructor with named parameters
      - factory fromJson(Map<String, dynamic> json)
      - Map<String, dynamic> toJson()

    Args:
        class_name: The Dart class name (same as Python class name).
        model_class: The Pydantic PayloadBase subclass to introspect.

    Returns:
        List of Dart source lines.
    """
    fields: list[_FieldInfo] = []
    for name, field_info in model_class.model_fields.items():
        fields.append(_analyze_field(name, field_info))

    lines: list[str] = []

    # Class declaration
    docstring = model_class.__doc__
    if docstring:
        # Take the first line of the docstring as a brief description
        first_line = docstring.strip().split("\n")[0].strip()
        lines.append(f"/// {first_line}")

    lines.append(f"class {class_name} {{")

    # Fields
    for f in fields:
        lines.append(f"  final {f.dart_type} {f.dart_name};")

    if fields:
        lines.append("")

    # Constructor
    if fields:
        lines.append(f"  const {class_name}({{")
        for f in fields:
            if f.default_literal is not None:
                lines.append(f"    this.{f.dart_name} = {f.default_literal},")
            else:
                lines.append(f"    required this.{f.dart_name},")
        lines.append("  });")
    else:
        lines.append(f"  const {class_name}();")

    lines.append("")

    # fromJson factory
    lines.append(f"  factory {class_name}.fromJson(Map<String, dynamic> json) {{")
    if fields:
        lines.append(f"    return {class_name}(")
        for f in fields:
            lines.append(f"      {f.dart_name}: {f.from_json_expr},")
        lines.append("    );")
    else:
        lines.append(f"    return const {class_name}();")
    lines.append("  }")

    lines.append("")

    # toJson method
    lines.append("  Map<String, dynamic> toJson() => {")
    for f in fields:
        lines.append(f"        '{f.python_name}': {f.to_json_expr},")
    lines.append("      };")

    lines.append("}")

    return lines


def _extract_domain(model_class: type[PayloadBase]) -> str:
    """Extract the domain name from a payload model's module path.

    The domain is the last component of the module name before the
    class definition.  For example:
      mobileflow_protocol.payloads.auth -> auth
      mobileflow_protocol.payloads.cli  -> cli

    Args:
        model_class: A PayloadBase subclass.

    Returns:
        Domain name string (e.g. "auth", "cli", "chat").
    """
    module = model_class.__module__
    # Module path: mobileflow_protocol.payloads.{domain}
    parts = module.split(".")
    return parts[-1]


def _generate_file_header(domain: str) -> list[str]:
    """Generate the standard file header for a generated Dart file.

    Args:
        domain: The domain name (e.g. "auth", "cli").

    Returns:
        List of header lines.
    """
    return [
        "// GENERATED CODE — DO NOT EDIT BY HAND",
        f"// Generated from mobileflow_protocol v{PROTOCOL_VERSION}",
        "//",
        "// To regenerate, run from pocket-coder/protocol/:",
        "//   python generate_dart_payloads.py",
        "//",
        f"// Source: protocol/src/mobileflow_protocol/payloads/{domain}.py",
        "",
    ]


def _collect_models_by_domain() -> dict[str, list[tuple[str, type[PayloadBase]]]]:
    """Group all registered payload models by their domain.

    Returns:
        Dict mapping domain name to list of (class_name, model_class) tuples,
        ordered by registration order.
    """
    domains: dict[str, list[tuple[str, type[PayloadBase]]]] = {}
    seen_classes: set[type] = set()

    for _msg_type, model_class in PAYLOAD_REGISTRY.items():
        if model_class in seen_classes:
            continue
        seen_classes.add(model_class)

        domain = _extract_domain(model_class)
        if domain not in domains:
            domains[domain] = []
        domains[domain].append((model_class.__name__, model_class))

    return domains


def generate() -> dict[str, str]:
    """Generate all Dart payload files.

    Returns:
        Dict mapping relative file path (from app/) to generated Dart source.
    """
    domains = _collect_models_by_domain()
    output_files: dict[str, str] = {}

    for domain, models in sorted(domains.items()):
        lines = _generate_file_header(domain)

        for i, (class_name, model_class) in enumerate(models):
            if i > 0:
                lines.append("")
            class_lines = _generate_dart_class(class_name, model_class)
            lines.extend(class_lines)

        lines.append("")
        file_path = f"lib/models/payloads/{domain}_payloads.g.dart"
        output_files[file_path] = "\n".join(lines)

    # Generate barrel file
    barrel_lines = [
        "// GENERATED CODE — DO NOT EDIT BY HAND",
        f"// Generated from mobileflow_protocol v{PROTOCOL_VERSION}",
        "//",
        "// To regenerate, run from pocket-coder/protocol/:",
        "//   python generate_dart_payloads.py",
        "//",
        "// Barrel file re-exporting all generated payload classes.",
        "",
    ]
    for domain in sorted(domains.keys()):
        barrel_lines.append(f"export '{domain}_payloads.g.dart';")
    barrel_lines.append("")

    output_files["lib/models/payloads/payloads.g.dart"] = "\n".join(barrel_lines)

    return output_files


def main():
    """Generate and write all Dart payload files."""
    output_files = generate()

    app_dir = Path(__file__).parent.parent / "app"
    total_classes = 0

    for rel_path, content in sorted(output_files.items()):
        out_path = app_dir / rel_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(content, encoding="utf-8")

        # Count classes in this file
        class_count = content.count("\nclass ")
        total_classes += class_count
        print(f"  Generated {rel_path} ({class_count} classes)")

    print(f"\nTotal: {total_classes} payload classes across {len(output_files) - 1} domain files")
    print(f"Protocol version: {PROTOCOL_VERSION}")


if __name__ == "__main__":
    main()
