/// ws_heartbeat.dart — Heartbeat, RTT measurement, and timeout detection.
///
/// Sends periodic `status.ping` via [MessageSender], measures RTT from
/// pong responses, and triggers reconnect when missed heartbeats exceed
/// the threshold. Extracted from WebSocketService for independent testing.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/connection_config.dart';
import '../models/protocol.dart';
import '../models/payloads/state_payloads.g.dart';
import '../utils/logger.dart';
import 'ws_message_sender.dart';
import 'connection_manager.dart';
import 'foreground_service.dart';

final _log = getLogger('WsHeartbeat');

/// Manages heartbeat ping/pong cycle, RTT measurement, and dead-connection
/// detection for the WebSocket link to the desktop agent.
///
/// Lifecycle: call [start] after successful auth, [stop] on disconnect,
/// [handlePong] when a `status.pong` arrives, and [resetOnActivity] on
/// any incoming message to suppress false timeout alarms.
class WsHeartbeat {
  final MessageSender _sender;
  final ConnectionManager _connManager;

  /// Called when consecutive missed heartbeats exceed [kMaxMissedHeartbeats].
  /// Typically triggers the reconnect flow in [WebSocketService].
  final VoidCallback onConnectionDead;

  /// Called after state changes (latency update, timeout flag) so the
  /// owning service can call [ChangeNotifier.notifyListeners].
  final VoidCallback onStateChanged;

  // ── Internal timers ──
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;

  // ── RTT measurement ──
  DateTime? _lastPingTime;
  int? _latencyMs;

  // ── Timeout tracking ──
  bool _pingTimedOut = false;
  int _missedHeartbeats = 0;

  /// Incremented each time a pong is received. UI widgets can listen
  /// to this to trigger a heartbeat pulse animation without polling.
  final ValueNotifier<int> pongNotifier = ValueNotifier<int>(0);

  /// Timestamp when the current connection was established.
  DateTime? _connectedSince;

  WsHeartbeat({
    required MessageSender sender,
    required ConnectionManager connManager,
    required this.onConnectionDead,
    required this.onStateChanged,
  })  : _sender = sender,
        _connManager = connManager;

  // ── Public read-only state ──

  /// Last measured round-trip latency in milliseconds, or -1 if unknown.
  int get latencyMs => _latencyMs ?? -1;

  /// Whether the last ping timed out (no pong received within timeout).
  bool get isPingTimedOut => _pingTimedOut;

  /// How long the current connection has been active, or null if not connected.
  Duration? get uptime => _connectedSince != null
      ? DateTime.now().difference(_connectedSince!)
      : null;

  // ── Lifecycle methods ──

  /// Start the heartbeat cycle.
  ///
  /// Cancels any existing timers, resets counters, records the
  /// connection start time, then sends the first ping after
  /// [kFirstHeartbeatDelay] followed by periodic pings at
  /// [kHeartbeatInterval]. Also starts the Android foreground
  /// service to keep the WebSocket alive in background.
  void start() {
    stop();
    _pingTimedOut = false;
    _latencyMs = null;
    _missedHeartbeats = 0;
    _connectedSince = DateTime.now();

    // First ping after a short delay so the user sees latency quickly
    Future.delayed(kFirstHeartbeatDelay, () {
      // Guard: connection may have dropped during the delay
      if (_connectedSince == null) return;
      _sendPing();
      // Then start the periodic timer
      _heartbeatTimer = Timer.periodic(kHeartbeatInterval, (_) {
        _sendPing();
      });
    });

    // Enable Android Foreground Service to keep WebSocket alive in background
    ForegroundService.start();
  }

  /// Stop all heartbeat timers and reset latency state.
  ///
  /// Called on disconnect or before starting a fresh heartbeat cycle.
  /// Also stops the Android foreground service.
  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
    _lastPingTime = null;
    // Reset latency so UI shows "--" instead of stale value
    _latencyMs = null;
    _connectedSince = null;

    // Disable Android Foreground Service when connection drops
    ForegroundService.stop();
  }

  /// Process an incoming `status.pong` — calculate RTT and reset counters.
  ///
  /// Cancels the pong timeout timer, records the round-trip latency,
  /// resets the missed-heartbeat counter, and increments [pongNotifier]
  /// so UI widgets can trigger a pulse animation.
  void handlePong() {
    if (_lastPingTime == null) return;
    final rtt = DateTime.now().difference(_lastPingTime!).inMilliseconds;
    _latencyMs = rtt;
    _pingTimedOut = false;
    _missedHeartbeats = 0;
    _pongTimeoutTimer?.cancel();
    // Notify UI widgets to trigger heartbeat pulse animation
    pongNotifier.value++;
    onStateChanged();
  }

  /// Reset the missed-heartbeat counter on any incoming message.
  ///
  /// If the Agent is actively sending data (chat streams, file events),
  /// the connection is clearly alive — no need to wait for a pong.
  void resetOnActivity() {
    if (_missedHeartbeats > 0) {
      _missedHeartbeats = 0;
      _pingTimedOut = false;
      _pongTimeoutTimer?.cancel();
      onStateChanged();
    }
  }

  /// Release all resources. Call once when the owning service is disposed.
  void dispose() {
    stop();
    pongNotifier.dispose();
  }

  // ── Internal ──

  /// Send a single ping and arm the pong timeout timer.
  void _sendPing() {
    _lastPingTime = DateTime.now();
    _sender.send(WsMessage(
      type: MessageType.statusPing,
      payload: const StatusPingPayload().toJson(),
    ));

    // Arm timeout timer — cancelled by handlePong or resetOnActivity
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = Timer(kHeartbeatTimeout, () {
      _missedHeartbeats++;
      _log.warning('⚠️ 心跳超时 #$_missedHeartbeats/$kMaxMissedHeartbeats');

      if (_missedHeartbeats < kMaxMissedHeartbeats) {
        // Not dead yet — send an immediate retry ping
        _pingTimedOut = true;
        _latencyMs = null;
        onStateChanged();
        _sendPing();
      } else {
        // Consecutive misses exceeded threshold — connection is dead
        _log.severe('❌ 心跳连续超时 $_missedHeartbeats 次，判定连接已死');
        _pingTimedOut = true;
        _latencyMs = null;
        onStateChanged();
        stop();
        // Force close the transport to trigger onDone → reconnect
        _connManager.disconnect();
        onConnectionDead();
      }
    });
  }
}
