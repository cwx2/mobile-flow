/// foreground_service.dart — Android Foreground Service bridge.
///
/// Communicates with the native [KeepAliveService] via MethodChannel
/// to start/stop the foreground service and dynamically update the
/// notification content during AI streaming.
///
/// Streaming text is accumulated into a line buffer and flushed to
/// the notification in real-time, creating a typewriter effect where
/// words appear one by one. When a line is full (~35 chars), the
/// buffer resets and a new line begins.
///
/// On non-Android platforms all calls are silent no-ops.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../utils/logger.dart';

final _log = getLogger('ForegroundService');

/// Static utility for managing the Android Foreground Service.
///
/// Wraps the native MethodChannel ("com.mobileflow.app/keepalive")
/// and provides high-level methods for the WebSocket lifecycle and
/// AI streaming state updates.
///
/// All methods are safe to call on any platform — non-Android calls
/// return immediately without side effects.
class ForegroundService {
  ForegroundService._(); // Prevent instantiation

  static const _channel = MethodChannel('com.mobileflow.app/keepalive');

  static bool _running = false;

  /// Timer for auto-reverting "done" state back to "connected".
  static Timer? _revertTimer;

  /// Throttle timer for streaming updates — prevents flooding the
  /// notification manager with too many updates per second.
  static Timer? _throttleTimer;

  // ── Line buffer for typewriter effect ──
  // Accumulates text chunks into a single line. When the line exceeds
  // [_maxLineChars], it resets and starts a new line. This creates
  // the visual effect of words appearing one by one, then the line
  // refreshing when full.
  static final _lineBuffer = StringBuffer();

  /// Max characters per notification line before resetting.
  ///
  /// Android notification contentText is single-line by default.
  /// ~35 Chinese chars or ~60 ASCII chars fit comfortably.
  static const _maxLineChars = 35;

  // ── Notification text (initialized from i18n via [init]) ──
  static const _titleDefault = 'MobileFlow';
  static String _textConnected = 'Connected · Coding assistant running';
  static String _titleStreaming = '✨ AI is responding...';
  static String _textDone = '✅ Response complete';

  /// Cache localized notification strings from the current locale.
  ///
  /// Call once from a widget that has [BuildContext] (e.g. HomeScreen)
  /// before the foreground service is started. Falls back to English
  /// defaults if never called.
  static void init(BuildContext context) {
    final s = S.of(context);
    _textConnected = s.foregroundServiceConnected;
    _titleStreaming = s.foregroundServiceStreaming;
    _textDone = s.foregroundServiceDone;
  }

  /// Start the foreground service with "connected" notification.
  ///
  /// Called when a WebSocket connection is successfully established.
  /// On Android 13+, requests POST_NOTIFICATIONS permission first.
  /// If already running, updates the notification to connected state.
  static Future<void> start() async {
    if (!Platform.isAndroid) return;

    try {
      if (_running) {
        await _update(_titleDefault, _textConnected);
        return;
      }

      // Android 13+ requires runtime notification permission
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      if (granted != true) {
        _log.warning('通知权限未授予，前台服务将静默运行');
        // Still start the service — it keeps the app alive even without
        // a visible notification on Android 13+.
      }

      await _channel.invokeMethod('start', {
        'title': _titleDefault,
        'text': _textConnected,
      });
      _running = true;
      _log.info('✅ 前台服务已启动');
    } catch (e) {
      _log.severe('前台服务启动失败: $e');
    }
  }

  /// Stop the foreground service and remove the notification.
  ///
  /// Called when the WebSocket connection is closed or the app
  /// is being disposed.
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (!_running) return;

    _revertTimer?.cancel();
    _revertTimer = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _lineBuffer.clear();

    try {
      await _channel.invokeMethod('stop');
      _running = false;
      _log.info('前台服务已停止');
    } catch (e) {
      _log.severe('前台服务停止失败: $e');
    }
  }

  /// Append a text chunk to the notification line buffer.
  ///
  /// Creates a typewriter effect: each chunk is appended to the
  /// current line and the notification updates in real-time. When
  /// the line exceeds [_maxLineChars], the buffer resets and a
  /// fresh line begins — giving the visual impression of text
  /// flowing line by line.
  ///
  /// Updates are throttled to every 150ms to balance smoothness
  /// with system resource usage.
  static void onStreamChunk(String text) {
    if (!Platform.isAndroid || !_running) return;

    _revertTimer?.cancel();

    // Append new text to the line buffer
    _lineBuffer.write(text);

    // If the line is full, reset to start a new line
    if (_lineBuffer.length > _maxLineChars) {
      // Keep only the tail portion so the transition feels smooth
      // instead of abruptly clearing to empty
      final overflow = _lineBuffer.toString();
      _lineBuffer.clear();
      // Start the new line with the last few chars for continuity
      final tail = overflow.length > 10
          ? overflow.substring(overflow.length - 10)
          : overflow;
      _lineBuffer.write(tail);
    }

    // Throttle notification updates to every 150ms
    if (_throttleTimer?.isActive ?? false) return;

    _throttleTimer = Timer(const Duration(milliseconds: 150), () {
      if (_running && _lineBuffer.isNotEmpty) {
        _update(_titleStreaming, _lineBuffer.toString());
      }
    });
  }

  /// Update notification to show "done" state, then auto-revert.
  ///
  /// Called when the AI finishes streaming. Shows "✅ 回复完成" for
  /// 3 seconds, then reverts to the idle "已连接" notification.
  static Future<void> onStreamDone() async {
    if (!Platform.isAndroid || !_running) return;

    _throttleTimer?.cancel();
    _lineBuffer.clear();

    await _update(_titleDefault, _textDone);

    // Auto-revert to connected state after 3 seconds
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 3), () {
      if (_running) {
        _update(_titleDefault, _textConnected);
      }
    });
  }

  /// Internal helper to update notification content.
  static Future<void> _update(String title, String text) async {
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'text': text,
      });
    } catch (e) {
      _log.warning('通知更新失败: $e');
    }
  }
}
