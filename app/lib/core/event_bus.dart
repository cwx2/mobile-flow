/// event_bus.dart — App-side event bus for decoupled message dispatch.
///
/// Provides a unified publish/subscribe mechanism so that screens
/// only subscribe to the events they care about, instead of each
/// screen listening to the raw WebSocket message stream directly.
///
/// Usage:
///   final bus = context.read<AppEventBus>();
///   bus.on('file.changed', (data) { ... });
///   bus.off('file.changed', handler);

import 'package:flutter/foundation.dart';

import '../utils/logger.dart';

final _log = getLogger('EventBus');

/// Event handler callback type.
typedef EventHandler = void Function(Map<String, dynamic> data);

/// App-wide event bus built on [ChangeNotifier].
///
/// Supports persistent handlers via [on], one-shot handlers via [once],
/// and wildcard removal via [off]. Events are dispatched synchronously;
/// handler errors are caught and logged to avoid breaking the dispatch chain.
class AppEventBus extends ChangeNotifier {
  /// Event name → list of persistent handlers.
  final Map<String, List<EventHandler>> _handlers = {};

  /// Event name → list of one-shot handlers.
  final Map<String, List<EventHandler>> _onceHandlers = {};

  /// Register a persistent event handler for [event].
  void on(String event, EventHandler handler) {
    _handlers.putIfAbsent(event, () => []).add(handler);
  }

  /// Register a one-shot handler that auto-removes after first trigger.
  void once(String event, EventHandler handler) {
    _onceHandlers.putIfAbsent(event, () => []).add(handler);
  }

  /// Remove handler(s) for [event].
  ///
  /// If [handler] is null, removes all handlers for that event.
  void off(String event, [EventHandler? handler]) {
    if (handler == null) {
      _handlers.remove(event);
      _onceHandlers.remove(event);
    } else {
      _handlers[event]?.remove(handler);
    }
  }

  /// Emit an [event] with optional [data], notifying all subscribers.
  void emit(String event, [Map<String, dynamic>? data]) {
    final payload = data ?? {};

    // Persistent handlers
    for (final handler in List.of(_handlers[event] ?? [])) {
      try {
        handler(payload);
      } catch (e) {
        _log.severe('EventBus handler error [$event]: $e');
      }
    }

    // One-shot handlers (removed after execution)
    final once = _onceHandlers.remove(event);
    if (once != null) {
      for (final handler in once) {
        try {
          handler(payload);
        } catch (e) {
          _log.severe('EventBus once handler error [$event]: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    _handlers.clear();
    _onceHandlers.clear();
    super.dispose();
  }
}

/// Standard app-side event name constants.
///
/// Used with [AppEventBus] to decouple producers (WebSocketService)
/// from consumers (screens, widgets).
class AppEvents {
  // File changes (pushed by agent)
  static const fileCreated = 'file.created';
  static const fileModified = 'file.modified';
  static const fileDeleted = 'file.deleted';

  // Permission requests
  static const permissionRequest = 'permission.request';

  // Project switching
  static const projectSwitched = 'project.switched';

  // Sessions
  static const sessionCreated = 'session.created';
  static const sessionSwitched = 'session.switched';

  // Agent status
  static const agentStatusChanged = 'agent.status.changed';

  // ACP terminal output
  static const terminalOutput = 'terminal.output';

  // Chat lifecycle
  static const chatDone = 'chat.done';
  static const chatError = 'chat.error';

  // Navigation
  static const navigateToChat = 'navigate.chat';
  static const navigateToTerminal = 'navigate.terminal';
  static const navigateToTestPanel = 'navigate.test_panel';

  // Git state push (from cache layer auto-refresh)
  static const gitStatusPush = 'git.status.push';
  static const gitBranchesPush = 'git.branches.push';
  static const gitLogPush = 'git.log.push';
  static const gitProgressPush = 'git.progress.push';
}
