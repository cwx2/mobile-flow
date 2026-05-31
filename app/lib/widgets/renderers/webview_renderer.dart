/// webview_renderer.dart — Reusable InAppWebView wrapper widget.
///
/// Module: widgets/renderers/
/// Responsibility:
///   Generic WebView renderer that loads any URL, supports internal
///   navigation, refresh, and reports loading/error state via callbacks.
///   Used by Web Preview Panel but generic enough for other uses.
///
/// Called by:
///   - screens/test_panel/web_preview_panel.dart
///   - Future: any screen needing embedded web content
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../utils/logger.dart';

final _log = getLogger('WebViewRenderer');

/// Callback for URL navigation changes within the WebView.
typedef OnUrlChanged = void Function(String url);

/// Callback for loading state changes.
typedef OnLoadingStateChanged = void Function(bool isLoading);

/// Callback for page load errors.
typedef OnLoadError = void Function(String url, int code, String message);

/// A reusable InAppWebView wrapper with navigation, refresh, and error handling.
///
/// Provides a clean interface for embedding web content with:
/// - URL loading and navigation
/// - Pull-to-refresh (optional)
/// - Loading state reporting
/// - Error state reporting
/// - Programmatic refresh via [WebViewRendererController]
class WebViewRenderer extends StatefulWidget {
  /// Initial URL to load.
  final String initialUrl;

  /// Controller for programmatic actions (refresh, load URL).
  final WebViewRendererController? controller;

  /// Called when the current URL changes (navigation within WebView).
  final OnUrlChanged? onUrlChanged;

  /// Called when loading state changes (started/finished).
  final OnLoadingStateChanged? onLoadingStateChanged;

  /// Called when a page load error occurs.
  final OnLoadError? onLoadError;

  /// Called when the page finishes loading successfully.
  final VoidCallback? onPageFinished;

  /// Whether to allow navigation to external URLs.
  /// If false, only navigation within the same origin is allowed.
  final bool allowExternalNavigation;

  const WebViewRenderer({
    super.key,
    required this.initialUrl,
    this.controller,
    this.onUrlChanged,
    this.onLoadingStateChanged,
    this.onLoadError,
    this.onPageFinished,
    this.allowExternalNavigation = true,
  });

  @override
  State<WebViewRenderer> createState() => _WebViewRendererState();
}

class _WebViewRendererState extends State<WebViewRenderer> {
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(WebViewRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
    // If the URL changed externally, load the new URL
    if (widget.initialUrl != oldWidget.initialUrl) {
      _loadUrl(widget.initialUrl);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    super.dispose();
  }

  void _loadUrl(String url) {
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  void _refresh() {
    _webViewController?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
      initialSettings: InAppWebViewSettings(
        // Allow mixed content (HTTP from HTTPS context)
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        // Enable JavaScript
        javaScriptEnabled: true,
        // Allow file access for local resources
        allowFileAccess: true,
        // Disable zoom controls for cleaner mobile UI
        supportZoom: true,
        builtInZoomControls: false,
        displayZoomControls: false,
        // Use wide viewport for responsive sites
        useWideViewPort: true,
        loadWithOverviewMode: true,
        // Allow cleartext traffic (HTTP)
        clearCache: false,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        _log.fine('WebView 已创建: url=${widget.initialUrl}');
      },
      onLoadStart: (controller, url) {
        _log.fine('页面加载开始: $url');
        widget.onLoadingStateChanged?.call(true);
        if (url != null) {
          widget.onUrlChanged?.call(url.toString());
        }
      },
      onLoadStop: (controller, url) {
        _log.fine('页面加载完成: $url');
        widget.onLoadingStateChanged?.call(false);
        widget.onPageFinished?.call();
        if (url != null) {
          widget.onUrlChanged?.call(url.toString());
        }
      },
      onReceivedError: (controller, request, error) {
        _log.warning('页面加载错误: ${request.url}, code=${error.type}, msg=${error.description}');
        widget.onLoadingStateChanged?.call(false);
        widget.onLoadError?.call(
          request.url.toString(),
          error.type.toNativeValue() ?? -1,
          error.description,
        );
      },
      onUpdateVisitedHistory: (controller, url, androidIsReload) {
        if (url != null) {
          widget.onUrlChanged?.call(url.toString());
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        if (!widget.allowExternalNavigation) {
          final requestUrl = navigationAction.request.url?.toString() ?? '';
          final initialHost = WebUri(widget.initialUrl).host;
          final requestHost = navigationAction.request.url?.host ?? '';
          // Block navigation to different hosts
          if (requestHost.isNotEmpty && requestHost != initialHost) {
            _log.fine('阻止外部导航: $requestUrl');
            return NavigationActionPolicy.CANCEL;
          }
        }
        return NavigationActionPolicy.ALLOW;
      },
      // Trust self-signed certificates from the Agent's HTTPS proxy.
      // The Agent generates a self-signed cert for port 443 to intercept
      // API requests that frontend JS sends with https:// + location.hostname.
      onReceivedServerTrustAuthRequest: (controller, challenge) async {
        return ServerTrustAuthResponse(
          action: ServerTrustAuthResponseAction.PROCEED,
        );
      },
    );
  }
}

/// Controller for programmatic WebView actions.
///
/// Allows parent widgets to trigger refresh, load new URLs, and
/// query the current URL without direct access to the InAppWebView.
class WebViewRendererController {
  _WebViewRendererState? _state;

  void _attach(_WebViewRendererState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// Reload the current page.
  void refresh() {
    _state?._refresh();
  }

  /// Load a new URL.
  void loadUrl(String url) {
    _state?._loadUrl(url);
  }

  /// Whether the controller is attached to a WebView.
  bool get isAttached => _state != null;
}
