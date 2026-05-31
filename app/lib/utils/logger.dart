/// Structured logging utilities using Dart's standard `logging` package.
///
/// Provides a thin wrapper for consistent log initialization and per-module
/// logger creation. Mirrors the Python agent's loguru pattern:
///
/// | Dart Level      | Python Level | Usage                        |
/// |-----------------|-------------|------------------------------|
/// | `_log.fine()`   | `debug()`   | Debug details, param values  |
/// | `_log.info()`   | `info()`    | Business milestones          |
/// | `_log.warning()`| `warning()` | Recoverable anomalies        |
/// | `_log.severe()` | `error()`   | Functional failures          |
///
/// Usage in any file:
/// ```dart
/// import 'package:mobileflow/utils/logger.dart';  // package name is legacy, see pubspec.yaml
/// final _log = getLogger('WebSocket');
/// _log.info('连接成功: $host:$port');
/// ```
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Get a named logger instance for a module.
///
/// Each module should call this once at file level:
/// ```dart
/// final _log = getLogger('ChatState');
/// ```
Logger getLogger(String name) => Logger(name);

/// Initialize the root logger. Call once in `main()`.
///
/// In debug mode, logs at [Level.ALL] (everything visible).
/// In release mode, logs at [Level.INFO] (fine/debug suppressed).
///
/// Output format: `HH:mm:ss | LEVEL   | [Name] message`
void initLogging() {
  Logger.root.level = kDebugMode ? Level.ALL : Level.INFO;

  Logger.root.onRecord.listen((record) {
    final time = '${record.time.hour.toString().padLeft(2, '0')}:'
        '${record.time.minute.toString().padLeft(2, '0')}:'
        '${record.time.second.toString().padLeft(2, '0')}';
    final level = record.level.name.padRight(7);
    final msg = '$time | $level | [${record.loggerName}] ${record.message}';

    // Use developer.log for structured output in DevTools,
    // fall back to debugPrint for console visibility.
    if (kDebugMode) {
      developer.log(
        record.message,
        time: record.time,
        level: record.level.value,
        name: record.loggerName,
        error: record.error,
        stackTrace: record.stackTrace,
      );
    }
    // Console fallback — only in debug mode to avoid leaking logs in release.
    // developer.log above already covers DevTools output.
    if (kDebugMode) {
      debugPrint(msg);
    }
  });
}
