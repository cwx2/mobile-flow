// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/state.py

/// Payload for ``status.ping`` — heartbeat ping.
class StatusPingPayload {
  const StatusPingPayload();

  factory StatusPingPayload.fromJson(Map<String, dynamic> json) {
    return const StatusPingPayload();
  }

  Map<String, dynamic> toJson() => {
      };
}

/// Payload for ``status.pong`` — heartbeat pong.
class StatusPongPayload {
  const StatusPongPayload();

  factory StatusPongPayload.fromJson(Map<String, dynamic> json) {
    return const StatusPongPayload();
  }

  Map<String, dynamic> toJson() => {
      };
}

/// Payload for ``state.push`` — cached state update.
class StatePushPayload {
  final String key;
  final dynamic data;

  const StatePushPayload({
    required this.key,
    required this.data,
  });

  factory StatePushPayload.fromJson(Map<String, dynamic> json) {
    return StatePushPayload(
      key: json['key'] as String? ?? '',
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'data': data,
      };
}

/// Payload for ``confirm.request`` — confirm dangerous operation.
class ConfirmRequestPayload {
  final String message;
  final String confirmId;

  const ConfirmRequestPayload({
    required this.message,
    required this.confirmId,
  });

  factory ConfirmRequestPayload.fromJson(Map<String, dynamic> json) {
    return ConfirmRequestPayload(
      message: json['message'] as String? ?? '',
      confirmId: json['confirm_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'message': message,
        'confirm_id': confirmId,
      };
}

/// Payload for ``confirm.response`` — user confirmation.
class ConfirmResponsePayload {
  final String confirmId;
  final bool confirmed;

  const ConfirmResponsePayload({
    required this.confirmId,
    required this.confirmed,
  });

  factory ConfirmResponsePayload.fromJson(Map<String, dynamic> json) {
    return ConfirmResponsePayload(
      confirmId: json['confirm_id'] as String? ?? '',
      confirmed: json['confirmed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'confirm_id': confirmId,
        'confirmed': confirmed,
      };
}

/// Payload for ``mode.set`` — switch ACP session mode.
class ModeSetPayload {
  final String cli;
  final String modeId;

  const ModeSetPayload({
    required this.cli,
    required this.modeId,
  });

  factory ModeSetPayload.fromJson(Map<String, dynamic> json) {
    return ModeSetPayload(
      cli: json['cli'] as String? ?? '',
      modeId: json['mode_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'mode_id': modeId,
      };
}

/// Payload for ``config.set`` — set ACP config option value.
class ConfigSetPayload {
  final String cli;
  final String configId;
  final dynamic value;

  const ConfigSetPayload({
    required this.cli,
    required this.configId,
    required this.value,
  });

  factory ConfigSetPayload.fromJson(Map<String, dynamic> json) {
    return ConfigSetPayload(
      cli: json['cli'] as String? ?? '',
      configId: json['config_id'] as String? ?? '',
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'config_id': configId,
        'value': value,
      };
}
