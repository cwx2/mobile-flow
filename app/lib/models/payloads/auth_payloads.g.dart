// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/auth.py

/// Payload for ``auth.pair`` — initial device pairing request.
class AuthPairPayload {
  final String token;
  final String? deviceName;

  const AuthPairPayload({
    required this.token,
    this.deviceName = null,
  });

  factory AuthPairPayload.fromJson(Map<String, dynamic> json) {
    return AuthPairPayload(
      token: json['token'] as String? ?? '',
      deviceName: json['device_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'device_name': deviceName,
      };
}

/// Payload for ``auth.connect`` — reconnect with session token.
class AuthConnectPayload {
  final String sessionToken;
  final String? clientId;

  const AuthConnectPayload({
    required this.sessionToken,
    this.clientId = null,
  });

  factory AuthConnectPayload.fromJson(Map<String, dynamic> json) {
    return AuthConnectPayload(
      sessionToken: json['session_token'] as String? ?? '',
      clientId: json['client_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_token': sessionToken,
        'client_id': clientId,
      };
}

/// Payload for ``auth.result`` — authentication outcome.
class AuthResultPayload {
  final bool success;
  final String? sessionToken;
  final String? error;
  final String? secret;
  final bool? resumed;
  final String? cliState;
  final String? cliName;
  final String? clientId;
  final bool? shouldRepair;

  const AuthResultPayload({
    required this.success,
    this.sessionToken = null,
    this.error = null,
    this.secret = null,
    this.resumed = null,
    this.cliState = null,
    this.cliName = null,
    this.clientId = null,
    this.shouldRepair = null,
  });

  factory AuthResultPayload.fromJson(Map<String, dynamic> json) {
    return AuthResultPayload(
      success: json['success'] as bool? ?? false,
      sessionToken: json['session_token'] as String?,
      error: json['error'] as String?,
      secret: json['secret'] as String?,
      resumed: json['resumed'] as bool?,
      cliState: json['cli_state'] as String?,
      cliName: json['cli_name'] as String?,
      clientId: json['client_id'] as String?,
      shouldRepair: json['should_repair'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'session_token': sessionToken,
        'error': error,
        'secret': secret,
        'resumed': resumed,
        'cli_state': cliState,
        'cli_name': cliName,
        'client_id': clientId,
        'should_repair': shouldRepair,
      };
}

/// Payload for ``auth.submit`` — submit CLI auth credentials.
class AuthSubmitPayload {
  final String cli;
  final String methodId;
  final Map<String, String> data;

  const AuthSubmitPayload({
    required this.cli,
    required this.methodId,
    required this.data,
  });

  factory AuthSubmitPayload.fromJson(Map<String, dynamic> json) {
    return AuthSubmitPayload(
      cli: json['cli'] as String? ?? '',
      methodId: json['method_id'] as String? ?? '',
      data: Map<String, String>.from(json['data'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'method_id': methodId,
        'data': data,
      };
}
