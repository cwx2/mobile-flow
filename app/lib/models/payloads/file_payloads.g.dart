// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/file.py

/// Payload for ``file.tree`` — request directory tree.
class FileTreePayload {
  final String path;
  final int depth;

  const FileTreePayload({
    this.path = '/',
    this.depth = 2,
  });

  factory FileTreePayload.fromJson(Map<String, dynamic> json) {
    return FileTreePayload(
      path: json['path'] as String? ?? '',
      depth: json['depth'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'depth': depth,
      };
}

/// Payload for ``file.tree.result`` — directory tree data.
class FileTreeResultPayload {
  final List<Map<String, dynamic>> data;
  final String reqPath;

  const FileTreeResultPayload({
    this.data = const [],
    this.reqPath = '/',
  });

  factory FileTreeResultPayload.fromJson(Map<String, dynamic> json) {
    return FileTreeResultPayload(
      data: (json['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      reqPath: json['req_path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'data': data,
        'req_path': reqPath,
      };
}

/// Payload for ``file.read`` — request file content.
class FileReadPayload {
  final String path;

  const FileReadPayload({
    required this.path,
  });

  factory FileReadPayload.fromJson(Map<String, dynamic> json) {
    return FileReadPayload(
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
      };
}

/// Payload for ``file.read.result`` — file content response.
class FileReadResultPayload {
  final String path;
  final String? content;
  final String? language;
  final int lineCount;
  final String? error;

  const FileReadResultPayload({
    required this.path,
    this.content = null,
    this.language = null,
    this.lineCount = 0,
    this.error = null,
  });

  factory FileReadResultPayload.fromJson(Map<String, dynamic> json) {
    return FileReadResultPayload(
      path: json['path'] as String? ?? '',
      content: json['content'] as String?,
      language: json['language'] as String?,
      lineCount: json['line_count'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'content': content,
        'language': language,
        'line_count': lineCount,
        'error': error,
      };
}

/// Payload for ``file.write`` — write file content.
class FileWritePayload {
  final String path;
  final String content;

  const FileWritePayload({
    required this.path,
    required this.content,
  });

  factory FileWritePayload.fromJson(Map<String, dynamic> json) {
    return FileWritePayload(
      path: json['path'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'content': content,
      };
}

/// Payload for ``file.write.result`` — write result.
class FileWriteResultPayload {
  final bool success;
  final String path;

  const FileWriteResultPayload({
    required this.success,
    required this.path,
  });

  factory FileWriteResultPayload.fromJson(Map<String, dynamic> json) {
    return FileWriteResultPayload(
      success: json['success'] as bool? ?? false,
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'path': path,
      };
}

/// Payload for ``file.search`` — search files or content.
class FileSearchPayload {
  final String query;
  final bool searchContent;
  final bool isRegex;
  final bool caseSensitive;
  final bool wholeWord;

  const FileSearchPayload({
    required this.query,
    this.searchContent = false,
    this.isRegex = false,
    this.caseSensitive = false,
    this.wholeWord = false,
  });

  factory FileSearchPayload.fromJson(Map<String, dynamic> json) {
    return FileSearchPayload(
      query: json['query'] as String? ?? '',
      searchContent: json['search_content'] as bool? ?? false,
      isRegex: json['is_regex'] as bool? ?? false,
      caseSensitive: json['case_sensitive'] as bool? ?? false,
      wholeWord: json['whole_word'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        'search_content': searchContent,
        'is_regex': isRegex,
        'case_sensitive': caseSensitive,
        'whole_word': wholeWord,
      };
}

/// Payload for ``file.search.result`` — final search results.
class FileSearchResultPayload {
  final List<Map<String, dynamic>> results;
  final String query;

  const FileSearchResultPayload({
    this.results = const [],
    this.query = '',
  });

  factory FileSearchResultPayload.fromJson(Map<String, dynamic> json) {
    return FileSearchResultPayload(
      results: (json['results'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      query: json['query'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'results': results,
        'query': query,
      };
}

/// Payload for ``file.search.stream`` — streaming search results.
class FileSearchStreamPayload {
  final List<Map<String, dynamic>> results;
  final int total;

  const FileSearchStreamPayload({
    this.results = const [],
    this.total = 0,
  });

  factory FileSearchStreamPayload.fromJson(Map<String, dynamic> json) {
    return FileSearchStreamPayload(
      results: (json['results'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      total: json['total'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'results': results,
        'total': total,
      };
}

/// Payload for ``file.create`` — create a new file or directory.
class FileCreatePayload {
  final String path;
  final String name;
  final String type;

  const FileCreatePayload({
    this.path = '',
    this.name = '',
    this.type = 'file',
  });

  factory FileCreatePayload.fromJson(Map<String, dynamic> json) {
    return FileCreatePayload(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'type': type,
      };
}

/// Payload for ``file.create.result`` — create result.
class FileCreateResultPayload {
  final bool success;
  final String? path;
  final String? error;

  const FileCreateResultPayload({
    this.success = false,
    this.path = null,
    this.error = null,
  });

  factory FileCreateResultPayload.fromJson(Map<String, dynamic> json) {
    return FileCreateResultPayload(
      success: json['success'] as bool? ?? false,
      path: json['path'] as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'path': path,
        'error': error,
      };
}

/// Payload for ``file.rename`` — rename a file or directory.
class FileRenamePayload {
  final String path;
  final String newName;

  const FileRenamePayload({
    this.path = '',
    this.newName = '',
  });

  factory FileRenamePayload.fromJson(Map<String, dynamic> json) {
    return FileRenamePayload(
      path: json['path'] as String? ?? '',
      newName: json['new_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'new_name': newName,
      };
}

/// Payload for ``file.rename.result`` — rename result.
class FileRenameResultPayload {
  final bool success;
  final String? oldPath;
  final String? newPath;
  final String? error;

  const FileRenameResultPayload({
    this.success = false,
    this.oldPath = null,
    this.newPath = null,
    this.error = null,
  });

  factory FileRenameResultPayload.fromJson(Map<String, dynamic> json) {
    return FileRenameResultPayload(
      success: json['success'] as bool? ?? false,
      oldPath: json['old_path'] as String?,
      newPath: json['new_path'] as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'old_path': oldPath,
        'new_path': newPath,
        'error': error,
      };
}

/// Payload for ``file.delete`` — delete a file or directory.
class FileDeletePayload {
  final String path;

  const FileDeletePayload({
    this.path = '',
  });

  factory FileDeletePayload.fromJson(Map<String, dynamic> json) {
    return FileDeletePayload(
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
      };
}

/// Payload for ``file.delete.result`` — delete result.
class FileDeleteResultPayload {
  final bool success;
  final String? path;
  final String? error;

  const FileDeleteResultPayload({
    this.success = false,
    this.path = null,
    this.error = null,
  });

  factory FileDeleteResultPayload.fromJson(Map<String, dynamic> json) {
    return FileDeleteResultPayload(
      success: json['success'] as bool? ?? false,
      path: json['path'] as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'path': path,
        'error': error,
      };
}

/// Payload for ``file.changed`` — file system change notification.
class FileChangedPayload {
  final String path;
  final String change;

  const FileChangedPayload({
    required this.path,
    required this.change,
  });

  factory FileChangedPayload.fromJson(Map<String, dynamic> json) {
    return FileChangedPayload(
      path: json['path'] as String? ?? '',
      change: json['change'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'change': change,
      };
}
