/// stream_watchdog.dart — Phase-aware stream activity watchdog.
///
/// Monitors time elapsed since the last stream chunk. Fires a callback
/// when the timeout expires, indicating the stream has silently stalled.
/// Timeout duration varies by streaming phase (thinking/streaming/toolRunning).
///
/// Follows the same standalone-timer pattern as [WsHeartbeat]: a single
/// class with start/reset/cancel lifecycle, injected callback, and no
/// dependency on Flutter widgets or Provider.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/connection_config.dart';
import '../utils/logger.dart';

final _log = getLogger('StreamWatchdog');

/// Streaming phases for watchdog timeout selection.
///
/// Each phase has a different timeout duration reflecting the expected
/// cadence of data arrival:
///   - thinking: AI is processing, may take a while before first chunk
///   - streaming: text chunks arrive frequently
///   - toolRunning: tools can take much longer (file ops, searches)
enum StreamPhase {
  /// No active stream. Watchdog is inactive.
  idle,

  /// Waiting for the first chunk after beginAssistantMessage().
  thinking,

  /// Actively receiving text/thought chunks.
  streaming,

  /// A tool is executing (extended timeout).
  toolRunning,
}

/// Phase-aware stream activity watchdog.
///
/// Lifecycle:
///   1. [start] — begin monitoring with a phase-specific timeout
///   2. [reset] — restart the timer (called on each chunk received)
///   3. [updatePhase] — change the timeout duration (phase transition)
///   4. [cancel] — stop monitoring (stream completed normally)
///
/// When the timer fires without being reset, [onTimeout] is called,
/// signaling that the stream has silently stalled.
class StreamWatchdog {
  /// Callback fired when the watchdog timer expires.
  /// Typically calls `interruptCurrentStream()` on the chat state.
  final VoidCallback onTimeout;

  Timer? _timer;
  StreamPhase _currentPhase = StreamPhase.idle;

  StreamWatchdog({required this.onTimeout});

  /// Start the watchdog with the timeout for [phase].
  ///
  /// Cancels any existing timer and starts a fresh one.
  /// Called when a streaming turn begins (phase = thinking).
  void start(StreamPhase phase) {
    _currentPhase = phase;
    _timer?.cancel();
    final duration = _timeoutForPhase(phase);
    _timer = Timer(duration, _handleTimeout);
    _log.fine('看门狗启动: phase=${phase.name}, timeout=${duration.inSeconds}s');
  }

  /// Reset the timer using the current phase's timeout.
  ///
  /// Called on each received stream chunk to indicate the stream is alive.
  /// No-op if the watchdog is not active (phase == idle).
  void reset() {
    if (_currentPhase == StreamPhase.idle) return;
    _timer?.cancel();
    _timer = Timer(_timeoutForPhase(_currentPhase), _handleTimeout);
  }

  /// Update the phase and restart the timer with the new timeout.
  ///
  /// Called when agentStatus transitions (e.g., thinking → streaming,
  /// streaming → toolRunning). No-op if the phase hasn't changed.
  void updatePhase(StreamPhase phase) {
    if (phase == _currentPhase) return;
    final oldPhase = _currentPhase;
    _currentPhase = phase;
    _timer?.cancel();
    if (phase == StreamPhase.idle) {
      _timer = null;
      return;
    }
    final duration = _timeoutForPhase(phase);
    _timer = Timer(duration, _handleTimeout);
    _log.fine('看门狗阶段变更: ${oldPhase.name} → ${phase.name}, '
        'timeout=${duration.inSeconds}s');
  }

  /// Cancel the watchdog (stream completed normally via chat.done/chat.error).
  ///
  /// Resets the phase to idle and cancels the timer.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    if (_currentPhase != StreamPhase.idle) {
      _log.fine('看门狗取消: phase=${_currentPhase.name}');
    }
    _currentPhase = StreamPhase.idle;
  }

  /// Whether the watchdog is currently active (timer running).
  bool get isActive => _timer != null;

  /// Current phase being monitored.
  StreamPhase get currentPhase => _currentPhase;

  /// Release resources. Call from the owning service's dispose().
  void dispose() => cancel();

  /// Get the timeout duration for a given phase.
  Duration _timeoutForPhase(StreamPhase phase) {
    switch (phase) {
      case StreamPhase.thinking:
        return kWatchdogThinkingTimeout;
      case StreamPhase.streaming:
        return kWatchdogStreamingTimeout;
      case StreamPhase.toolRunning:
        return kWatchdogToolRunningTimeout;
      case StreamPhase.idle:
        return kWatchdogStreamingTimeout; // fallback, shouldn't be called
    }
  }

  /// Handle watchdog timer expiration — log and invoke callback.
  void _handleTimeout() {
    _log.warning('⚠️ 流式看门狗超时: phase=${_currentPhase.name}');
    _timer = null;
    _currentPhase = StreamPhase.idle;
    onTimeout();
  }
}
