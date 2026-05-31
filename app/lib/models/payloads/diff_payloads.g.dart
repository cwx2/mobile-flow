// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/diff.py

/// Payload for ``diff.preview`` — proposed diff for review.
class DiffPreviewPayload {
  final String filePath;
  final String? oldContent;
  final String newContent;

  const DiffPreviewPayload({
    required this.filePath,
    this.oldContent = null,
    required this.newContent,
  });

  factory DiffPreviewPayload.fromJson(Map<String, dynamic> json) {
    return DiffPreviewPayload(
      filePath: json['file_path'] as String? ?? '',
      oldContent: json['old_content'] as String?,
      newContent: json['new_content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'file_path': filePath,
        'old_content': oldContent,
        'new_content': newContent,
      };
}

/// Payload for ``diff.apply`` — accept proposed diff.
class DiffApplyPayload {
  final String filePath;
  final String newContent;

  const DiffApplyPayload({
    required this.filePath,
    required this.newContent,
  });

  factory DiffApplyPayload.fromJson(Map<String, dynamic> json) {
    return DiffApplyPayload(
      filePath: json['file_path'] as String? ?? '',
      newContent: json['new_content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'file_path': filePath,
        'new_content': newContent,
      };
}

/// Payload for ``diff.reject`` — reject proposed diff.
class DiffRejectPayload {
  final String filePath;

  const DiffRejectPayload({
    required this.filePath,
  });

  factory DiffRejectPayload.fromJson(Map<String, dynamic> json) {
    return DiffRejectPayload(
      filePath: json['file_path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'file_path': filePath,
      };
}
