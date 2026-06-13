/// wake_lock_service.dart — AI active period wake lock management.
///
/// Prevents CPU sleep (Android PARTIAL_WAKE_LOCK / iOS idleTimerDisabled)
/// while AI is actively generating output. Released after an idle timeout
/// to avoid excessive battery drain.
///
/// When AI is streaming/thinking/toolRunning, the wake lock is held so
/// the OS does not suspend the process and drop the WebSocket connection.
/// Once AI goes idle, a 30-second delay allows for brief gaps between
/// tool calls without thrashing the lock on/off.
///
/// On platforms without wake lock support (e.g. web), all calls are
/// silent no-ops.
library;

import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

import '../utils/logger.dart';

final _log = getLogger('WakeLock');

/// Static utility for managing CPU wake lock during AI activity.
///
/// Acquire when AI starts generating, release after idle timeout.
/// All methods are safe to call from any platform — unsupported
/// platforms fail silently.
class WakeLockService {
  WakeLockService._(); // Prevent instantiation

  static bool _held = false;
  static Timer? _releaseTimer;

  /// Delay before releasing wake lock after AI goes idle.
  ///
  /// 30 seconds covers typical tool-call gaps where the AI agent is
  /// briefly idle between steps (waiting for tool results, thinking).
  /// Prevents rapid acquire/release cycles that waste battery.
  static const _idleRelease = Duration(seconds: 30);

  /// Acquire wake lock — AI is actively generating output.
  ///
  /// Called when [AgentStatus] transitions to thinking, streaming,
  /// or toolRunning. Cancels any pending release timer. Idempotent —
  /// safe to call multiple times while already held.
  static Future<void> acquire() async {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (_held) return;
    try {
      await WakelockPlus.enable();
      _held = true;
      _log.fine('WakeLock acquired (AI active)');
    } catch (e) {
      _log.warning('WakeLock acquire 失败: $e');
    }
  }

  /// Schedule a delayed release — AI went idle.
  ///
  /// Called when [AgentStatus] transitions to idle. The delay prevents
  /// thrashing during brief tool-call gaps. If AI becomes active again
  /// within the delay, [acquire] cancels the pending release.
  static void scheduleRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = Timer(_idleRelease, () async {
      if (!_held) return;
      try {
        await WakelockPlus.disable();
        _held = false;
        _log.fine('WakeLock released (AI idle ${_idleRelease.inSeconds}s)');
      } catch (e) {
        _log.warning('WakeLock release 失败: $e');
      }
    });
  }

  /// Immediate release — connection lost or service disposed.
  ///
  /// Called on disconnect or when [WebSocketService] is disposed.
  /// Does not wait for the idle timeout.
  static Future<void> forceRelease() async {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (!_held) return;
    try {
      await WakelockPlus.disable();
      _held = false;
      _log.fine('WakeLock force released');
    } catch (_) {}
  }
}
