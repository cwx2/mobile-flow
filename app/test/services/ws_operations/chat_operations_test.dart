// ChatOperations tests
//
// Covers: sendChat (message add, beginAssistantMessage, context ref clear,
// agent status guard), cancelChat, newSession, switchSession,
// requestChatHistory, requestMoreHistory.
//
// Uses a mock WebSocketService that tracks method calls and exposes
// the state ChatOperations reads/writes.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/core/event_bus.dart';
import 'package:mobileflow/models/chat_message.dart';
import 'package:mobileflow/models/context_reference.dart';
import 'package:mobileflow/models/protocol.dart';
import 'package:mobileflow/services/chat_state.dart';
import 'package:mobileflow/services/websocket_service.dart';
import 'package:mobileflow/services/ws_operations/chat_operations.dart';

// ── Mock WebSocketService for ChatOperations ──
//
// ChatOperations accesses: _ws.agentStatus, _ws.messages, _ws.send(),
// _ws.beginAssistantMessage(), _ws.finishStream(), _ws.defaultCli,
// _ws.pendingContextReferences, _ws.loadingHistory, _ws.notifyUI(),
// _ws.isLoadingMoreHistory, _ws.hasMoreHistory, _ws.loadingMoreHistory,
// _ws.eventBus.

class _ChatStateHost extends ChangeNotifier with ChatStateMixin {}

class _MockWs implements WebSocketService {
  final _ChatStateHost _state = _ChatStateHost();
  final List<WsMessage> sentMessages = [];
  int beginAssistantMessageCount = 0;
  int finishStreamCount = 0;
  int notifyUICount = 0;

  @override
  String defaultCli = 'test-cli';

  @override
  AgentStatus get agentStatus => _state.agentStatus;

  @override
  List<ChatMessage> get messages => _state.messages;

  @override
  final List<ContextReference> pendingContextReferences = [];

  @override
  bool get isLoadingHistory => _state.isLoadingHistory;

  @override
  set loadingHistory(bool v) => _state.loadingHistory = v;

  @override
  bool get isLoadingMoreHistory => _state.isLoadingMoreHistory;

  @override
  set loadingMoreHistory(bool v) => _state.loadingMoreHistory = v;

  @override
  bool get hasMoreHistory => _state.hasMoreHistory;

  @override
  AppEventBus? get eventBus => null;

  @override
  void send(WsMessage msg) => sentMessages.add(msg);

  @override
  void beginAssistantMessage() {
    beginAssistantMessageCount++;
    _state.beginAssistantMessage();
  }

  @override
  void finishStream(AppEventBus? bus) {
    finishStreamCount++;
    _state.finishStream(bus);
  }

  @override
  void notifyUI() => notifyUICount++;

  /// Get sent messages of a given type.
  List<WsMessage> ofType(String type) =>
      sentMessages.where((m) => m.type == type).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late _MockWs ws;
  late ChatOperations chatOps;

  setUp(() {
    ws = _MockWs();
    chatOps = ChatOperations(ws);
  });

  group('ChatOperations — sendChat', () {
    test('添加用户消息到 messages 列表', () {
      chatOps.sendChat('Hello');
      expect(ws.messages.length, 2); // user + assistant (streaming)
      expect(ws.messages.first.role, ChatRole.user);
      expect(ws.messages.first.plainText, 'Hello');
    });

    test('调用 beginAssistantMessage', () {
      chatOps.sendChat('Hello');
      expect(ws.beginAssistantMessageCount, 1);
    });

    test('发送后清空 pendingContextReferences', () {
      ws.pendingContextReferences.add(ContextReference(
        type: ContextRefType.files,
        path: 'src/main.py',
      ));
      expect(ws.pendingContextReferences.length, 1);

      chatOps.sendChat('Check this file');
      expect(ws.pendingContextReferences, isEmpty);

      // Verify the context references were included in the sent message
      final chatSendMsgs = ws.ofType(MessageType.chatSend);
      expect(chatSendMsgs.length, 1);
      expect(chatSendMsgs.first.payload['context_references'], isNotNull);
    });

    test('agentStatus 非 idle 时先取消再发送', () {
      // Put agent into thinking state
      ws.beginAssistantMessage();
      expect(ws.agentStatus, AgentStatus.thinking);

      chatOps.sendChat('New message');

      // Should have sent a cancel first
      final cancelMsgs = ws.ofType(MessageType.chatCancel);
      expect(cancelMsgs.length, 1);

      // Then the chat.send
      final sendMsgs = ws.ofType(MessageType.chatSend);
      expect(sendMsgs.length, 1);
    });
  });

  group('ChatOperations — cancelChat', () {
    test('发送 chat.cancel 并调用 finishStream', () {
      ws.beginAssistantMessage();
      chatOps.cancelChat();

      final cancelMsgs = ws.ofType(MessageType.chatCancel);
      expect(cancelMsgs.length, 1);
      expect(cancelMsgs.first.payload['cli'], 'test-cli');
      expect(ws.finishStreamCount, 1);
    });
  });

  group('ChatOperations — newSession', () {
    test('清空 messages 并发送 session.new', () {
      ws.messages.add(ChatMessage(
        role: ChatRole.user,
        blocks: [ContentBlock.text('old msg')],
      ));
      expect(ws.messages.length, 1);

      chatOps.newSession();

      expect(ws.messages, isEmpty);
      final newMsgs = ws.ofType(MessageType.sessionNew);
      expect(newMsgs.length, 1);
      expect(newMsgs.first.payload['cli'], 'test-cli');
    });
  });

  group('ChatOperations — switchSession', () {
    test('设置 loadingHistory 并发送 session.switch', () {
      chatOps.switchSession('session-123');

      expect(ws.isLoadingHistory, true);
      final switchMsgs = ws.ofType(MessageType.sessionSwitch);
      expect(switchMsgs.length, 1);
      expect(switchMsgs.first.payload['session_id'], 'session-123');
    });
  });

  group('ChatOperations — requestChatHistory', () {
    test('设置 loadingHistory 并发送 chat.history', () {
      chatOps.requestChatHistory();

      expect(ws.isLoadingHistory, true);
      final historyMsgs = ws.ofType(MessageType.chatHistory);
      expect(historyMsgs.length, 1);
      expect(historyMsgs.first.payload['cli'], 'test-cli');
    });
  });

  group('ChatOperations — requestMoreHistory', () {
    test('正在加载时跳过', () {
      ws.loadingMoreHistory = true;
      chatOps.requestMoreHistory();
      expect(ws.ofType(MessageType.chatHistoryMore), isEmpty);
    });

    test('没有更多历史时跳过', () {
      // hasMoreHistory is false by default (no history buffer, no server more)
      chatOps.requestMoreHistory();
      expect(ws.ofType(MessageType.chatHistoryMore), isEmpty);
    });

    test('有更多历史时发送 chat.history.more', () {
      // Restore history with hasMore=true to enable pagination
      ws._state.restoreHistory(
        [
          {'role': 'user', 'type': 'text', 'content': 'hi'},
        ],
        hasMore: true,
      );

      chatOps.requestMoreHistory();

      expect(ws.isLoadingMoreHistory, true);
      final moreMsgs = ws.ofType(MessageType.chatHistoryMore);
      expect(moreMsgs.length, 1);
    });
  });
}
