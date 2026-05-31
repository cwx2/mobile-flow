/// terminal_handler.dart — Handler for terminal output messages.
library;

import '../../core/event_bus.dart';
import '../../models/protocol.dart';
import '../../models/payloads/terminal_payloads.g.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

/// Handles ACP terminal output messages.
///
/// Message types: terminalOutput.
class TerminalHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    final p = TerminalOutputPayload.fromJson(msg.payload);
    if (p.source != 'acp') return;

    final tid = p.terminalId;
    if (tid.isEmpty) return;

    ws.terminalOutputs
        .putIfAbsent(tid, () => [])
        .add(p.text);
    ws.eventBus?.emit(AppEvents.terminalOutput, msg.payload);
    ws.scheduleStreamNotify();
  }
}
