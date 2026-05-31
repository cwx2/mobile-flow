/// web_preview_panel.dart — Web Preview panel for the Test Panel.
///
/// Module: screens/test_panel/
/// Responsibility:
///   Port configuration, optional start command, WebView preview of
///   proxied localhost content, and command output display during startup.
///   Supports "Connect Only" mode (port only, no command).
///
/// Called by:
///   - TestPanelScreen (Phase 6, Task 11.1) as one of the sub-panels
///   - Can be used standalone for testing during Phase 2
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/protocol.dart';
import '../../l10n/app_localizations.dart';
import '../../services/websocket_service.dart';
import '../../services/ws_operations/test_panel_operations.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/logger.dart';
import '../../widgets/renderers/webview_renderer.dart';

final _log = getLogger('WebPreview');

/// Regex to detect URLs in command output text.
final _urlRegex = RegExp(r'https?://[^\s,;]+');

/// Preview session state machine.
enum _PreviewState { idle, starting, running, stopping, error }

/// Web Preview Panel — port proxy + WebView for localhost preview.
///
/// Provides an interface for previewing web apps running on the desktop
/// Agent. Supports two modes:
/// 1. Full mode: enter port + command, Agent starts dev server and proxies
/// 2. Connect Only: enter port only, Agent proxies to existing server
class WebPreviewPanel extends StatefulWidget {
  const WebPreviewPanel({super.key});

  @override
  State<WebPreviewPanel> createState() => _WebPreviewPanelState();
}

class _WebPreviewPanelState extends State<WebPreviewPanel> {
  final _portController = TextEditingController();
  final _urlController = TextEditingController();
  final _commandController = TextEditingController();
  final _cwdController = TextEditingController();
  final _webViewController = WebViewRendererController();

  /// Current preview state.
  _PreviewState _state = _PreviewState.idle;

  /// Preview URL received from Agent (preview.ready).
  String? _previewUrl;

  /// Command output lines (compilation progress).
  final List<String> _outputLines = [];

  /// Error message for display.
  String? _errorMessage;

  /// Current URL shown in the URL bar.
  String _currentUrl = '';

  /// Whether the WebView is currently loading.
  bool _isWebViewLoading = false;

  /// Subscription to messageStream for preview.* messages.
  StreamSubscription<WsMessage>? _messageSub;

  /// Whether auto-refresh on file change is enabled.
  bool _autoRefreshEnabled = true;

  /// Debounce timer for file change auto-refresh.
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeToMessages();
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _refreshDebounce?.cancel();
    _portController.dispose();
    _urlController.dispose();
    _commandController.dispose();
    _cwdController.dispose();
    super.dispose();
  }

  void _subscribeToMessages() {
    final ws = context.read<WebSocketService>();
    _messageSub = ws.messageStream
        .where((msg) =>
            msg.type == MessageType.previewReady ||
            msg.type == MessageType.previewOutput ||
            msg.type == MessageType.previewStopped ||
            msg.type == MessageType.previewFileChanged)
        .listen(_handleMessage);
  }

  void _handleMessage(WsMessage msg) {
    switch (msg.type) {
      case MessageType.previewReady:
        _onPreviewReady(msg.payload);
      case MessageType.previewOutput:
        _onPreviewOutput(msg.payload);
      case MessageType.previewStopped:
        _onPreviewStopped(msg.payload);
      case MessageType.previewFileChanged:
        _onFileChanged(msg.payload);
    }
  }

  void _onPreviewReady(Map<String, dynamic> payload) {
    final url = payload['preview_url'] as String? ?? '';
    _log.info('预览就绪: url=$url');
    setState(() {
      _previewUrl = url;
      _currentUrl = url;
      _state = _PreviewState.running;
      _errorMessage = null;
    });
  }

  void _onPreviewOutput(Map<String, dynamic> payload) {
    final data = payload['data'] as String? ?? '';
    setState(() {
      // Split and add lines, cap at 200 lines for the startup log
      final lines = data.split('\n');
      for (final line in lines) {
        if (line.isNotEmpty) {
          _outputLines.add(line);
        }
      }
      if (_outputLines.length > 200) {
        _outputLines.removeRange(0, _outputLines.length - 200);
      }
    });
  }

  void _onPreviewStopped(Map<String, dynamic> payload) {
    final reason = payload['reason'] as String? ?? 'unknown';
    final lastOutput = payload['last_output'] as String?;
    _log.info('预览已停止: reason=$reason');
    setState(() {
      _state = _PreviewState.idle;
      _previewUrl = null;
      if (reason == 'crashed') {
        _state = _PreviewState.error;
        _errorMessage = lastOutput ?? 'Preview crashed';
      }
    });
  }

  void _onFileChanged(Map<String, dynamic> payload) {
    if (!_autoRefreshEnabled || _state != _PreviewState.running) return;

    // Debounce 500ms — batch rapid file changes into one reload
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 500), () {
      _log.fine('自动刷新: 文件变更触发 WebView 重载');
      _webViewController.refresh();
    });
  }

  void _startPreview() {
    final portText = _portController.text.trim();
    final command = _commandController.text.trim();
    final cwd = _cwdController.text.trim();
    final targetUrl = _urlController.text.trim();

    // Validate: need at least a command or a target URL/port
    if (portText.isEmpty && command.isEmpty && targetUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).previewNeedPortOrCommand),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // If port is provided, validate it
    int port = 0;
    if (portText.isNotEmpty) {
      final parsed = int.tryParse(portText);
      if (parsed == null || parsed < 1 || parsed > 65535) {
        setState(() {
          _errorMessage = S.of(context).previewInvalidPort;
        });
        return;
      }
      port = parsed;
    }

    _log.info('启动预览: targetUrl=$targetUrl, port=$port, command=${command.isEmpty ? "(none)" : command}, cwd=${cwd.isEmpty ? "(default)" : cwd}');

    setState(() {
      _state = _PreviewState.starting;
      _outputLines.clear();
      _errorMessage = null;
      _previewUrl = null;
    });

    context.read<TestPanelOperations>().startPreview(
          targetUrl: targetUrl,
          port: port,
          command: command.isEmpty ? null : command,
          cwd: cwd.isEmpty ? null : cwd,
        );
  }

  void _stopPreview() {
    _log.info('停止预览');
    setState(() {
      _state = _PreviewState.stopping;
    });
    context.read<TestPanelOperations>().stopPreview();
  }

  void _refreshWebView() {
    _webViewController.refresh();
  }

  void _retryPreview() {
    setState(() {
      _state = _PreviewState.idle;
      _errorMessage = null;
    });
  }

  /// Handle user tapping a URL in the command output.
  ///
  /// Extracts the port from the URL and sends a Connect Only preview
  /// request to the Agent. Transitions to starting state and waits
  /// for preview.ready before showing the WebView.
  void _onOutputUrlTapped(String url) {
    _log.info('用户点击输出中的 URL: $url');

    // Extract port from URL
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final port = uri.port > 0 ? uri.port : (uri.scheme == 'https' ? 443 : 80);

    // Tell Agent to activate proxy on this port (Connect Only mode).
    // Wait for preview.ready before transitioning to running state.
    context.read<TestPanelOperations>().startPreview(
      targetUrl: url,
      port: port,
      command: null,
    );

    setState(() {
      _state = _PreviewState.starting;
      _errorMessage = null;
    });
  }

  void _startVisualDiff() {
    if (_previewUrl == null) return;
    _log.info('启动视觉对比');
    context.read<TestPanelOperations>().startVisualDiff(url: _previewUrl!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).previewVisualDiffCaptured),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Configuration area (port + command + buttons)
        _buildConfigArea(context),

        // Content area (output log, WebView, or error)
        Expanded(child: _buildContentArea(context)),
      ],
    );
  }

  Widget _buildConfigArea(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);
    final isActive = _state == _PreviewState.running ||
        _state == _PreviewState.starting;

    return Padding(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Command input row (primary — with play/stop button)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  enabled: !isActive,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: colors.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: l.previewCommandHint,
                    hintStyle: TextStyle(color: colors.onSurfaceMuted),
                    filled: true,
                    fillColor: colors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.sm,
                    ),
                    isDense: true,
                    prefixIcon: Icon(Icons.terminal,
                        size: 18, color: colors.onSurfaceMuted),
                  ),
                  onSubmitted: (_) => _startPreview(),
                ),
              ),
              SizedBox(width: spacing.sm),
              // Start / Stop button
              if (isActive)
                IconButton(
                  icon: Icon(Icons.stop_circle, color: colors.error),
                  onPressed: _stopPreview,
                  tooltip: l.previewStopTooltip,
                )
              else
                IconButton(
                  icon: Icon(Icons.play_circle_fill, color: colors.success),
                  onPressed: _startPreview,
                  tooltip: l.previewStartTooltip,
                ),
            ],
          ),
          SizedBox(height: spacing.sm),
          // Target URL + Port + Working directory row (secondary options)
          Row(
            children: [
              // Target URL field (e.g. https://de4.nmm.com:7001)
              Expanded(
                child: TextField(
                  controller: _urlController,
                  enabled: !isActive,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: colors.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: S.of(context).previewUrlHint,
                    hintStyle: TextStyle(color: colors.onSurfaceMuted, fontSize: 12),
                    filled: true,
                    fillColor: colors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: spacing.sm,
                      vertical: spacing.sm,
                    ),
                    isDense: true,
                    prefixIcon: Icon(Icons.link,
                        size: 16, color: colors.onSurfaceMuted),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          // Working directory row
          TextField(
            controller: _cwdController,
            enabled: !isActive,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: colors.onSurface,
            ),
            decoration: InputDecoration(
              hintText: l.previewCwdHint,
              hintStyle: TextStyle(color: colors.onSurfaceMuted, fontSize: 13),
              filled: true,
              fillColor: colors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: spacing.md,
                vertical: spacing.sm,
              ),
              isDense: true,
              prefixIcon: Icon(Icons.folder_outlined,
                  size: 16, color: colors.onSurfaceMuted),
            ),
          ),
          // URL bar (shown when preview is running)
          if (_state == _PreviewState.running && _previewUrl != null) ...[
            SizedBox(height: spacing.sm),
            _buildUrlBar(context),
          ],
        ],
      ),
    );
  }

  Widget _buildUrlBar(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Loading indicator or lock icon
          if (_isWebViewLoading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            )
          else
            Icon(Icons.language, size: 16, color: colors.onSurfaceMuted),
          SizedBox(width: spacing.sm),
          // URL text
          Expanded(
            child: Text(
              _currentUrl,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceMuted,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Refresh button
          InkWell(
            onTap: _refreshWebView,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.refresh, size: 18, color: colors.onSurfaceMuted),
            ),
          ),
          // Auto-refresh toggle
          InkWell(
            onTap: () {
              setState(() {
                _autoRefreshEnabled = !_autoRefreshEnabled;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                _autoRefreshEnabled ? Icons.sync : Icons.sync_disabled,
                size: 18,
                color: _autoRefreshEnabled
                    ? colors.primary
                    : colors.onSurfaceMuted,
              ),
            ),
          ),
          // Visual diff button
          InkWell(
            onTap: _startVisualDiff,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.compare,
                size: 18,
                color: colors.onSurfaceMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentArea(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);

    switch (_state) {
      case _PreviewState.idle:
        return Center(
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.web, size: 48, color: colors.onSurfaceMuted),
                SizedBox(height: spacing.md),
                Text(
                  l.previewIdleTitle,
                  style: TextStyle(color: colors.onSurfaceMuted, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: spacing.sm),
                Text(
                  l.previewIdleSubtitle,
                  style: TextStyle(color: colors.onSurfaceMuted, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );

      case _PreviewState.starting:
        return _buildStartingView(context);

      case _PreviewState.running:
        return _buildWebView(context);

      case _PreviewState.stopping:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colors.primary),
              SizedBox(height: spacing.md),
              Text(
                l.previewStopping,
                style: TextStyle(color: colors.onSurfaceMuted),
              ),
            ],
          ),
        );

      case _PreviewState.error:
        return _buildErrorView(context);
    }
  }

  Widget _buildStartingView(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Column(
      children: [
        // Loading indicator
        Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
              SizedBox(width: spacing.sm),
              Text(
                S.of(context).previewStarting,
                style: TextStyle(color: colors.onSurfaceMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        // Command output (compilation progress)
        Expanded(
          child: Container(
            margin: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border.withValues(alpha: 0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ListView.builder(
                padding: EdgeInsets.all(spacing.sm),
                itemCount: _outputLines.length,
                itemBuilder: (context, index) {
                  final line = _outputLines[index];
                  // Detect URLs in output and make them tappable
                  final urlMatch = _urlRegex.firstMatch(line);
                  if (urlMatch != null) {
                    final url = urlMatch.group(0)!;
                    final before = line.substring(0, urlMatch.start);
                    final after = line.substring(urlMatch.end);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (before.isNotEmpty)
                          Text(before, style: TextStyle(
                            fontFamily: 'monospace', fontSize: 11,
                            height: 1.4, color: colors.onSurface,
                          )),
                        GestureDetector(
                          onTap: () => _onOutputUrlTapped(url),
                          child: Text(url, style: TextStyle(
                            fontFamily: 'monospace', fontSize: 11,
                            height: 1.4, color: colors.primary,
                            decoration: TextDecoration.underline,
                          )),
                        ),
                        if (after.isNotEmpty)
                          Expanded(child: Text(after, style: TextStyle(
                            fontFamily: 'monospace', fontSize: 11,
                            height: 1.4, color: colors.onSurface,
                          ))),
                      ],
                    );
                  }
                  return Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                      color: colors.onSurface,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebView(BuildContext context) {
    final spacing = context.spacing;

    if (_previewUrl == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.sm, 0, spacing.sm, spacing.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: WebViewRenderer(
          initialUrl: _previewUrl!,
          controller: _webViewController,
          onUrlChanged: (url) {
            setState(() {
              _currentUrl = url;
            });
          },
          onLoadingStateChanged: (isLoading) {
            setState(() {
              _isWebViewLoading = isLoading;
            });
          },
          onLoadError: (url, code, message) {
            _log.warning('WebView 加载错误: url=$url, code=$code, msg=$message');
            setState(() {
              _errorMessage = message;
              _state = _PreviewState.error;
            });
          },
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.error),
            SizedBox(height: spacing.md),
            Text(
              l.previewErrorTitle,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing.sm),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(color: colors.onSurfaceMuted, fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            SizedBox(height: spacing.lg),
            FilledButton.icon(
              onPressed: _retryPreview,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
