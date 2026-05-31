/// loading_state.dart — Data-driven loading state mixin for screens.
///
/// Module: core/
/// Responsibility:
///   Provides a reusable loading state pattern that eliminates manual
///   `setState(() => _loading = true/false)` calls. Loading is derived
///   from whether data has arrived and whether an error has occurred.
///
///   Includes timeout protection to prevent infinite loading spinners
///   when the Agent is unreachable or the WebSocket drops silently.
///
/// Used by:
///   - GitScreen, FilesScreen, PluginScreen, and any future screen
///     that fetches data on init and needs a loading → content → error flow.
///
/// Design pattern: Mixin Pattern (same as StaggeredListAnimator)
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../utils/logger.dart';

final _log = getLogger('LoadingState');

/// Default timeout for data loading operations.
///
/// 15 seconds covers slow networks and WSL cold-start scenarios
/// while still failing fast enough for a good user experience.
const kLoadingTimeout = Duration(seconds: 15);

/// Default timeout error message shown to the user.
const kLoadingTimeoutMessage = '加载超时，请检查连接后重试';

/// Mixin that provides data-driven loading state management.
///
/// Instead of manually toggling a `bool _loading` flag, screens declare
/// when data has arrived ([markDataReceived]) or when a fresh load cycle
/// starts ([resetLoading]). The [isLoading] getter derives the current
/// state automatically:
///
///   isLoading = !dataReceived && loadingError.isEmpty
///
/// Includes a configurable timeout ([startLoadingTimeout]) that sets
/// [loadingError] if no data arrives within the deadline, preventing
/// infinite spinners.
///
/// Usage:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with LoadingStateMixin {
///   @override
///   void initState() {
///     super.initState();
///     _fetchData();
///   }
///
///   void _fetchData() {
///     setState(() => resetLoading());
///     startLoadingTimeout();
///     ws.requestSomeData();
///   }
///
///   void _onDataArrived() {
///     markDataReceived();
///     setState(() { /* update data fields */ });
///   }
///
///   @override
///   void dispose() {
///     disposeLoading();
///     super.dispose();
///   }
/// }
/// ```
mixin LoadingStateMixin<T extends StatefulWidget> on State<T> {
  bool _dataReceived = false;
  String _loadingError = '';
  Timer? _loadingTimeout;

  /// Whether the screen is in a loading state.
  ///
  /// True when no data has arrived yet AND no error has occurred.
  /// Automatically becomes false when [markDataReceived] is called
  /// or when [loadingError] is set (timeout / explicit error).
  bool get isLoading => !_dataReceived && _loadingError.isEmpty;

  /// Current loading error message (empty string = no error).
  ///
  /// Set by [startLoadingTimeout] on expiry, or manually via
  /// [setLoadingError] for custom error scenarios (e.g. server
  /// returned an error response instead of data).
  String get loadingError => _loadingError;

  /// Whether data has been received at least once in the current
  /// loading cycle. Useful for distinguishing "empty result" from
  /// "never loaded".
  bool get dataReceived => _dataReceived;

  /// Mark that primary data has arrived, ending the loading state.
  ///
  /// Cancels any active timeout timer. Call this in the message
  /// handler when the expected response arrives.
  void markDataReceived() {
    _dataReceived = true;
    _cancelTimer();
  }

  /// Reset to a fresh loading cycle.
  ///
  /// Clears [dataReceived] and [loadingError], making [isLoading]
  /// return true again. Call this before requesting new data
  /// (refresh, project switch, etc.).
  ///
  /// Does NOT call setState — the caller should wrap this in their
  /// own setState block alongside other state resets.
  void resetLoading() {
    _dataReceived = false;
    _loadingError = '';
    _cancelTimer();
  }

  /// Set a custom error message, ending the loading state.
  ///
  /// [isLoading] becomes false because [loadingError] is non-empty.
  /// Cancels any active timeout timer.
  ///
  /// Does NOT call setState — the caller should wrap this in their
  /// own setState block.
  void setLoadingError(String error) {
    _loadingError = error;
    _cancelTimer();
  }

  /// Start a timeout timer that fires [setLoadingError] if no data
  /// arrives within [timeout].
  ///
  /// [message] overrides the default timeout text, allowing each
  /// screen to show context-specific guidance (e.g. "请检查 Git 仓库").
  ///
  /// Cancels any previously running timeout timer.
  /// Calls setState internally on timeout to trigger a rebuild.
  void startLoadingTimeout({
    Duration timeout = kLoadingTimeout,
    String message = kLoadingTimeoutMessage,
  }) {
    _cancelTimer();
    _loadingTimeout = Timer(timeout, () {
      if (mounted && isLoading) {
        _log.warning('加载超时: screen=${widget.runtimeType}, timeout=${timeout.inSeconds}s');
        setState(() {
          _loadingError = message;
        });
      }
    });
  }

  /// Clean up the timeout timer. Call in the screen's [dispose].
  void disposeLoading() {
    _cancelTimer();
  }

  /// Internal: cancel timer without side effects.
  void _cancelTimer() {
    _loadingTimeout?.cancel();
    _loadingTimeout = null;
  }
}
