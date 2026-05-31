# MobileFlow Protocol

App ↔ Agent WebSocket communication protocol definitions.
Single source of truth for both Python (Agent) and Dart (App) sides.

## Structure

```
protocol/
├── src/mobileflow_protocol/
│   ├── types.py       # MessageType enum (all 122 message types)
│   ├── envelope.py    # Message class (WebSocket envelope)
│   ├── models.py      # Payload models (CLIInfo, StreamChunk, etc.)
│   ├── errors.py      # Error codes
│   ├── version.py     # PROTOCOL_VERSION constant
│   └── __init__.py    # Package exports
├── generate_dart.py   # Generate Dart code from Python definitions
├── verify_dart.py     # Verify Python ↔ Dart consistency
└── README.md
```

## Usage

### Python (Agent side)

```python
from mobileflow_protocol.types import MessageType
from mobileflow_protocol.envelope import Message
from mobileflow_protocol.models import CLIInfo, StreamChunk

msg = Message(type=MessageType.CLI_STATUS, payload={"cli": "kiro", "state": "ready"})
await ws.send(msg.model_dump_json())
```

### Dart (App side)

```dart
import 'package:mobileflow/models/protocol.dart';

ws.send(WsMessage(type: MessageType.cliList));

final msg = WsMessage.fromJson(jsonDecode(data));
if (msg.type == MessageType.cliListResult) {
  final adapters = msg.payload['adapters'] as List;
}
```

## Adding a New Message Type

1. Edit `src/mobileflow_protocol/types.py` — add enum member with direction comment
2. If notification or command, add to `_NOTIFICATIONS` or `_COMMANDS` set
3. Optionally add payload model in `models.py`
4. Run `python generate_dart.py` from `pocket-coder/protocol/`
5. Run `python verify_dart.py` to confirm consistency
6. Dart side automatically gets the new constant

## Message Patterns

| Pattern | Description | Example |
|---------|-------------|---------|
| **Request** | Paired request-response | `file.read` → `file.read.result` |
| **Notification** | One-way Agent → App push | `cli.status`, `file.changed` |
| **Command** | One-way App → Agent action | `chat.cancel`, `mode.set` |

## Protocol Version

```python
from mobileflow_protocol.version import PROTOCOL_VERSION  # Currently 1
```

Increment only on breaking changes. New message types are non-breaking.
