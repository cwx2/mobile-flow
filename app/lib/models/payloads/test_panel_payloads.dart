/// test_panel_payloads.dart — Payload models for Test Panel protocol messages.
///
/// Phase 1 covers script execution payloads only.
/// Future phases will add API proxy, preview, screenshot, and visual diff.
library;

/// Payload for `script.run` — execute a command on the Agent.
///
/// Sent by the App to request command execution. The command runs
/// in a subprocess with optional working directory and env overrides.
class ScriptRunPayload {
  final String command;
  final String? workingDirectory;
  final Map<String, String>? env;

  const ScriptRunPayload({
    required this.command,
    this.workingDirectory,
    this.env,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'command': command};
    if (workingDirectory != null) {
      json['working_directory'] = workingDirectory;
    }
    if (env != null) {
      json['env'] = env;
    }
    return json;
  }
}

/// Payload for `script.output` — streaming output chunk from Agent.
///
/// Received when stdout/stderr data becomes available from the
/// running subprocess.
class ScriptOutputPayload {
  /// Which output stream produced this data ("stdout" or "stderr").
  final String stream;

  /// The output text content.
  final String data;

  const ScriptOutputPayload({
    required this.stream,
    required this.data,
  });

  factory ScriptOutputPayload.fromJson(Map<String, dynamic> json) {
    return ScriptOutputPayload(
      stream: json['stream'] as String? ?? 'stdout',
      data: json['data'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'stream': stream,
        'data': data,
      };
}

/// Payload for `script.done` — command completed notification.
///
/// Received when the subprocess terminates, regardless of whether
/// it completed normally, was killed, or errored.
class ScriptDonePayload {
  /// Process exit code (0 = success).
  final int exitCode;

  /// Termination reason: "completed", "killed", or "error".
  final String status;

  /// Optional error description when status is "error".
  final String? errorMessage;

  const ScriptDonePayload({
    required this.exitCode,
    required this.status,
    this.errorMessage,
  });

  factory ScriptDonePayload.fromJson(Map<String, dynamic> json) {
    return ScriptDonePayload(
      exitCode: json['exit_code'] as int? ?? -1,
      status: json['status'] as String? ?? 'error',
      errorMessage: json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'exit_code': exitCode,
      'status': status,
    };
    if (errorMessage != null) {
      json['error_message'] = errorMessage;
    }
    return json;
  }
}

/// Payload for `script.stop` — request termination of running command.
///
/// Sent by the App to request graceful stop of the running command.
class ScriptStopPayload {
  final String reason;

  const ScriptStopPayload({this.reason = 'user_initiated'});

  Map<String, dynamic> toJson() => {'reason': reason};
}
