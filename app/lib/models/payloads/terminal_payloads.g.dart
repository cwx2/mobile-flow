// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/terminal.py

/// Payload for ``terminal.start`` — start a PTY terminal session.
class TerminalStartPayload {
  final String cli;
  final int cols;
  final int rows;

  const TerminalStartPayload({
    required this.cli,
    this.cols = 80,
    this.rows = 24,
  });

  factory TerminalStartPayload.fromJson(Map<String, dynamic> json) {
    return TerminalStartPayload(
      cli: json['cli'] as String? ?? '',
      cols: json['cols'] as int? ?? 0,
      rows: json['rows'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'cli': cli,
        'cols': cols,
        'rows': rows,
      };
}

/// Payload for ``terminal.started`` — terminal session ready.
class TerminalStartedPayload {
  final String terminalId;
  final String cli;

  const TerminalStartedPayload({
    this.terminalId = '',
    this.cli = '',
  });

  factory TerminalStartedPayload.fromJson(Map<String, dynamic> json) {
    return TerminalStartedPayload(
      terminalId: json['terminal_id'] as String? ?? '',
      cli: json['cli'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'terminal_id': terminalId,
        'cli': cli,
      };
}

/// Payload for ``terminal.input`` — user keyboard input.
class TerminalInputPayload {
  final String data;

  const TerminalInputPayload({
    required this.data,
  });

  factory TerminalInputPayload.fromJson(Map<String, dynamic> json) {
    return TerminalInputPayload(
      data: json['data'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'data': data,
      };
}

/// Payload for ``terminal.output`` — terminal output data.
class TerminalOutputPayload {
  final String data;
  final String terminalId;
  final String source;
  final String text;

  const TerminalOutputPayload({
    this.data = '',
    this.terminalId = '',
    this.source = '',
    this.text = '',
  });

  factory TerminalOutputPayload.fromJson(Map<String, dynamic> json) {
    return TerminalOutputPayload(
      data: json['data'] as String? ?? '',
      terminalId: json['terminal_id'] as String? ?? '',
      source: json['source'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'data': data,
        'terminal_id': terminalId,
        'source': source,
        'text': text,
      };
}

/// Payload for ``terminal.resize`` — resize terminal dimensions.
class TerminalResizePayload {
  final int cols;
  final int rows;

  const TerminalResizePayload({
    required this.cols,
    required this.rows,
  });

  factory TerminalResizePayload.fromJson(Map<String, dynamic> json) {
    return TerminalResizePayload(
      cols: json['cols'] as int? ?? 0,
      rows: json['rows'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'cols': cols,
        'rows': rows,
      };
}

/// Payload for ``terminal.stop`` — stop terminal session.
class TerminalStopPayload {
  const TerminalStopPayload();

  factory TerminalStopPayload.fromJson(Map<String, dynamic> json) {
    return const TerminalStopPayload();
  }

  Map<String, dynamic> toJson() => {
      };
}
