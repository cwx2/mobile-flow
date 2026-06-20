/// ws_reconnect_guard.dart — Deferred reconnection with grace window.
///
/// When a WebSocket disconnection is detected, delays the visible
/// reconnection UI by a grace period. During this window, silent
/// reconnection is attempted. If it succeeds within the grace window,
/// the user never sees any disruption (no banner, no state change).
///
/// This prevents the jarring "reconnecting..." banner from flashing
/// for brief, recoverable disconnections caused by app backgrounding,
/// network hiccups, or OS-level socket cleanup.
///
/// Architecture:
///   _onDone detected → ReconnectGuard.onDisconnected()
///     → Start silent reconnect loop (no UI change)
///     → Arm grace timer (2s foreground / 30s background)
///     → If reconnect succeeds within grace → user sees nothing
///     → If grace timer fires → fall back to visible reconnect flow
library;

import 'dart:async';
import '../utils/logger.dart';

final _log = getLogger('ReconnectGuard');

/// Grace window before showing reconnection UI to the user.
///
/// 2 seconds is generous for LAN reconnection (typical < 100ms RTT).
/// This covers the vast majority of background-resume disconnections.
const kGraceWindowForeground = Duration(seconds: 2);

/// Extended grace window when the app is in background.
///
/// The user can't see anything anyway, so we can afford to silently
/// retry for much longer without degrading perceived experience.
const kGraceWindowBackground = Duration(seconds: 30);

/// Delay between silent reconnect retry attempts within the grace window.
const kSilentRetryInterval = Duration(milliseconds: 500);

/// Maximum number of silent retries before giving up early.
/// Prevents CPU spinning if the network is truly unreachable.
const kMaxSilentRetries = 6;

/// Internal state of the reconnect guard.
enum _GuardState {
  /// No disconnection detected, normal operation.
  idle,

  /// Disconnection detected, grace window active, silently reconnecting.
  graceActive,

  /// Grace window expired, visible reconnect flow triggered.
  visibleReconnect,
}

/// Manages the grace window between disconnection detection and visible
/// reconnect UI. Attempts silent reconnection during the grace period.
///
/// Lifecycle:
///   - [onDisconnected]: called by _onDone/_onError when WebSocket drops
///   - [onAppResumed]: called when app returns to foreground
///   - [reset]: called when connection is fully re-established
///   - [dispose]: cleanup timers
class ReconnectGuard {
  _GuardState _state = _GuardState.idle;
  Timer? _graceTimer;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _appInBackground = false;

  /// Callback to attempt a single silent (invisible) reconnect.
  /// Returns true on success, false on failure.
  final Future<bool> Function() onSilentReconnect;

  /// Callback to start the visible reconnect flow (shows banner).
  /// Called only after the grace window expires.
  final void Function() onVisibleReconnect;

  /// Callback invoked when silent reconnect succeeds during grace.
  /// Used to restart heartbeat and notify UI without showing a banner.
  final void Function() onSilentSuccess;

  ReconnectGuard({
    required this.onSilentReconnect,
    required this.onVisibleReconnect,
    required this.onSilentSuccess,
  });

  /// Whether the guard is currently in the grace window.
  bool get isGraceActive => _state == _GuardState.graceActive;

  /// Whether the guard has fallen through to visible reconnect.
  bool get isVisibleReconnect => _state == _GuardState.visibleReconnect;

  /// Notify that the app entered background.
  void markBackground() => _appInBackground = true;

  /// Notify that the app returned to foreground.
  void markForeground() => _appInBackground = false;

  /// Called when WebSocket disconnection is detected (_onDone / _onError).
  ///
  /// Starts the grace window and begins silent reconnect attempts.
  /// Does NOT change any visible UI state — the ConnectionService
  /// remains in [AppConnectionState.connected] during this period.
  void onDisconnected() {
    if (_state != _GuardState.idle) return;
    _state = _GuardState.graceActive;
    _retryCount = 0;

    final window =
        _appInBackground ? kGraceWindowBackground : kGraceWindowForeground;
    _log.info(
        '⏳ Grace window 开始: ${window.inMilliseconds}ms '
        '(background=$_appInBackground)');

    // Attempt silent reconnect immediately
    _attemptSilent();

    // Arm fallback timer — if grace expires, go visible
    _graceTimer = Timer(window, () {
      if (_state == _GuardState.graceActive) {
        _log.warning('⏳ Grace window 超时 (${window.inMilliseconds}ms), '
            '降级到可见重连');
        _retryTimer?.cancel();
        _state = _GuardState.visibleReconnect;
        onVisibleReconnect();
      }
    });
  }

  /// Attempt a single silent reconnect, retry on failure.
  Future<void> _attemptSilent() async {
    if (_state != _GuardState.graceActive) return;
    _retryCount++;

    if (_retryCount > kMaxSilentRetries) {
      _log.warning('静默重连达到上限 ($kMaxSilentRetries 次), 等待 grace 超时');
      return;
    }

    _log.fine('静默重连尝试 #$_retryCount/$kMaxSilentRetries');

    try {
      final success = await onSilentReconnect();
      if (success && _state == _GuardState.graceActive) {
        _log.info('✅ Grace window 内静默重连成功 (第 $_retryCount 次)');
        _graceTimer?.cancel();
        _retryTimer?.cancel();
        _state = _GuardState.idle;
        onSilentSuccess();
        return;
      }
    } catch (e) {
      _log.fine('静默重连异常: $e');
    }

    // Schedule retry if still in grace
    if (_state == _GuardState.graceActive) {
      _retryTimer?.cancel();
      _retryTimer = Timer(kSilentRetryInterval, _attemptSilent);
    }
  }

  /// Called when app returns to foreground while grace is active.
  ///
  /// If we were using the extended background grace window, shorten it
  /// to the foreground window since the user is now looking.
  /// Also immediately triggers a silent reconnect attempt since all
  /// timers were frozen by the OS while in background.
  void onAppResumed() {
    _appInBackground = false;
    if (_state == _GuardState.graceActive) {
      // User is back — immediately attempt reconnect (timers were frozen
      // by iOS/Android while in background, so retry loop was paused).
      _attemptSilent();

      // Also set a fallback timer: if silent reconnect doesn't succeed
      // within 2 seconds, fall back to visible reconnect.
      _graceTimer?.cancel();
      _graceTimer = Timer(kGraceWindowForeground, () {
        if (_state == _GuardState.graceActive) {
          _log.warning('⏳ Grace window 超时 (前台缩短), 降级到可见重连');
          _retryTimer?.cancel();
          _state = _GuardState.visibleReconnect;
          onVisibleReconnect();
        }
      });
    }
  }

  /// Reset to idle state.
  ///
  /// Called when the connection is fully re-established (either
  /// through grace-window silent reconnect or visible reconnect).
  void reset() {
    _graceTimer?.cancel();
    _retryTimer?.cancel();
    _state = _GuardState.idle;
    _retryCount = 0;
  }

  /// Cancel all timers and reset state. Call on dispose.
  void dispose() {
    _graceTimer?.cancel();
    _retryTimer?.cancel();
    _state = _GuardState.idle;
  }
}
