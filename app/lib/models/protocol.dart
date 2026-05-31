/// protocol.dart — WebSocket data models and envelope.
///
/// Dart-side protocol definitions for App-Agent communication.
/// MessageType constants are auto-generated in protocol_types.g.dart
/// from the Python mobileflow_protocol package (single source of truth).
///
/// This file contains hand-written classes that require Dart-specific
/// logic (fromJson factories, default values, etc.).
library;

// Re-export auto-generated message types so existing imports keep working.
// Files that `import 'protocol.dart'` get MessageType without extra imports.
export 'protocol_types.g.dart';

/// WebSocket message envelope.
///
/// Every message exchanged over the WebSocket is wrapped in this
/// structure with a unique [id], a [type] from [MessageType],
/// a millisecond [timestamp], and an arbitrary JSON [payload].
class WsMessage {
  final String id;
  final String type;
  final int timestamp;
  final Map<String, dynamic> payload;

  WsMessage({
    String? id,
    required this.type,
    int? timestamp,
    this.payload = const {},
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toRadixString(36),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  /// Deserialize from a JSON map received over WebSocket.
  factory WsMessage.fromJson(Map<String, dynamic> json) {
    return WsMessage(
      id: json['id'] as String?,
      type: json['type'] as String,
      timestamp: json['timestamp'] as int?,
      payload: Map<String, dynamic>.from(json['payload'] ?? {}),
    );
  }

  /// Serialize to a JSON map for sending over WebSocket.
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'timestamp': timestamp,
        'payload': payload,
      };
}

/// CLI capability declaration (mirrors ACP AgentCapabilities exactly).
///
/// Parsed from `cli.list.result` adapter entries or `cli.status`
/// updates. Used by the UI to conditionally enable features
/// (e.g. image attachment, session list, MCP support).
class CliCapabilities {
  // ACP top-level
  final bool supportsSessionLoad;

  // ACP promptCapabilities
  final bool supportsImage;
  final bool supportsAudio;
  final bool supportsEmbeddedContext;

  // ACP sessionCapabilities
  final bool supportsSessionList;
  final bool supportsSessionClose;
  final bool supportsSessionFork;
  final bool supportsSessionResume;

  // ACP mcpCapabilities
  final bool supportsMcpHttp;
  final bool supportsMcpSse;

  // Available modes (from new_session response)
  final List<Map<String, dynamic>> availableModes;

  const CliCapabilities({
    this.supportsSessionLoad = false,
    this.supportsImage = false,
    this.supportsAudio = false,
    this.supportsEmbeddedContext = false,
    this.supportsSessionList = false,
    this.supportsSessionClose = false,
    this.supportsSessionFork = false,
    this.supportsSessionResume = false,
    this.supportsMcpHttp = false,
    this.supportsMcpSse = false,
    this.availableModes = const [],
  });

  /// Deserialize from a JSON map with snake_case keys.
  factory CliCapabilities.fromJson(Map<String, dynamic> json) {
    return CliCapabilities(
      supportsSessionLoad: json['supports_session_load'] as bool? ?? false,
      supportsImage: json['supports_image'] as bool? ?? false,
      supportsAudio: json['supports_audio'] as bool? ?? false,
      supportsEmbeddedContext: json['supports_embedded_context'] as bool? ?? false,
      supportsSessionList: json['supports_session_list'] as bool? ?? false,
      supportsSessionClose: json['supports_session_close'] as bool? ?? false,
      supportsSessionFork: json['supports_session_fork'] as bool? ?? false,
      supportsSessionResume: json['supports_session_resume'] as bool? ?? false,
      supportsMcpHttp: json['supports_mcp_http'] as bool? ?? false,
      supportsMcpSse: json['supports_mcp_sse'] as bool? ?? false,
      availableModes: (json['available_modes'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }

  /// Parse from a `cli.list.result` adapter entry (snake_case keys at top level).
  factory CliCapabilities.fromAdapter(Map<String, dynamic> adapter) {
    return CliCapabilities.fromJson(adapter);
  }

  /// Empty capabilities (all flags false, no modes).
  static const empty = CliCapabilities();
}


/// ACP session config option (select or boolean type).
///
/// Represents a single configurable setting exposed by the ACP provider,
/// such as model selection or feature toggles.
class ConfigOption {
  final String id;
  final String name;
  final String type; // "select" | "boolean"
  final String? description;
  final String? category;
  final dynamic currentValue; // String for select, bool for boolean
  final List<ConfigOptionValue>? options; // only for select type

  const ConfigOption({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.category,
    this.currentValue,
    this.options,
  });

  /// Deserialize from a JSON map.
  ///
  /// Handles both flat option lists and nested group structures.
  factory ConfigOption.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'select';
    List<ConfigOptionValue>? options;
    final rawOptions = json['options'];
    if (rawOptions is List) {
      // Flat list of options
      options = rawOptions
          .map((o) => ConfigOptionValue.fromJson(Map<String, dynamic>.from(o as Map)))
          .toList();
    }
    return ConfigOption(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: type,
      description: json['description'] as String?,
      category: json['category'] as String?,
      currentValue: json['currentValue'] ?? json['current_value'],
      options: options,
    );
  }
}

/// A single selectable value within a [ConfigOption] of type "select".
class ConfigOptionValue {
  final String value;
  final String name;
  final String? description;

  const ConfigOptionValue({
    required this.value,
    required this.name,
    this.description,
  });

  /// Deserialize from a JSON map.
  factory ConfigOptionValue.fromJson(Map<String, dynamic> json) {
    return ConfigOptionValue(
      value: json['value'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
    );
  }
}
