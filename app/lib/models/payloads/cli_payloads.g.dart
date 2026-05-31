// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/cli.py

/// Payload for ``cli.list`` — request list of CLI adapters.
class CliListPayload {
  final String? cli;

  const CliListPayload({
    this.cli = null,
  });

  factory CliListPayload.fromJson(Map<String, dynamic> json) {
    return CliListPayload(
      cli: json['cli'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
      };
}

/// Payload for ``cli.list.result`` — adapter list response.
class CliListResultPayload {
  final List<Map<String, dynamic>> adapters;
  final String defaultCli;
  final Map<String, dynamic>? actionResult;

  const CliListResultPayload({
    this.adapters = const [],
    this.defaultCli = '',
    this.actionResult = null,
  });

  factory CliListResultPayload.fromJson(Map<String, dynamic> json) {
    return CliListResultPayload(
      adapters: (json['adapters'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      defaultCli: json['default_cli'] as String? ?? '',
      actionResult: json['action_result'] != null ? Map<String, dynamic>.from(json['action_result'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'adapters': adapters,
        'default_cli': defaultCli,
        'action_result': actionResult,
      };
}

/// Payload for ``cli.switch`` — switch the active CLI adapter.
class CliSwitchPayload {
  final String cli;

  const CliSwitchPayload({
    this.cli = '',
  });

  factory CliSwitchPayload.fromJson(Map<String, dynamic> json) {
    return CliSwitchPayload(
      cli: json['cli'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
      };
}

/// Payload for ``cli.status`` — CLI lifecycle state notification.
class CliStatusPayload {
  final String cli;
  final String state;
  final String message;
  final Map<String, dynamic>? capabilities;
  final String? error;
  final List<Map<String, dynamic>>? authMethods;
  final String? authType;
  final String? deviceCodeUrl;
  final String? deviceCode;

  const CliStatusPayload({
    required this.cli,
    required this.state,
    required this.message,
    this.capabilities = null,
    this.error = null,
    this.authMethods = null,
    this.authType = null,
    this.deviceCodeUrl = null,
    this.deviceCode = null,
  });

  factory CliStatusPayload.fromJson(Map<String, dynamic> json) {
    return CliStatusPayload(
      cli: json['cli'] as String? ?? '',
      state: json['state'] as String? ?? '',
      message: json['message'] as String? ?? '',
      capabilities: json['capabilities'] != null ? Map<String, dynamic>.from(json['capabilities'] as Map) : null,
      error: json['error'] as String?,
      authMethods: (json['auth_methods'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      authType: json['auth_type'] as String?,
      deviceCodeUrl: json['device_code_url'] as String?,
      deviceCode: json['device_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'state': state,
        'message': message,
        'capabilities': capabilities,
        'error': error,
        'auth_methods': authMethods,
        'auth_type': authType,
        'device_code_url': deviceCodeUrl,
        'device_code': deviceCode,
      };
}

/// Payload for ``cli.retry`` — retry failed CLI initialization.
class CliRetryPayload {
  final String? cli;

  const CliRetryPayload({
    this.cli = null,
  });

  factory CliRetryPayload.fromJson(Map<String, dynamic> json) {
    return CliRetryPayload(
      cli: json['cli'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
      };
}

/// Payload for ``cli.install`` — install a CLI adapter.
class CliInstallPayload {
  final String cli;

  const CliInstallPayload({
    this.cli = '',
  });

  factory CliInstallPayload.fromJson(Map<String, dynamic> json) {
    return CliInstallPayload(
      cli: json['cli'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
      };
}

/// Payload for ``cli.install.result`` — install outcome.
class CliInstallResultPayload {
  final String cli;
  final bool success;
  final String message;

  const CliInstallResultPayload({
    this.cli = '',
    this.success = false,
    this.message = '',
  });

  factory CliInstallResultPayload.fromJson(Map<String, dynamic> json) {
    return CliInstallResultPayload(
      cli: json['cli'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'success': success,
        'message': message,
      };
}

/// Payload for ``cli.install.progress`` — install/uninstall step progress.
class CliInstallProgressPayload {
  final String cli;
  final int step;
  final int totalSteps;
  final String package;
  final String label;
  final String status;

  const CliInstallProgressPayload({
    this.cli = '',
    this.step = 0,
    this.totalSteps = 0,
    this.package = '',
    this.label = '',
    this.status = '',
  });

  factory CliInstallProgressPayload.fromJson(Map<String, dynamic> json) {
    return CliInstallProgressPayload(
      cli: json['cli'] as String? ?? '',
      step: json['step'] as int? ?? 0,
      totalSteps: json['total_steps'] as int? ?? 0,
      package: json['package'] as String? ?? '',
      label: json['label'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'step': step,
        'total_steps': totalSteps,
        'package': package,
        'label': label,
        'status': status,
      };
}

/// Payload for ``cli.uninstall`` — uninstall a CLI adapter.
class CliUninstallPayload {
  final String cli;

  const CliUninstallPayload({
    this.cli = '',
  });

  factory CliUninstallPayload.fromJson(Map<String, dynamic> json) {
    return CliUninstallPayload(
      cli: json['cli'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
      };
}

/// Payload for ``cli.uninstall.result`` — uninstall outcome.
class CliUninstallResultPayload {
  final String cli;
  final bool success;
  final String message;

  const CliUninstallResultPayload({
    this.cli = '',
    this.success = false,
    this.message = '',
  });

  factory CliUninstallResultPayload.fromJson(Map<String, dynamic> json) {
    return CliUninstallResultPayload(
      cli: json['cli'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'success': success,
        'message': message,
      };
}

/// Payload for ``cli.add`` — add a custom agent.
class CliAddPayload {
  final String name;
  final String command;
  final List<String> args;
  final String? displayName;

  const CliAddPayload({
    this.name = '',
    this.command = '',
    this.args = const [],
    this.displayName = null,
  });

  factory CliAddPayload.fromJson(Map<String, dynamic> json) {
    return CliAddPayload(
      name: json['name'] as String? ?? '',
      command: json['command'] as String? ?? '',
      args: (json['args'] as List? ?? []).map((e) => e as String).toList(),
      displayName: json['display_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'command': command,
        'args': args,
        'display_name': displayName,
      };
}

/// Payload for ``cli.remove`` — remove a custom agent.
class CliRemovePayload {
  final String name;

  const CliRemovePayload({
    this.name = '',
  });

  factory CliRemovePayload.fromJson(Map<String, dynamic> json) {
    return CliRemovePayload(
      name: json['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
      };
}

/// Payload for ``cli.commands`` — CLI-advertised slash commands.
///
/// Sent by the Agent when a CLI advertises available commands via ACP.
/// Uses replace semantics: each message replaces the previous command
/// list for that CLI adapter.
class CliCommandsPayload {
  final String cli;
  final List<Map<String, dynamic>> commands;

  const CliCommandsPayload({
    required this.cli,
    this.commands = const [],
  });

  factory CliCommandsPayload.fromJson(Map<String, dynamic> json) {
    return CliCommandsPayload(
      cli: json['cli'] as String? ?? '',
      commands: (json['commands'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'commands': commands,
      };
}
