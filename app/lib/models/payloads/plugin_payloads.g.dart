// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/plugin.py

/// Payload for ``plugin.list`` — list installed plugins.
class PluginListPayload {
  final String? capability;

  const PluginListPayload({
    this.capability = null,
  });

  factory PluginListPayload.fromJson(Map<String, dynamic> json) {
    return PluginListPayload(
      capability: json['capability'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'capability': capability,
      };
}

/// Payload for ``plugin.list.result`` — plugin list.
class PluginListResultPayload {
  final List<Map<String, dynamic>> plugins;

  const PluginListResultPayload({
    this.plugins = const [],
  });

  factory PluginListResultPayload.fromJson(Map<String, dynamic> json) {
    return PluginListResultPayload(
      plugins: (json['plugins'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'plugins': plugins,
      };
}

/// Payload for ``plugin.enable`` — enable a plugin.
class PluginEnablePayload {
  final String pluginId;

  const PluginEnablePayload({
    required this.pluginId,
  });

  factory PluginEnablePayload.fromJson(Map<String, dynamic> json) {
    return PluginEnablePayload(
      pluginId: json['plugin_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'plugin_id': pluginId,
      };
}

/// Payload for ``plugin.disable`` — disable a plugin.
class PluginDisablePayload {
  final String pluginId;

  const PluginDisablePayload({
    required this.pluginId,
  });

  factory PluginDisablePayload.fromJson(Map<String, dynamic> json) {
    return PluginDisablePayload(
      pluginId: json['plugin_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'plugin_id': pluginId,
      };
}

/// Payload for ``plugin.uninstall`` — uninstall a plugin.
class PluginUninstallPayload {
  final String pluginId;

  const PluginUninstallPayload({
    required this.pluginId,
  });

  factory PluginUninstallPayload.fromJson(Map<String, dynamic> json) {
    return PluginUninstallPayload(
      pluginId: json['plugin_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'plugin_id': pluginId,
      };
}

/// Payload for ``plugin.state_changed`` — plugin state change.
class PluginStateChangedPayload {
  final String pluginId;
  final String state;
  final String? error;

  const PluginStateChangedPayload({
    required this.pluginId,
    required this.state,
    this.error = null,
  });

  factory PluginStateChangedPayload.fromJson(Map<String, dynamic> json) {
    return PluginStateChangedPayload(
      pluginId: json['plugin_id'] as String? ?? '',
      state: json['state'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'plugin_id': pluginId,
        'state': state,
        'error': error,
      };
}

/// Payload for ``plugin.install`` — install a plugin.
class PluginInstallPayload {
  final String sourceType;
  final String sourceUrl;

  const PluginInstallPayload({
    required this.sourceType,
    required this.sourceUrl,
  });

  factory PluginInstallPayload.fromJson(Map<String, dynamic> json) {
    return PluginInstallPayload(
      sourceType: json['source_type'] as String? ?? '',
      sourceUrl: json['source_url'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'source_type': sourceType,
        'source_url': sourceUrl,
      };
}

/// Payload for ``plugin.install.result`` — install outcome.
class PluginInstallResultPayload {
  final bool success;
  final String message;
  final String? pluginId;

  const PluginInstallResultPayload({
    required this.success,
    this.message = '',
    this.pluginId = null,
  });

  factory PluginInstallResultPayload.fromJson(Map<String, dynamic> json) {
    return PluginInstallResultPayload(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      pluginId: json['plugin_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        'plugin_id': pluginId,
      };
}

/// Payload for ``plugin.config.get`` — get plugin configuration.
class PluginConfigGetPayload {
  final String pluginId;

  const PluginConfigGetPayload({
    required this.pluginId,
  });

  factory PluginConfigGetPayload.fromJson(Map<String, dynamic> json) {
    return PluginConfigGetPayload(
      pluginId: json['plugin_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'plugin_id': pluginId,
      };
}

/// Payload for ``plugin.config.get.result`` — plugin configuration.
class PluginConfigGetResultPayload {
  final String pluginId;
  final Map<String, dynamic> config;

  const PluginConfigGetResultPayload({
    required this.pluginId,
    this.config = const {},
  });

  factory PluginConfigGetResultPayload.fromJson(Map<String, dynamic> json) {
    return PluginConfigGetResultPayload(
      pluginId: json['plugin_id'] as String? ?? '',
      config: Map<String, dynamic>.from(json['config'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'plugin_id': pluginId,
        'config': config,
      };
}

/// Payload for ``plugin.config.set`` — set plugin configuration.
class PluginConfigSetPayload {
  final String pluginId;
  final Map<String, dynamic> config;

  const PluginConfigSetPayload({
    required this.pluginId,
    required this.config,
  });

  factory PluginConfigSetPayload.fromJson(Map<String, dynamic> json) {
    return PluginConfigSetPayload(
      pluginId: json['plugin_id'] as String? ?? '',
      config: Map<String, dynamic>.from(json['config'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'plugin_id': pluginId,
        'config': config,
      };
}

/// Payload for ``plugin.config.set.result`` — set result.
class PluginConfigSetResultPayload {
  final bool success;
  final String? error;

  const PluginConfigSetResultPayload({
    required this.success,
    this.error = null,
  });

  factory PluginConfigSetResultPayload.fromJson(Map<String, dynamic> json) {
    return PluginConfigSetResultPayload(
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'error': error,
      };
}
