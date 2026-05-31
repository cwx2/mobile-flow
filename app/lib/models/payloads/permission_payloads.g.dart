// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/permission.py

/// Payload for ``permission.request`` — Agent pushes permission request to App.
class PermissionRequestPayload {
  final String requestId;
  final String toolName;
  final String? toolKind;
  final String? description;
  final List<Map<String, dynamic>> options;

  const PermissionRequestPayload({
    required this.requestId,
    required this.toolName,
    this.toolKind = null,
    this.description = null,
    this.options = const [],
  });

  factory PermissionRequestPayload.fromJson(Map<String, dynamic> json) {
    return PermissionRequestPayload(
      requestId: json['request_id'] as String? ?? '',
      toolName: json['tool_name'] as String? ?? '',
      toolKind: json['tool_kind'] as String?,
      description: json['description'] as String?,
      options: (json['options'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'tool_name': toolName,
        'tool_kind': toolKind,
        'description': description,
        'options': options,
      };
}

/// Payload for ``permission.response`` — App responds with user decision.
class PermissionResponsePayload {
  final String requestId;
  final bool approved;
  final String optionId;

  const PermissionResponsePayload({
    required this.requestId,
    required this.approved,
    this.optionId = 'allow_once',
  });

  factory PermissionResponsePayload.fromJson(Map<String, dynamic> json) {
    return PermissionResponsePayload(
      requestId: json['request_id'] as String? ?? '',
      approved: json['approved'] as bool? ?? false,
      optionId: json['option_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'approved': approved,
        'option_id': optionId,
      };
}

/// Payload for ``permission.policy`` — Agent pushes permission policy update.
class PermissionPolicyPayload {
  final Map<String, dynamic> policy;

  const PermissionPolicyPayload({
    this.policy = const {},
  });

  factory PermissionPolicyPayload.fromJson(Map<String, dynamic> json) {
    return PermissionPolicyPayload(
      policy: Map<String, dynamic>.from(json['policy'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'policy': policy,
      };
}
