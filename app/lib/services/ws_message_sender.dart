/// ws_message_sender.dart — Abstract interface for sending WebSocket messages.
///
/// Operations classes depend on this interface instead of WebSocketService,
/// enabling compile-time decoupling and mock-based unit testing.
/// WebSocketService implements it, handling encryption transparently.
library;

import '../models/protocol.dart';

/// Contract for sending [WsMessage] through the active transport.
///
/// Operations classes call [send] to dispatch messages without knowing
/// about encryption, transport details, or connection state.
abstract interface class MessageSender {
  /// Send [msg] through the active transport.
  ///
  /// If LAN encryption is active, the payload is encrypted before
  /// reaching [ConnectionManager]. Auth messages bypass encryption.
  void send(WsMessage msg);

  /// The default CLI name (used as fallback when callers don't specify).
  String get defaultCli;
}
