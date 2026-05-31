// HandlerRegistry tests
//
// Covers: register, get, registerAll, overwrite, and type isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/protocol.dart';
import 'package:mobileflow/services/message_handlers/handler_registry.dart';
import 'package:mobileflow/services/message_handlers/message_handler.dart';
import 'package:mobileflow/services/websocket_service.dart';

/// Stub handler that records the last message type it processed.
class _StubHandler extends MessageHandler {
  String? lastType;

  @override
  void handle(WsMessage msg, WebSocketService ws) {
    lastType = msg.type;
  }
}

void main() {
  late HandlerRegistry registry;

  setUp(() {
    registry = HandlerRegistry();
  });

  group('HandlerRegistry', () {
    test('register 和 get 返回正确的 handler', () {
      final handler = _StubHandler();
      registry.register('chat.stream', handler);
      expect(registry.get('chat.stream'), same(handler));
    });

    test('get 对未注册类型返回 null', () {
      expect(registry.get('nonexistent.type'), isNull);
    });

    test('registerAll 批量注册多个 handler', () {
      final chatHandler = _StubHandler();
      final cliHandler = _StubHandler();
      registry.registerAll({
        MessageType.chatStream: chatHandler,
        MessageType.cliStatus: cliHandler,
      });
      expect(registry.get(MessageType.chatStream), same(chatHandler));
      expect(registry.get(MessageType.cliStatus), same(cliHandler));
    });

    test('重复注册同一类型会覆盖前一个 handler', () {
      final first = _StubHandler();
      final second = _StubHandler();
      registry.register('chat.done', first);
      registry.register('chat.done', second);
      expect(registry.get('chat.done'), same(second));
      expect(registry.get('chat.done'), isNot(same(first)));
    });

    test('不同类型映射到不同 handler', () {
      final handlerA = _StubHandler();
      final handlerB = _StubHandler();
      registry.register(MessageType.chatStream, handlerA);
      registry.register(MessageType.chatDone, handlerB);
      expect(registry.get(MessageType.chatStream), same(handlerA));
      expect(registry.get(MessageType.chatDone), same(handlerB));
      expect(
        registry.get(MessageType.chatStream),
        isNot(same(registry.get(MessageType.chatDone))),
      );
    });
  });
}
