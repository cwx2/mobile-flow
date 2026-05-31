/// test_panel_operations.dart — Test Panel send operations (script, preview, API, screenshot, visual diff).
///
/// Implements all outbound WebSocket messages for the Test Panel feature.
/// Stateless sender — constructs and sends messages but does not
/// handle responses. Incoming messages arrive via TestPanelHandler.
///
/// Depends on [MessageSender] interface only — no WebSocketService coupling.
library;

import '../../models/protocol.dart';
import '../../models/payloads/test_panel_payloads.dart';
import '../ws_message_sender.dart';

/// Domain operations for the Test Panel feature.
///
/// Stateless sender — constructs and sends messages but does not
/// handle responses. Incoming messages arrive via TestPanelHandler.
class TestPanelOperations {
  final MessageSender _sender;

  TestPanelOperations(this._sender);

  // ── Script operations ──

  /// Run a script command on the Agent.
  ///
  /// The Agent will stream output via `script.output` messages and
  /// report completion via `script.done`.
  void runScript(String command, {String? cwd, Map<String, String>? env}) =>
      _sender.send(WsMessage(
          type: MessageType.scriptRun,
          payload: ScriptRunPayload(
            command: command,
            workingDirectory: cwd,
            env: env,
          ).toJson()));

  /// Stop the currently running script on the Agent.
  ///
  /// The Agent sends SIGTERM first, then SIGKILL after 5 seconds.
  void stopScript() => _sender.send(WsMessage(
      type: MessageType.scriptStop,
      payload: const ScriptStopPayload().toJson()));

  // ── Preview operations ──

  /// Start a web preview session on the Agent.
  ///
  /// If [command] is provided, the Agent starts the dev server subprocess
  /// and activates the port proxy. If [command] is null ("Connect Only"
  /// mode), only the port proxy is activated.
  ///
  /// [targetUrl] is the full URL to proxy to (e.g. "https://de4.nmm.com:7001").
  /// If empty, Agent auto-detects from command output.
  ///
  /// The Agent responds with `preview.ready` (URL) and streams
  /// `preview.output` (compilation progress).
  void startPreview({String? command, int port = 0, String? cwd, String targetUrl = ''}) =>
      _sender.send(WsMessage(
          type: MessageType.previewStart,
          payload: <String, dynamic>{
            if (targetUrl.isNotEmpty) 'target_url': targetUrl,
            'port': port,
            if (command != null) 'command': command,
            if (cwd != null) 'working_directory': cwd,
          }));

  /// Stop the active web preview session.
  ///
  /// The Agent stops the dev server (if running), deactivates the port
  /// proxy, and sends `preview.stopped`.
  void stopPreview() => _sender.send(WsMessage(
      type: MessageType.previewStop,
      payload: const <String, dynamic>{}));

  // ── API Proxy operations ──

  /// Send an HTTP request through the Agent's HTTP proxy.
  ///
  /// The Agent executes the request from the desktop and returns
  /// the full response via `api.response` or `api.error`.
  void sendApiRequest({
    required String url,
    required String method,
    Map<String, String> headers = const {},
    String? body,
    bool followRedirects = true,
    required String requestId,
  }) =>
      _sender.send(WsMessage(
          type: MessageType.apiRequest,
          payload: <String, dynamic>{
            'url': url,
            'method': method,
            'headers': headers,
            if (body != null) 'body': body,
            'follow_redirects': followRedirects,
            'request_id': requestId,
          }));

  // ── Screenshot operations ──

  /// Capture a screenshot of a URL via Playwright on the Agent.
  ///
  /// The Agent responds with `screenshot.result` or `screenshot.error`.
  void captureScreenshot({
    required String url,
    int viewportWidth = 375,
    int viewportHeight = 812,
    String waitUntil = 'networkidle',
  }) =>
      _sender.send(WsMessage(
          type: MessageType.screenshotCapture,
          payload: <String, dynamic>{
            'url': url,
            'viewport_width': viewportWidth,
            'viewport_height': viewportHeight,
            'wait_until': waitUntil,
          }));

  // ── Visual Diff operations ──

  /// Start a visual diff session — capture the "before" baseline.
  ///
  /// The Agent captures a screenshot and stores it as the baseline.
  void startVisualDiff({
    required String url,
    int viewportWidth = 375,
    int viewportHeight = 812,
  }) =>
      _sender.send(WsMessage(
          type: MessageType.visualDiffStart,
          payload: <String, dynamic>{
            'url': url,
            'viewport_width': viewportWidth,
            'viewport_height': viewportHeight,
          }));

  /// Compare current state against the "before" baseline.
  ///
  /// The Agent captures an "after" screenshot, computes the pixel diff,
  /// and sends `visual_diff.result`.
  void compareVisualDiff() => _sender.send(WsMessage(
      type: MessageType.visualDiffCompare,
      payload: const <String, dynamic>{}));

  // ── Plugin queries ──

  /// Query installed plugins for project type detection.
  ///
  /// The Agent responds with `preview.detect.result` containing
  /// suggested command and port (if a plugin provides them).
  void detectPreview() => _sender.send(WsMessage(
      type: MessageType.previewDetect,
      payload: const <String, dynamic>{}));
}
