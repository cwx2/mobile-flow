/// connection_service.dart — Connection state machine.
///
/// Tracks the current connection lifecycle state as a finite state
/// machine (FSM) with five states: disconnected, connecting, connected,
/// reconnecting, and failed. Exposes state and reconnect progress
/// via [ChangeNotifier] for Provider-based UI updates.
///
/// Replaces the previous boolean [isConnected] with a richer enum
/// so the UI can distinguish "reconnecting" (stay on HomeScreen,
/// show banner) from "disconnected" (show ConnectScreen).
library;

import 'package:flutter/foundation.dart';

import '../core/connection_config.dart';
import '../utils/logger.dart';
import 'connection_manager.dart';

final _log = getLogger('ConnectionService');

/// Connection lifecycle states.
///
/// Named [AppConnectionState] to avoid collision with Flutter's
/// built-in [ConnectionState] from the async widget library.
///
/// The state machine transitions are:
///   disconnected → connecting → connected
///   connected → reconnecting → connected (success)
///   connected → reconnecting → failed (exhausted)
///   reconnecting → disconnected (user manual disconnect)
///   failed → connecting (user retry)
enum AppConnectionState {
  /// No active connection. Initial state or user-initiated disconnect.
  disconnected,

  /// TCP + WebSocket + auth handshake in progress.
  connecting,

  /// Connection established, heartbeat running.
  connected,

  /// Connection lost, automatic reconnect in progress.
  /// User stays on HomeScreen with a reconnect banner.
  reconnecting,

  /// Reconnect attempts exhausted or unrecoverable error.
  /// User sees failure UI with retry / disconnect options.
  failed,
}

/// Holds the current connection state with the desktop agent.
///
/// This is a lightweight state container — actual transport logic
/// lives in [ConnectionManager], reconnect orchestration lives in
/// [WebSocketService]. Screens watch this to drive routing and
/// status display.
class ConnectionService extends ChangeNotifier {
  String? _host;
  int _port = 9600;
  String? _sessionToken;
  AppConnectionState _state = AppConnectionState.disconnected;
  ConnectionMode _connectionMode = ConnectionMode.lan;

  // Reconnect progress (exposed for UI banner)
  int _reconnectAttempt = 0;
  int _reconnectMaxAttempts = kReconnectMaxAttempts;

  // Getters
  String? get host => _host;
  int get port => _port;
  String? get sessionToken => _sessionToken;
  AppConnectionState get state => _state;
  ConnectionMode get connectionMode => _connectionMode;
  int get reconnectAttempt => _reconnectAttempt;
  int get reconnectMaxAttempts => _reconnectMaxAttempts;

  /// Backward-compatible getter for code that still checks boolean.
  ///
  /// Returns true when the connection is usable (connected) or
  /// temporarily interrupted but recovering (reconnecting). This
  /// keeps existing UI code working during the migration period.
  bool get isConnected =>
      _state == AppConnectionState.connected ||
      _state == AppConnectionState.reconnecting;

  /// Build the WebSocket URL based on the current connection mode.
  String get wsUrl {
    switch (_connectionMode) {
      case ConnectionMode.lan:
        return 'ws://$_host:$_port';
      case ConnectionMode.relay:
        return 'relay://$_host';
      case ConnectionMode.tunnel:
        return 'wss://$_host';
    }
  }

  /// Set connection parameters (called after QR scan or manual input).
  ///
  /// [host] is the IP or relay URL.
  /// [port] is only used for LAN mode.
  /// [mode] determines the transport type.
  void setConnection({
    required String host,
    int port = 9600,
    ConnectionMode mode = ConnectionMode.lan,
  }) {
    _log.info('连接参数变更: host=$host, port=$port, mode=$mode');
    _host = host;
    _port = port;
    _connectionMode = mode;
    notifyListeners();
  }

  /// Transition to [ConnectionState.connecting].
  ///
  /// Called when a connection attempt begins (initial or retry from failed).
  void markConnecting() {
    final old = _state;
    _state = AppConnectionState.connecting;
    _log.info('连接状态变更: $old → $_state');
    notifyListeners();
  }

  /// Transition to [ConnectionState.connected].
  ///
  /// Called after successful TCP + auth handshake. Resets reconnect
  /// counters so the next disconnect starts fresh.
  void markConnected(String sessionToken) {
    final old = _state;
    _sessionToken = sessionToken;
    _state = AppConnectionState.connected;
    _reconnectAttempt = 0;
    _log.info('连接状态变更: $old → $_state, host=$_host:$_port');
    notifyListeners();
  }

  /// Transition to [ConnectionState.reconnecting].
  ///
  /// Called when the connection drops unexpectedly (heartbeat timeout,
  /// stream onDone/onError). The user stays on HomeScreen.
  void markReconnecting({int? maxAttempts}) {
    final old = _state;
    _state = AppConnectionState.reconnecting;
    _reconnectAttempt = 0;
    if (maxAttempts != null) _reconnectMaxAttempts = maxAttempts;
    _log.warning('连接状态变更: $old → $_state, maxAttempts=$_reconnectMaxAttempts');
    notifyListeners();
  }

  /// Update the current reconnect attempt number.
  ///
  /// Called by the reconnect loop in [WebSocketService] so the UI
  /// banner can show "第 3/10 次".
  void updateReconnectAttempt(int attempt) {
    _reconnectAttempt = attempt;
    _log.fine('重连进度: $_reconnectAttempt/$_reconnectMaxAttempts');
    notifyListeners();
  }

  /// Transition to [ConnectionState.failed].
  ///
  /// Called when reconnect attempts are exhausted or an unrecoverable
  /// error occurs. The user sees a failure banner with retry option.
  void markFailed() {
    final old = _state;
    _state = AppConnectionState.failed;
    _log.severe('连接状态变更: $old → $_state, 重连已耗尽');
    notifyListeners();
  }

  /// Transition to [ConnectionState.disconnected].
  ///
  /// Called on user-initiated disconnect or when cleaning up after
  /// a failed connection attempt.
  void disconnect() {
    final old = _state;
    _state = AppConnectionState.disconnected;
    _sessionToken = null;
    _reconnectAttempt = 0;
    _log.info('连接状态变更: $old → $_state, host=$_host:$_port');
    notifyListeners();
  }
}
