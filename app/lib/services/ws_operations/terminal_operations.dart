/// terminal_operations.dart — Terminal start, input, resize, stop operations.
///
/// Depends on [MessageSender] interface only — no WebSocketService coupling.
library;

import '../../models/protocol.dart';
import '../../models/payloads/terminal_payloads.g.dart';
import '../ws_message_sender.dart';

/// Domain operations for terminal session management.
///
/// Stateless sender — constructs and sends messages but does not
/// handle responses. Terminal output arrives via TerminalHandler.
class TerminalOperations {
  final MessageSender _sender;

  TerminalOperations(this._sender);

  /// Start a terminal session.
  void startTerminal({String? cli, int cols = 80, int rows = 24}) =>
      _sender.send(WsMessage(
          type: MessageType.terminalStart,
          payload: TerminalStartPayload(
            cli: cli ?? _sender.defaultCli,
            cols: cols,
            rows: rows,
          ).toJson()));

  /// Send input data to the terminal.
  void sendTerminalInput(String data) => _sender.send(WsMessage(
      type: MessageType.terminalInput,
      payload: TerminalInputPayload(data: data).toJson()));

  /// Resize the terminal to [cols] x [rows].
  void resizeTerminal(int cols, int rows) => _sender.send(WsMessage(
      type: MessageType.terminalResize,
      payload: TerminalResizePayload(cols: cols, rows: rows).toJson()));

  /// Stop the terminal session.
  void stopTerminal() => _sender.send(WsMessage(
      type: MessageType.terminalStop,
      payload: const TerminalStopPayload().toJson()));
}
