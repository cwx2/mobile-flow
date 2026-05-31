// CliHandler tests
//
// Covers: cliStatus with state=ready triggers handleCliStatus and history
// request, duplicate history request prevention, capabilities update,
// cliListResult with agent default, app default fallback, and no CLIs.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/protocol.dart';
import 'package:mobileflow/models/payloads/cli_payloads.g.dart';
import 'package:mobileflow/models/chat_message.dart';
import 'package:mobileflow/services/chat_state.dart';
import 'package:mobileflow/services/message_handlers/cli_handler.dart';
import 'package:mobileflow/services/websocket_service.dart';
import 'package:mobileflow/services/ws_operations/chat_operations.dart';

// ── Mock WebSocketService for CliHandler ──
//
// CliHandler calls: ws.cliCapabilitiesMap, ws.handleCliStatus,
// ws.historyRequestedForCli, ws.defaultCli, ws.chatOps.requestChatHistory,
// ws.installedClis, ws.cliDisplayNames, ws.messages, ws.resetCliState,
// ws.send, ws.notifyUI.

class _ChatStateHost extends ChangeNotifier with ChatStateMixin {}

/// Fake ChatOperations that tracks requestChatHistory calls.
/// Extends the real class so the return type matches WebSocketService.chatOps.
class _FakeChatOps extends ChatOperations {
  int requestChatHistoryCount = 0;

  _FakeChatOps(_FakeWsForChatOps ws) : super(ws);

  @override
  void requestChatHistory({String? cli}) => requestChatHistoryCount++;
}

/// Minimal WS stub used only to construct _FakeChatOps (ChatOperations
/// constructor requires a WebSocketService).
class _FakeWsForChatOps implements WebSocketService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockWs implements WebSocketService {
  final _ChatStateHost _state = _ChatStateHost();
  late final _FakeChatOps _chatOps = _FakeChatOps(_FakeWsForChatOps());

  // CliHandler-relevant state
  @override
  Map<String, CliCapabilities> get cliCapabilitiesMap => _cliCapabilities;
  final Map<String, CliCapabilities> _cliCapabilities = {};

  @override
  String defaultCli = '';

  @override
  bool get historyRequestedForCli => _historyRequested;
  @override
  set historyRequestedForCli(bool v) => _historyRequested = v;
  bool _historyRequested = false;

  @override
  List<String> installedClis = [];

  @override
  Map<String, String> cliDisplayNames = {};

  @override
  List<ChatMessage> get messages => _state.messages;

  // Track sent messages
  final List<WsMessage> sentMessages = [];

  @override
  void send(WsMessage msg) => sentMessages.add(msg);

  @override
  void handleCliStatus(CliStatusPayload payload) =>
      _state.handleCliStatus(payload);

  @override
  void resetCliState() => _state.resetCliState();

  int notifyUICount = 0;
  @override
  void notifyUI() => notifyUICount++;

  // ChatOps proxy — returns the fake that tracks requestChatHistory calls
  @override
  ChatOperations get chatOps => _chatOps;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late CliHandler handler;
  late _MockWs ws;

  setUp(() {
    handler = CliHandler();
    ws = _MockWs();
  });

  group('CliHandler — cliStatus', () {
    test('state=ready 触发 handleCliStatus 并请求聊天历史', () {
      ws.defaultCli = 'claude';

      handler.handle(
        WsMessage(
          type: MessageType.cliStatus,
          payload: {
            'cli': 'claude',
            'state': 'ready',
            'message': 'Provider ready',
          },
        ),
        ws,
      );

      expect(ws._state.cliLifecycleState, CliLifecycleState.ready);
      expect(ws._chatOps.requestChatHistoryCount, 1);
      expect(ws.historyRequestedForCli, true);
    });

    test('state=ready 但已请求过历史则不重复请求', () {
      ws.defaultCli = 'claude';
      ws.historyRequestedForCli = true;

      handler.handle(
        WsMessage(
          type: MessageType.cliStatus,
          payload: {
            'cli': 'claude',
            'state': 'ready',
            'message': 'Provider ready',
          },
        ),
        ws,
      );

      expect(ws._chatOps.requestChatHistoryCount, 0);
    });

    test('state=ready 但 cli 不是 defaultCli 则不请求历史', () {
      ws.defaultCli = 'claude';

      handler.handle(
        WsMessage(
          type: MessageType.cliStatus,
          payload: {
            'cli': 'other-cli',
            'state': 'ready',
            'message': 'Ready',
          },
        ),
        ws,
      );

      expect(ws._chatOps.requestChatHistoryCount, 0);
    });

    test('capabilities 在 handleCliStatus 之前更新', () {
      ws.defaultCli = 'claude';

      handler.handle(
        WsMessage(
          type: MessageType.cliStatus,
          payload: {
            'cli': 'claude',
            'state': 'ready',
            'message': 'Ready',
            'capabilities': {
              'supports_image': true,
              'supports_session_list': true,
            },
          },
        ),
        ws,
      );

      expect(ws.cliCapabilitiesMap.containsKey('claude'), true);
      expect(ws.cliCapabilitiesMap['claude']!.supportsImage, true);
      expect(ws.cliCapabilitiesMap['claude']!.supportsSessionList, true);
    });
  });

  group('CliHandler — cliListResult', () {
    test('agent 有 default_cli 时采用它', () {
      ws.defaultCli = '';

      handler.handle(
        WsMessage(
          type: MessageType.cliListResult,
          payload: {
            'adapters': [
              {'name': 'claude', 'display_name': 'Claude', 'installed': true},
              {'name': 'copilot', 'display_name': 'Copilot', 'installed': true},
            ],
            'default_cli': 'claude',
          },
        ),
        ws,
      );

      expect(ws.defaultCli, 'claude');
      expect(ws.installedClis, ['claude', 'copilot']);
      expect(ws.cliDisplayNames['claude'], 'Claude');
    });

    test('agent 无 default 但 app 有记忆时发送 cliSwitch', () {
      ws.defaultCli = 'copilot';

      handler.handle(
        WsMessage(
          type: MessageType.cliListResult,
          payload: {
            'adapters': [
              {'name': 'copilot', 'display_name': 'Copilot', 'installed': true},
            ],
            'default_cli': '',
          },
        ),
        ws,
      );

      // Should send cli.switch to restore the app's remembered CLI
      final switchMsgs = ws.sentMessages
          .where((m) => m.type == MessageType.cliSwitch)
          .toList();
      expect(switchMsgs.length, 1);
      expect(switchMsgs.first.payload['cli'], 'copilot');
    });

    test('无 CLI 安装时清空 defaultCli', () {
      ws.defaultCli = 'old-cli';

      handler.handle(
        WsMessage(
          type: MessageType.cliListResult,
          payload: {
            'adapters': [
              {'name': 'claude', 'display_name': 'Claude', 'installed': false},
            ],
            'default_cli': '',
          },
        ),
        ws,
      );

      expect(ws.defaultCli, '');
      expect(ws.installedClis, isEmpty);
    });
  });
}
