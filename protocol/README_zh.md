# MobileFlow 通信协议

App ↔ Agent 之间的 WebSocket 通信协议定义。
Python（Agent 端）和 Dart（App 端）共用同一套协议，Python 端是唯一数据源。

## 目录结构

```
protocol/
├── src/mobileflow_protocol/
│   ├── types.py       # 消息类型枚举（全部 122 个消息类型）
│   ├── envelope.py    # 消息信封（Message 类）
│   ├── models.py      # 数据模型（CLIInfo、StreamChunk 等）
│   ├── errors.py      # 错误码定义
│   ├── version.py     # 协议版本号
│   └── __init__.py    # 包导出
├── generate_dart.py   # 从 Python 定义生成 Dart 代码
├── verify_dart.py     # 校验 Python 和 Dart 两端是否一致
└── README.md
```

## 使用方式

### Python 端（Agent）

```python
# 导入消息类型
from mobileflow_protocol.types import MessageType

# 导入消息信封
from mobileflow_protocol.envelope import Message

# 导入数据模型
from mobileflow_protocol.models import CLIInfo, StreamChunk, StreamChunkType

# 发送消息
msg = Message(type=MessageType.CLI_STATUS, payload={"cli": "kiro", "state": "ready"})
await ws.send(msg.model_dump_json())
```

### Dart 端（App）

```dart
// MessageType 是自动生成的，通过 protocol.dart 的 export 导入
import 'package:mobileflow/models/protocol.dart';

// 发送消息
ws.send(WsMessage(type: MessageType.cliList));

// 解析收到的消息
final msg = WsMessage.fromJson(jsonDecode(data));
if (msg.type == MessageType.cliListResult) {
  final adapters = msg.payload['adapters'] as List;
}
```

## 新增消息类型的流程

### 第一步：在 Python 端添加

编辑 `src/mobileflow_protocol/types.py`，在对应的功能域区域加入新的枚举值：

```python
# 必须标注方向（App -> Agent 或 Agent -> App）
SYSTEM_INFO = "system.info"              # App -> Agent: request system info
SYSTEM_INFO_RESULT = "system.info.result"  # Agent -> App: system info
```

### 第二步：分类消息模式

如果新消息是通知（Agent 单向推送）或命令（App 单向发送），需要加到 `types.py` 底部的分类集合里：

```python
# 通知类型（Agent -> App，不需要回复）
_NOTIFICATIONS: frozenset[MessageType] = frozenset({
    MessageType.SYSTEM_INFO_PUSH,  # 加在这里
    ...
})

# 命令类型（App -> Agent，不需要 .result 回复）
_COMMANDS: frozenset[MessageType] = frozenset({
    MessageType.SYSTEM_RESET,  # 加在这里
    ...
})
```

不加的话默认是 Request 模式（有配对的 `.result` 回复）。

### 第三步：添加数据模型（可选）

如果消息有复杂的 payload 结构，在 `models.py` 里定义 Pydantic 模型：

```python
class SystemInfoResultPayload(BaseModel):
    """Payload for system.info.result."""
    os: str
    python_version: str
    agent_version: str
```

### 第四步：生成 Dart 代码

在 `pocket-coder/protocol/` 目录下运行：

```bash
python generate_dart.py
```

这会自动更新 `app/lib/models/protocol_types.g.dart`，Dart 端立即可用新的常量。

### 第五步：校验一致性

```bash
python verify_dart.py
```

输出 `OK: All xxx Python MessageType constants found in Dart file` 表示两端一致。

### 完成

Dart 端自动拥有了 `MessageType.systemInfo` 和 `MessageType.systemInfoResult` 常量，
不需要手动编辑任何 Dart 文件。

## 消息模式说明

每个消息类型属于以下三种模式之一：

| 模式 | 说明 | 示例 |
|------|------|------|
| **Request（请求-响应）** | App 发送请求，Agent 返回 `.result` 响应 | `file.read` → `file.read.result` |
| **Notification（通知）** | Agent 单向推送给 App，不需要回复 | `cli.status`、`file.changed` |
| **Command（命令）** | App 单向发送给 Agent，不需要 `.result` | `chat.cancel`、`mode.set` |

Python 端可以查询消息模式：

```python
from mobileflow_protocol.types import get_message_pattern, MessagePattern

pattern = get_message_pattern(MessageType.CLI_STATUS)
assert pattern == MessagePattern.NOTIFICATION
```

## 协议版本号

```python
from mobileflow_protocol.version import PROTOCOL_VERSION  # 当前为 1
```

只有在破坏性变更（重命名消息类型、修改 payload 结构）时才递增版本号。
新增消息类型不算破坏性变更，不需要递增。

## 重要规则

- **Python 端是唯一数据源**：所有消息类型在 `types.py` 里定义，Dart 端通过脚本生成
- **禁止手动编辑 `protocol_types.g.dart`**：这是自动生成的文件，手动改会被覆盖
- **每次改协议后必须跑 `generate_dart.py`**：否则 Dart 端会缺少新的消息类型
- **`protocol.dart` 里的手写类不受影响**：WsMessage、CliCapabilities、ConfigOption 等仍然手动维护
