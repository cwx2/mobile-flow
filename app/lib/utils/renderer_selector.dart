/// renderer_selector.dart — Content-type based renderer selection utility.
///
/// Module: utils/
/// Responsibility:
///   Selects the appropriate renderer widget based on content type.
///   Used by the Test Panel to display responses in the correct format.
///
/// Called by:
///   - screens/test_panel/api_tester_panel.dart
///   - Any screen needing automatic renderer selection
library;

/// Available renderer types for content display.
enum RendererType {
  /// WebView renderer for live HTML content.
  webView,

  /// JSON renderer with syntax highlighting and collapsible nodes.
  json,

  /// Image renderer with pinch-to-zoom.
  image,

  /// Terminal renderer with monospace font and ANSI colors.
  terminal,

  /// Plain text fallback.
  plainText,
}

/// Select the appropriate renderer based on content type.
///
/// Examines the Content-Type header value and returns the most
/// suitable renderer type. Falls back to [RendererType.plainText]
/// for unknown content types.
///
/// Rules:
/// - `text/html` → WebView renderer
/// - `application/json` → JSON renderer
/// - `image/*` → Image renderer
/// - Command output (no content type) → Terminal renderer
/// - Everything else → Plain text
RendererType selectRenderer(String? contentType) {
  if (contentType == null || contentType.isEmpty) {
    return RendererType.terminal;
  }

  final lower = contentType.toLowerCase();

  // Strip parameters (e.g. "text/html; charset=utf-8" → "text/html")
  final mimeType = lower.split(';').first.trim();

  if (mimeType == 'text/html' || mimeType == 'application/xhtml+xml') {
    return RendererType.webView;
  }

  if (mimeType == 'application/json' || mimeType.endsWith('+json')) {
    return RendererType.json;
  }

  if (mimeType.startsWith('image/')) {
    return RendererType.image;
  }

  if (mimeType == 'text/plain') {
    return RendererType.plainText;
  }

  // JavaScript, XML, CSS — show as plain text with monospace
  if (mimeType.startsWith('text/') ||
      mimeType == 'application/javascript' ||
      mimeType == 'application/xml') {
    return RendererType.plainText;
  }

  return RendererType.plainText;
}

/// Select renderer for command output (always terminal).
RendererType selectRendererForCommandOutput() => RendererType.terminal;

/// Select renderer for screenshot data (always image).
RendererType selectRendererForScreenshot() => RendererType.image;
