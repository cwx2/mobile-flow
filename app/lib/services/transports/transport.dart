/// transport.dart — Transport interface and shared base class.
///
/// Defines the [Transport] contract that all connection modes must
/// implement, and [BaseTransport] which extracts the common
/// WebSocket lifecycle logic (connect, listen, close, send).
///
/// Subclasses only need to implement [createChannel] to provide
/// a connected [WebSocketChannel] — all stream wiring, error
/// handling, and cleanup is handled by the base class.
library;

import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/connection_config.dart';
import '../../utils/logger.dart';

final _log = getLogger('Transport');

/// Pure interface contract for all transport modes.
///
/// [WebSocketService] programs against this interface — it never
/// knows whether the underlying connection is LAN, Relay, or Tunnel.
abstract interface class Transport {
  /// Establish the connection.
  Future<void> connect();

  /// Send a serialized JSON message string.
  void send(String jsonMessage);

  /// Incoming message stream (JSON strings).
  Stream<String> get messageStream;

  /// Close the connection and release resources.
  ///
  /// When [graceful] is true, attempts a proper WebSocket close
  /// handshake. When false, drops the connection immediately.
  Future<void> close({bool graceful = true});

  /// Whether the transport is currently connected.
  bool get isConnected;
}

/// Shared base class for all WebSocket transports.
///
/// Handles the common lifecycle: connect → listen → forward
/// messages → report errors/close → cleanup. Subclasses only
/// implement [createChannel] to build the mode-specific
/// [WebSocketChannel] (with custom URI, headers, etc.).
///
/// The two-stream pattern (inner raw WebSocket stream → outer
/// broadcast controller) decouples the transport lifecycle from
/// consumers. When the inner stream closes, the outer stream
/// signals the upper layer without auto-reconnecting.
abstract class BaseTransport implements Transport {
  WebSocketChannel? _channel;
  final _messageController = StreamController<String>.broadcast();
  bool _connected = false;
  bool _manuallyClosed = false;

  /// Human-readable label for log messages (e.g. "LAN", "Relay").
  String get label;

  /// Create and return a connected [WebSocketChannel].
  ///
  /// Called by [connect]. Subclasses build the URI, set headers,
  /// and call `WebSocketChannel.connect(...)`. The base class
  /// handles the `.ready` timeout and stream wiring.
  Future<WebSocketChannel> createChannel();

  /// Transform an incoming raw message before forwarding.
  ///
  /// Override in subclasses that need decryption (e.g. Relay).
  /// Default implementation passes through unchanged.
  String transformIncoming(String raw) => raw;

  /// Transform an outgoing message before sending.
  ///
  /// Override in subclasses that need encryption (e.g. Relay).
  /// Default implementation passes through unchanged.
  String transformOutgoing(String jsonMessage) => jsonMessage;

  @override
  Future<void> connect() async {
    _manuallyClosed = false;
    try {
      _channel = await createChannel();
      await _channel!.ready.timeout(kConnectTimeout);
      _connected = true;
      _log.info('✅ ${label}Transport 已连接');

      _channel!.stream.listen(
        (data) {
          try {
            final transformed = transformIncoming(data as String);
            _messageController.add(transformed);
          } catch (e) {
            _log.severe('❌ ${label}Transport 消息转换错误: $e');
          }
        },
        onError: (e) {
          _log.warning('⚠️ ${label}Transport 错误: $e');
          _connected = false;
          if (!_manuallyClosed) _messageController.addError(e);
        },
        onDone: () {
          _log.warning('⚠️ ${label}Transport 连接断开');
          _connected = false;
          if (!_manuallyClosed && !_messageController.isClosed) {
            _messageController.close();
          }
        },
      );
    } catch (e) {
      _log.severe('❌ ${label}Transport 连接失败: $e');
      _connected = false;
      rethrow;
    }
  }

  @override
  void send(String jsonMessage) {
    final transformed = transformOutgoing(jsonMessage);
    _channel?.sink.add(transformed);
  }

  @override
  Stream<String> get messageStream => _messageController.stream;

  /// Close the connection and release resources.
  ///
  /// When [graceful] is true (user-initiated disconnect), attempts to
  /// send a WebSocket close frame with a 2s timeout. When false
  /// (reconnect cleanup), skips the close frame entirely — the old
  /// channel is simply dropped and GC'd, avoiding the hang caused by
  /// trying to send a close frame to an unreachable peer.
  Future<void> close({bool graceful = true}) async {
    _connected = false;
    _log.fine('$label close: graceful=$graceful, channel=${_channel != null}');

    if (graceful && _channel != null) {
      _manuallyClosed = true;
      // User-initiated: attempt WebSocket close frame handshake
      try {
        await _channel!.sink.close().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            _log.warning('$label close: 优雅关闭超时 (2s)，放弃');
          },
        );
      } catch (e) {
        _log.warning('$label close: sink.close() 异常: $e');
      }
    }
    // Drop channel reference — GC cleans up the TCP socket.
    // Avoids hanging on sink.close() when the peer is unreachable.
    _channel = null;

    if (!_messageController.isClosed) {
      await _messageController.close();
    }
    _log.fine('$label close: 完成');
  }

  @override
  bool get isConnected => _connected;
}

/// Thrown when a Tunnel connection fails due to HTTP 401/403.
///
/// Signals that the Bearer Token or CF Access credentials are invalid.
/// The reconnect loop should NOT retry on this error — user must
/// re-enter credentials.
class TunnelAuthException implements Exception {
  final String message;
  TunnelAuthException(this.message);

  @override
  String toString() => 'TunnelAuthException: $message';
}
