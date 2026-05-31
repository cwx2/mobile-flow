/// handler_registry.dart — Message type → Handler routing registry.
library;

import 'message_handler.dart';

/// Maps message type strings to [MessageHandler] instances.
///
/// Used by WebSocketService to route incoming messages without
/// a monolithic if-else chain. New message types only need a
/// new handler file and a register() call.
class HandlerRegistry {
  final Map<String, MessageHandler> _handlers = {};

  /// Register a handler for a single message [type].
  void register(String type, MessageHandler handler) {
    _handlers[type] = handler;
  }

  /// Register multiple handlers at once.
  void registerAll(Map<String, MessageHandler> handlers) {
    _handlers.addAll(handlers);
  }

  /// Look up the handler for a message [type], or null if unregistered.
  MessageHandler? get(String type) => _handlers[type];
}
