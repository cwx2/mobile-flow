"""Verify generated Dart file matches Python protocol definitions."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "src"))

from mobileflow_protocol.types import MessageType


def snake_to_camel(name):
    parts = name.lower().split("_")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])


dart_file = Path(__file__).parent.parent / "app" / "lib" / "models" / "protocol_types.g.dart"
dart_content = dart_file.read_text(encoding="utf-8")

missing = []
for member in MessageType:
    dart_name = snake_to_camel(member.name)
    wire_value = member.value
    expected = f"static const {dart_name} = '{wire_value}';"
    if expected not in dart_content:
        missing.append(f"  {dart_name} = '{wire_value}'")

if missing:
    print(f"FAIL: {len(missing)} constants missing from generated Dart file:")
    for m in missing:
        print(m)
    sys.exit(1)
else:
    print(f"OK: All {len(MessageType)} Python MessageType constants found in Dart file")
