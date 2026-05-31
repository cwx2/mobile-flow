/// run_config_output_view.dart — Real-time process output with preview support.
///
/// Uses xterm's Terminal + TerminalView for rendering process output with
/// full ANSI escape sequence support, proper scrollback, and monospace
/// terminal rendering.
///
/// When the configuration is a preview type and reaches running state
/// with a preview_url, a tabbed interface shows both Output and Preview
/// tabs. The Preview tab uses WebViewRenderer to display the proxied
/// web content.
///
/// Called by:
///   - RunConfigListScreen (on tap to view output)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../l10n/app_localizations.dart';
import '../../models/run_configuration.dart';
import '../../services/run_config_provider.dart';
import '../../services/ws_operations/run_config_operations.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/logger.dart';
import '../../widgets/renderers/webview_renderer.dart';

final _log = getLogger('RunConfigOutput');

/// Terminal-style output view for a running configuration.
///
/// Displays real-time process output with:
/// - xterm Terminal for full ANSI rendering and scrollback
/// - Read-only mode (no input handling)
/// - Stdout/stderr rendered via raw output listener
/// - Before-run task prefix forwarded from provider
/// - Stop button in app bar when process is active
/// - Exit code chip when process has stopped
/// - Tabbed Output/Preview when preview_url is available
class RunConfigOutputView extends StatefulWidget {
  /// The configuration ID to display output for.
  final String configId;

  const RunConfigOutputView({super.key, required this.configId});

  @override
  State<RunConfigOutputView> createState() => _RunConfigOutputViewState();
}

class _RunConfigOutputViewState extends State<RunConfigOutputView>
    with SingleTickerProviderStateMixin {
  final WebViewRendererController _webViewController =
      WebViewRendererController();

  /// xterm Terminal instance for rendering process output.
  late Terminal _terminal;

  /// Dispose callback for the raw output listener registration.
  VoidCallback? _disposeOutputListener;

  /// Tab controller for Output/Preview tabs.
  late TabController _tabController;

  /// Whether we already auto-switched to the Preview tab for this session.
  bool _didAutoSwitch = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 5000);
    _tabController = TabController(length: 2, vsync: this);

    // Register raw output listener after first frame so context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<RunConfigProvider>();
      _disposeOutputListener = provider.addRawOutputListener(
        widget.configId,
        (text) {
          _terminal.write(text);
        },
      );
    });
  }

  @override
  void dispose() {
    _disposeOutputListener?.call();
    _tabController.dispose();
    super.dispose();
  }

  /// Auto-switch to Preview tab when preview_url becomes available.
  void _maybeAutoSwitchToPreview(String? previewUrl, RunConfigState state) {
    if (!_didAutoSwitch &&
        previewUrl != null &&
        state == RunConfigState.running) {
      _didAutoSwitch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController.index != 1) {
          _tabController.animateTo(1);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RunConfigProvider>();
    final colors = context.colors;
    final state = provider.getState(widget.configId);
    final exitCode = provider.exitCodes[widget.configId];
    final errorMessage = provider.errorMessages[widget.configId];
    final previewUrl = provider.previewUrls[widget.configId];

    // Find the configuration for the app bar title
    final config = provider.configurations
        .where((c) => c.id == widget.configId)
        .firstOrNull;
    final title = config?.name ?? S.of(context).runConfigOutputTab;

    final isActive = state != RunConfigState.idle &&
        state != RunConfigState.stopped;

    // Determine if preview tab should be available
    final hasPreview = previewUrl != null && previewUrl.isNotEmpty;

    // Auto-switch to preview tab when URL becomes available
    _maybeAutoSwitchToPreview(previewUrl, state);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: colors.surfaceElevated,
        actions: [
          // Refresh button (only visible on Preview tab when preview is active)
          if (hasPreview)
            AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                if (_tabController.index == 1) {
                  return IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      _log.fine('刷新 WebView 预览');
                      _webViewController.refresh();
                    },
                    tooltip: S.of(context).runConfigRefresh,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          // Stop button when process is active
          if (isActive)
            IconButton(
              icon: Icon(Icons.stop_circle, color: colors.error),
              onPressed: () {
                _log.info('停止配置: $title');
                context.read<RunConfigOperations>().stop(widget.configId);
              },
              tooltip: S.of(context).runConfigStop,
            ),
        ],
        bottom: hasPreview
            ? TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: S.of(context).runConfigOutputTab),
                  Tab(text: S.of(context).runConfigPreviewTab),
                ],
              )
            : null,
      ),
      body: hasPreview
          ? TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Output
                _buildOutputBody(context, state, exitCode, errorMessage),
                // Tab 2: Preview WebView
                _buildPreviewBody(context, previewUrl),
              ],
            )
          : _buildOutputBody(context, state, exitCode, errorMessage),
    );
  }

  /// Build the output tab body (state bar + exit code + xterm TerminalView).
  Widget _buildOutputBody(
    BuildContext context,
    RunConfigState state,
    int? exitCode,
    String? errorMessage,
  ) {
    final colors = context.colors;

    return Column(
      children: [
        // State indicator bar
        _buildStateBar(context, state),

        // Exit code chip (shown when stopped)
        if (state == RunConfigState.stopped && exitCode != null)
          _buildExitCodeChip(context, exitCode, errorMessage),

        // Output area — xterm TerminalView
        Expanded(
          child: Container(
            color: colors.surface,
            child: TerminalView(
              _terminal,
              readOnly: true,
              textStyle: const TerminalStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  /// Build the preview tab body with WebViewRenderer.
  Widget _buildPreviewBody(BuildContext context, String previewUrl) {
    return WebViewRenderer(
      initialUrl: previewUrl,
      controller: _webViewController,
      onLoadingStateChanged: (isLoading) {
        _log.fine('WebView 加载状态: isLoading=$isLoading');
      },
      onLoadError: (url, code, message) {
        _log.warning('WebView 加载错误: url=$url, code=$code, msg=$message');
      },
    );
  }

  /// Build the state indicator bar at the top.
  Widget _buildStateBar(BuildContext context, RunConfigState state) {
    if (state == RunConfigState.idle) return const SizedBox.shrink();

    final colors = context.colors;
    final spacing = context.spacing;
    final color = switch (state) {
      RunConfigState.idle => colors.onSurfaceMuted,
      RunConfigState.beforeRun => colors.warning,
      RunConfigState.starting => colors.warning,
      RunConfigState.running => colors.success,
      RunConfigState.stopping => colors.warning,
      RunConfigState.stopped => colors.onSurfaceMuted,
    };
    final label = _stateLabel(context, state);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.xs,
      ),
      color: color.withValues(alpha: 0.1),
      child: Row(
        children: [
          if (state == RunConfigState.running ||
              state == RunConfigState.beforeRun ||
              state == RunConfigState.starting)
            Padding(
              padding: EdgeInsets.only(right: spacing.sm),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              ),
            ),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build the exit code chip.
  Widget _buildExitCodeChip(
    BuildContext context,
    int exitCode,
    String? errorMessage,
  ) {
    final colors = context.colors;
    final spacing = context.spacing;
    final isSuccess = exitCode == 0;
    final chipColor = isSuccess ? colors.success : colors.error;
    final label = S.of(context).runConfigExitCode(exitCode);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.xs,
      ),
      child: Row(
        children: [
          Chip(
            label: Text(
              label,
              style: TextStyle(color: chipColor, fontSize: 12),
            ),
            backgroundColor: chipColor.withValues(alpha: 0.1),
            side: BorderSide(color: chipColor.withValues(alpha: 0.3)),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          if (errorMessage != null && errorMessage.isNotEmpty) ...[
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                errorMessage,
                style: TextStyle(
                  color: colors.error,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Get a human-readable label for the current state.
  String _stateLabel(BuildContext context, RunConfigState state) {
    final l = S.of(context);
    return switch (state) {
      RunConfigState.idle => '',
      RunConfigState.beforeRun => l.runConfigStateBeforeRun,
      RunConfigState.starting => l.runConfigStateStarting,
      RunConfigState.running => l.runConfigStateRunning,
      RunConfigState.stopping => l.runConfigStateStopping,
      RunConfigState.stopped => l.runConfigStateStopped,
    };
  }
}
