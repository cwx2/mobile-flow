/// run_config_provider.dart — Run Configuration state management.
///
/// Holds the client-side state for run configurations: the configuration
/// list, running states, output buffers, and selected ID. Handles
/// incoming WebSocket messages from the Agent and notifies listeners
/// on state changes.
///
/// Consumed by:
///   - RunConfigListScreen (configuration list display)
///   - RunConfigOutputView (terminal output display)
library;

import 'package:flutter/foundation.dart';

import '../models/protocol.dart';
import '../models/run_configuration.dart';
import '../utils/logger.dart';

final _log = getLogger('RunConfigProvider');

/// Maximum number of output lines to keep per configuration buffer.
///
/// Prevents unbounded memory growth for long-running processes.
/// Oldest lines are trimmed when the limit is exceeded.
const int kMaxOutputLines = 500;

/// A single line of process output with metadata.
class OutputLine {
  /// The text content of this output line.
  final String text;

  /// Whether this line came from stderr (vs stdout).
  final bool isStderr;

  /// Optional before-run task prefix (e.g. "[Before 1/2]").
  final String? taskPrefix;

  const OutputLine({
    required this.text,
    this.isStderr = false,
    this.taskPrefix,
  });
}

/// State management for the Run Configuration system.
///
/// Extends [ChangeNotifier] to integrate with Provider pattern.
/// Handles incoming WebSocket messages and maintains:
/// - Configuration list (from Agent)
/// - Selected configuration ID
/// - Per-config running states
/// - Per-config output buffers (capped at [kMaxOutputLines])
class RunConfigProvider extends ChangeNotifier {
  /// All configurations received from the Agent.
  List<RunConfiguration> configurations = [];

  /// Currently selected configuration ID (null if none selected).
  String? selectedId;

  /// Running state per configuration ID.
  final Map<String, RunConfigState> runningStates = {};

  /// Output buffer per configuration ID (last N lines).
  final Map<String, List<OutputLine>> outputBuffers = {};

  /// Exit code per configuration ID (set when process stops).
  final Map<String, int?> exitCodes = {};

  /// Error message per configuration ID (set on failure).
  final Map<String, String?> errorMessages = {};

  /// Preview URL per configuration ID (set when preview reaches running).
  final Map<String, String?> previewUrls = {};

  /// Raw output listeners per configuration ID (for xterm-based views).
  /// Each listener receives the raw text chunk as-is (no line splitting).
  final Map<String, List<void Function(String)>> _rawOutputListeners = {};

  /// Register a raw output listener for a configuration.
  /// Returns a dispose function to unregister.
  VoidCallback addRawOutputListener(String configId, void Function(String) callback) {
    _rawOutputListeners.putIfAbsent(configId, () => []).add(callback);
    return () {
      _rawOutputListeners[configId]?.remove(callback);
    };
  }

  /// Dispatch an incoming WebSocket message to the appropriate handler.
  ///
  /// Returns true if the message was handled, false otherwise.
  bool handleMessage(WsMessage msg) {
    switch (msg.type) {
      case MessageType.runConfigListResult:
        _handleListResult(msg.payload);
        return true;
      case MessageType.runConfigCreated:
        _handleCreated(msg.payload);
        return true;
      case MessageType.runConfigUpdated:
        _handleUpdated(msg.payload);
        return true;
      case MessageType.runConfigDeleted:
        _handleDeleted(msg.payload);
        return true;
      case MessageType.runConfigChanged:
        _handleChanged(msg.payload);
        return true;
      case MessageType.runConfigOutput:
        _handleOutput(msg.payload);
        return true;
      case MessageType.runConfigStateChanged:
        _handleStateChanged(msg.payload);
        return true;
      case MessageType.runConfigStatusResult:
        _handleStatusResult(msg.payload);
        return true;
      default:
        return false;
    }
  }

  /// Get the running state for a configuration (defaults to idle).
  RunConfigState getState(String configId) =>
      runningStates[configId] ?? RunConfigState.idle;

  /// Get the output buffer for a configuration.
  List<OutputLine> getOutput(String configId) =>
      outputBuffers[configId] ?? const [];

  /// Clear the output buffer for a configuration.
  void clearOutput(String configId) {
    outputBuffers.remove(configId);
    notifyListeners();
  }

  // ── Message handlers ──

  void _handleListResult(Map<String, dynamic> payload) {
    _log.fine('收到配置列表');
    final configsJson = payload['configurations'] as List<dynamic>? ?? [];
    configurations = configsJson
        .map((e) => RunConfiguration.fromJson(e as Map<String, dynamic>))
        .toList();
    selectedId = payload['selected_id'] as String?;
    notifyListeners();
  }

  void _handleCreated(Map<String, dynamic> payload) {
    final configJson = payload['configuration'] as Map<String, dynamic>?;
    if (configJson == null) return;
    final config = RunConfiguration.fromJson(configJson);
    _log.info('配置已创建: ${config.name}');
    configurations.add(config);
    notifyListeners();
  }

  void _handleUpdated(Map<String, dynamic> payload) {
    final configJson = payload['configuration'] as Map<String, dynamic>?;
    if (configJson == null) return;
    final config = RunConfiguration.fromJson(configJson);
    _log.fine('配置已更新: ${config.name}');
    final index = configurations.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      configurations[index] = config;
    }
    notifyListeners();
  }

  void _handleDeleted(Map<String, dynamic> payload) {
    final configId = payload['config_id'] as String?;
    if (configId == null) return;
    _log.info('配置已删除: $configId');
    configurations.removeWhere((c) => c.id == configId);
    // Clean up associated state
    runningStates.remove(configId);
    outputBuffers.remove(configId);
    exitCodes.remove(configId);
    errorMessages.remove(configId);
    previewUrls.remove(configId);
    if (selectedId == configId) {
      selectedId = null;
    }
    notifyListeners();
  }

  void _handleChanged(Map<String, dynamic> payload) {
    _log.fine('配置列表变更广播');
    final configsJson = payload['configurations'] as List<dynamic>? ?? [];
    configurations = configsJson
        .map((e) => RunConfiguration.fromJson(e as Map<String, dynamic>))
        .toList();
    selectedId = payload['selected_id'] as String?;
    notifyListeners();
  }

  void _handleOutput(Map<String, dynamic> payload) {
    final configId = payload['config_id'] as String?;
    if (configId == null) return;

    final data = payload['data'] as String? ?? '';
    final stream = payload['stream'] as String? ?? 'stdout';
    final taskPrefix = payload['task_prefix'] as String?;

    final buffer = outputBuffers.putIfAbsent(configId, () => []);

    // Split by newlines to maintain line-by-line structure
    final lines = data.split('\n');
    for (final line in lines) {
      if (line.isNotEmpty || lines.length == 1) {
        buffer.add(OutputLine(
          text: line,
          isStderr: stream == 'stderr',
          taskPrefix: taskPrefix,
        ));
      }
    }

    // Trim oldest lines if buffer exceeds limit
    if (buffer.length > kMaxOutputLines) {
      buffer.removeRange(0, buffer.length - kMaxOutputLines);
    }

    // Notify raw output listeners (for xterm-based views)
    final rawListeners = _rawOutputListeners[configId];
    if (rawListeners != null) {
      final prefix = taskPrefix != null ? '$taskPrefix ' : '';
      for (final cb in rawListeners) {
        cb('$prefix$data');
      }
    }

    notifyListeners();
  }

  void _handleStateChanged(Map<String, dynamic> payload) {
    final configId = payload['config_id'] as String?;
    final stateStr = payload['state'] as String?;
    if (configId == null || stateStr == null) return;

    final state = RunConfigState.fromString(stateStr);
    _log.fine('状态变更: $configId → $stateStr');
    runningStates[configId] = state;

    // Track exit code and error message when stopped
    if (state == RunConfigState.stopped) {
      exitCodes[configId] = payload['exit_code'] as int?;
      errorMessages[configId] = payload['error_message'] as String?;
    }

    // Track preview URL when preview reaches running
    if (payload.containsKey('preview_url')) {
      previewUrls[configId] = payload['preview_url'] as String?;
    }

    // Clear output buffer when starting fresh
    if (state == RunConfigState.beforeRun || state == RunConfigState.starting) {
      outputBuffers[configId] = [];
      exitCodes.remove(configId);
      errorMessages.remove(configId);
    }

    notifyListeners();
  }

  void _handleStatusResult(Map<String, dynamic> payload) {
    final states = payload['states'] as Map<String, dynamic>? ?? {};
    _log.fine('状态查询结果: ${states.length} 个配置');
    for (final entry in states.entries) {
      runningStates[entry.key] = RunConfigState.fromString(entry.value as String);
    }
    notifyListeners();
  }
}
