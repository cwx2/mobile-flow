// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/session.py

/// Payload for ``session.list`` — request available sessions.
class SessionListPayload {
  final String cli;

  const SessionListPayload({
    required this.cli,
  });

  factory SessionListPayload.fromJson(Map<String, dynamic> json) {
    return SessionListPayload(
      cli: json['cli'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
      };
}

/// Payload for ``session.list.result`` — session list response.
class SessionListResultPayload {
  final List<Map<String, dynamic>> sessions;
  final String cli;

  const SessionListResultPayload({
    this.sessions = const [],
    this.cli = '',
  });

  factory SessionListResultPayload.fromJson(Map<String, dynamic> json) {
    return SessionListResultPayload(
      sessions: (json['sessions'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      cli: json['cli'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'sessions': sessions,
        'cli': cli,
      };
}

/// Payload for ``session.new`` — create a new session.
class SessionNewPayload {
  final String cli;

  const SessionNewPayload({
    required this.cli,
  });

  factory SessionNewPayload.fromJson(Map<String, dynamic> json) {
    return SessionNewPayload(
      cli: json['cli'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
      };
}

/// Payload for ``session.switch`` — switch to an existing session.
class SessionSwitchPayload {
  final String cli;
  final String sessionId;

  const SessionSwitchPayload({
    required this.cli,
    required this.sessionId,
  });

  factory SessionSwitchPayload.fromJson(Map<String, dynamic> json) {
    return SessionSwitchPayload(
      cli: json['cli'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'session_id': sessionId,
      };
}

/// Payload for ``session.close`` — close (delete) a session.
class SessionClosePayload {
  final String cli;
  final String sessionId;

  const SessionClosePayload({
    required this.cli,
    required this.sessionId,
  });

  factory SessionClosePayload.fromJson(Map<String, dynamic> json) {
    return SessionClosePayload(
      cli: json['cli'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'session_id': sessionId,
      };
}
