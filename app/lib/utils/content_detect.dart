/// content_detect.dart — Content detection utilities.
///
/// Detect content types (file paths, image data, etc.) for reuse across widgets.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'logger.dart';

final _log = getLogger('ContentDetect');

/// Check if a string looks like a file or directory path.
///
/// Returns true for both file paths (e.g. `src/main.dart`) and
/// directory paths (e.g. `myproject/agent`). Callers are
/// responsible for distinguishing files from directories when
/// deciding what action to take (open viewer vs browse tree).
bool isFilePath(String text) {
  if (text.contains('\n') || text.length > 200) return false;
  final trimmed = text.trim();
  return !text.contains(' ') &&
      (text.contains('/') || text.contains('.')) &&
      RegExp(r'[\w.\-]').hasMatch(trimmed);
}

/// Check if a path likely points to a file (has an extension).
///
/// Directory paths like `myproject/agent` return false.
/// File paths like `src/main.dart` return true.
/// Used by UI to decide between opening FileViewer vs FileBrowser.
bool looksLikeFile(String path) {
  final lastSegment = path.trim().split('/').last;
  return RegExp(r'\.\w{1,10}$').hasMatch(lastSegment);
}

/// Try to extract image bytes from JSON string.
/// Supports:
///   - int array: {source: {data: [255, 216, ...]}}
///   - base64 string: {type: "image", data: "/9j/4AAQ..."}
Uint8List? tryExtractImageBytes(String content) {
  try {
    // Quick check: must contain image-related keywords
    if (!content.contains('"image"') && !content.contains('"Image"') &&
        !content.contains('"jpeg"') && !content.contains('"png"') &&
        !content.contains('"data"')) {
      return null;
    }
    final json = jsonDecode(content);
    // Try int array (imageRead format)
    final bytes = _extractIntArray(json);
    if (bytes != null && bytes.isNotEmpty) {
      return Uint8List.fromList(bytes);
    }
    // Try base64 string (describe_screenshot format)
    final b64 = _extractBase64(json);
    if (b64 != null && b64.length > 100) {
      return Uint8List.fromList(base64Decode(b64));
    }
  } catch (e) {
    _log.fine('内容检测失败: $e');
  }
  return null;
}

/// Recursively find int array (image bytes) in JSON
List<int>? _extractIntArray(dynamic json) {
  if (json is Map) {
    if (json.containsKey('data') && json['data'] is List) {
      final data = json['data'] as List;
      if (data.isNotEmpty && data.first is int) {
        return data.cast<int>();
      }
    }
    for (final value in json.values) {
      final result = _extractIntArray(value);
      if (result != null) return result;
    }
  } else if (json is List) {
    for (final item in json) {
      final result = _extractIntArray(item);
      if (result != null) return result;
    }
  }
  return null;
}

/// Recursively find base64 image string in JSON
/// Looks for {type: "image", data: "base64..."} pattern
String? _extractBase64(dynamic json) {
  if (json is Map) {
    // Direct match: {type: "image", data: "..."}
    final type = json['type'];
    final data = json['data'];
    if (type == 'image' && data is String && data.length > 50) {
      return data;
    }
    // Recurse
    for (final value in json.values) {
      final result = _extractBase64(value);
      if (result != null) return result;
    }
  } else if (json is List) {
    for (final item in json) {
      final result = _extractBase64(item);
      if (result != null) return result;
    }
  }
  return null;
}
