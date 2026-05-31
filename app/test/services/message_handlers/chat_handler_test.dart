// ChatHandler tests
//
// Covers: chatDone, chatError, chatHistoryResult, chatHistoryMoreResult,
// chatStream (text, mode_change, config_update).
//
// Uses a lightweight MockWsForHandler that implements the WebSocketService
// surface area used by ChatHandler via noSuchMethod fallback.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/core/event_bus.dart';
import 'package:mobileflow/models/protocol.dart';
import 'package:mobileflow/services/chat_state.dart';
import 'package:mobileflow/services/message_handlers/chat_handler.dart';
import 'package:mobileflow/services/websocket_service.dart';
import 'package:mobileflow/services/ws_operations/chat_operations.dart';

// ── Mock WebSocketService ──
//
// ChatHandler calls: ws.handleStreamChunk, ws.finishStream, ws.errorStream,
// ws.restoreHistory, ws.appendOlderHistory, ws.notifyUI, ws.eventBus,
// ws.currentModeValue=, ws.configOptionsValue=, ws.currentMode,
// ws.configOptions, ws.agentStatus, ws.beginAssistantMessage, ws.chatOps.
//
// We use a real ChatStateMixin host for stream/history logic and track
// the handler-specific calls.

/// Minimal ChatStateMixin host for testing handler interactions.
class _ChatStateHost extends ChangeNotifier with ChatStateMixin {}

/// Mock that tracks calls from ChatHandler without needing the full
/// WebSocketService dependency tree.
class _MockWs implements WebSocketService {
  final _ChatStateHost _state = _ChatStateHost();
  final AppEventBus _eventBus = AppEventBus();

  // Tracking flags
  bool finishStreamCalled = false;
  String? errorStreamMessage;
  List<dynamic>? restoredHistory;
  int? restoredTotal;
  bool? restoredHasMore;
  bool? restoredResumed;
  List<dynamic>? appendedHistory;
  bool? appendedHasMore;
  int notifyUICount = 0;
  String? lastModeValue;
  List<ConfigOption>? lastConfigOptions;

  @override
  AppEventBus? get eventBus => _eventBus;

  @override
  AgentStatus get agentStatus => _state.agentStatus;

  @override
  String get currentMode => lastModeValue ?? '';

  @override
  List<ConfigOption> get configOptions => lastConfigOptions ?? [];

  @override
  set currentModeValue(String v) => lastModeValue = v;

  @override
  set configOptionsValue(List<ConfigOption> v) => lastConfigOptions = v;

  @override
  void handleStreamChunk(Map<String, dynamic> chunk) =>
      _state.handleStreamChunk(chunk);

  @override
  void beginAssistantMessage() => _state.beginAssistantMessage();

  @override
  void finishStream(AppEventBus? bus) {
    finishStreamCalled = true;
    _state.finishStream(bus);
  }

  @override
  void errorStream(String error, AppEventBus? bus) {
    errorStreamMessage = error;
    _state.errorStream(error, bus);
  }

  @override
  void restoreHistory(List<dynamic> historyList,
      {int totalCount = 0, bool hasMore = false, bool resumed = false}) {
    restoredHistory = historyList;
    restoredTotal = totalCount;
    restoredHasMore = hasMore;
    restoredResumed = resumed;
    _state.restoreHistory(historyList,
        totalCount: totalCount, hasMore: hasMore, resumed: resumed);
  }

  @override
  int appendOlderHistory(List<dynamic> olderItems,
      {bool hasMore = false}) {
    appendedHistory = olderItems;
    appendedHasMore = hasMore;
    return _state.appendOlderHistory(olderItems, hasMore: hasMore);
  }

  @override
  void notifyUI() {
    notifyUICount++;
  }

  @override
  ChatOperations get chatOps => throw UnimplementedError(
      'chatOps not needed for basic ChatHandler tests');

  // ── noSuchMethod fallback for unused members ──
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late ChatHandler handler;
  late _MockWs ws;

  setUp(() {
    handler = ChatHandler();
    ws = _MockWs();
  });

  group('ChatHandler', () {
    test('chatDone 调用 finishStream()', () {
      // Prepare a streaming message so finishStream has something to close
      ws.beginAssistantMessage();

      handler.handle(
        WsMessage(type: MessageType.chatDone, payload: {}),
        ws,
      );
      expect(ws.finishStreamCalled, true);
    });

    test('chatError 调用 errorStream() 并传递错误消息', () {
      ws.beginAssistantMessage();

      handler.handle(
        WsMessage(
          type: MessageType.chatError,
          payload: {'error': 'rate limit exceeded'},
        ),
        ws,
      );
      expect(ws.errorStreamMessage, 'rate limit exceeded');
    });

    test('chatHistoryResult 调用 restoreHistory() 并传递正确参数', () {
      final historyMessages = [
        {'role': 'user', 'type': 'text', 'content': 'hello'},
        {'role': 'assistant', 'type': 'text', 'content': 'hi there'},
      ];

      handler.handle(
        WsMessage(
          type: MessageType.chatHistoryResult,
          payload: {
            'messages': historyMessages,
            'total': 42,
            'has_more': true,
            'cli': 'test-cli',
          },
        ),
        ws,
      );
      expect(ws.restoredHistory, isNotNull);
      expect(ws.restoredHistory!.length, 2);
      expect(ws.restoredTotal, 42);
      expect(ws.restoredHasMore, true);
    });

    test('chatHistoryMoreResult 调用 appendOlderHistory() 并传递正确参数',
        () {
      final olderMessages = [
        {'role': 'user', 'type': 'text', 'content': 'older msg'},
      ];

      handler.handle(
        WsMessage(
          type: MessageType.chatHistoryMoreResult,
          payload: {
            'messages': olderMessages,
            'total': 100,
            'has_more': false,
            'cli': 'test-cli',
          },
        ),
        ws,
      );
      expect(ws.appendedHistory, isNotNull);
      expect(ws.appendedHistory!.length, 1);
      expect(ws.appendedHasMore, false);
    });

    test('chatStream text chunk 调用 handleStreamChunk()', () {
      ws.beginAssistantMessage();

      handler.handle(
        WsMessage(
          type: MessageType.chatStream,
          payload: {
            'chunk': {'type': 'text', 'content': 'hello world'},
          },
        ),
        ws,
      );
      // The text should have been appended to the streaming message
      // via handleStreamChunk → ChatStateMixin
      expect(ws._state.messages.last.plainText, contains('hello world'));
    });

    test('chatStream mode_change chunk 更新 currentModeValue', () {
      handler.handle(
        WsMessage(
          type: MessageType.chatStream,
          payload: {
            'chunk': {'type': 'mode_change', 'content': 'architect'},
          },
        ),
        ws,
      );
      expect(ws.lastModeValue, 'architect');
      expect(ws.notifyUICount, greaterThan(0));
    });

    test('chatStream config_update chunk 更新 configOptionsValue', () {
      final configJson =
          '[{"id":"model","name":"Model","type":"select","currentValue":"gpt-4"}]';

      handler.handle(
        WsMessage(
          type: MessageType.chatStream,
          payload: {
            'chunk': {'type': 'config_update', 'content': configJson},
          },
        ),
        ws,
      );
      expect(ws.lastConfigOptions, isNotNull);
      expect(ws.lastConfigOptions!.length, 1);
      expect(ws.lastConfigOptions!.first.id, 'model');
      expect(ws.notifyUICount, greaterThan(0));
    });

    test('chatStream 空 chunk 被忽略', () {
      ws.beginAssistantMessage();
      final msgCountBefore = ws._state.messages.length;

      handler.handle(
        WsMessage(
          type: MessageType.chatStream,
          payload: {'chunk': <String, dynamic>{}},
        ),
        ws,
      );
      // No crash, no new messages added
      expect(ws._state.messages.length, msgCountBefore);
    });
  });
}
