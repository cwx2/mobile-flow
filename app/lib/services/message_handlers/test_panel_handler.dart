/// test_panel_handler.dart — Handler for Test Panel incoming messages.
///
/// Phase 1 handles script.output and script.done messages.
/// Future phases will add api.response, api.error, preview.ready,
/// preview.output, preview.stopped, preview.file_changed,
/// screenshot.result, screenshot.error, visual_diff.result.
library;

import '../../models/protocol.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

/// Handles incoming Test Panel messages from the Agent.
///
/// Forwards script execution messages to [WebSocketService.messageStream]
/// so UI widgets can listen and update accordingly.
///
/// Message types handled:
/// - `script.output` — subprocess stdout/stderr chunk
/// - `script.done` — subprocess terminated
class TestPanelMessageHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    // All test panel messages are forwarded via messageStream.
    // The messageController.add() is already called in _onMessage()
    // before routing, so UI listeners on messageStream already receive
    // these messages. This handler exists for future state management
    // needs (e.g. tracking running state, buffering output).
    //
    // No additional processing needed for Phase 1 — the Script Runner
    // Panel listens directly to messageStream for script.output and
    // script.done messages.
  }
}
