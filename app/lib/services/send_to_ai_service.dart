/// send_to_ai_service.dart — Universal "Send to AI" pipeline.
///
/// Single entry point for any page to send content to the AI chat.
/// Shows a confirmation sheet with content preview + description input,
/// then formats and sends the message via [WebSocketService].
///
/// Usage from any page:
/// ```dart
/// SendToAiService.send(context, SendToAiPayload(
///   type: SendToAiType.code,
///   content: selectedCode,
///   filePath: 'src/auth.py',
///   startLine: 42,
///   endLine: 58,
///   language: 'python',
/// ));
/// ```
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../components/send_to_ai_sheet.dart';
import '../core/event_bus.dart';
import '../models/send_to_ai_payload.dart';
import '../utils/logger.dart';
import 'websocket_service.dart';
import 'ws_operations/chat_operations.dart';
import 'ws_operations/terminal_operations.dart';

final _log = getLogger('SendToAI');

/// Universal "Send to AI" pipeline.
///
/// Static-only service — no instance needed. Any page calls
/// [SendToAiService.send()] with a payload, and the pipeline handles
/// the rest: show sheet → format message → switch to chat → send.
class SendToAiService {
  SendToAiService._();

  /// Send content to the AI chat.
  ///
  /// Shows the confirmation sheet, waits for user input, then:
  /// 1. Formats the content + description into a chat message
  /// 2. Emits [AppEvents.navigateToChat] to switch to the chat tab
  /// 3. Sends the message via [WebSocketService.sendChat]
  ///
  /// Returns true if the message was sent, false if the user dismissed.
  static Future<bool> send(
    BuildContext context,
    SendToAiPayload payload,
  ) async {
    _log.fine('发送到AI: type=${payload.type.name}, source=${payload.sourceLabel}');

    // Capture references BEFORE showing the sheet, because the caller's
    // context may become invalid after the sheet closes (e.g., file actions
    // sheet pops its own context before calling us).
    final eventBus = context.read<AppEventBus>();
    final chatOps = context.read<ChatOperations>();
    final terminalOps = context.read<TerminalOperations>();

    // Show confirmation sheet with preview + description input
    final description = await showSendToAiSheet(context, payload: payload);

    // User dismissed without sending
    if (description == null) {
      _log.fine('用户取消发送到AI');
      return false;
    }

    // Format the message
    final message = payload.formatForAi(description);

    // Route based on payload type:
    // - run/terminal → send to AI CLI terminal, switch to terminal tab
    // - everything else → send as chat message, switch to chat tab
    final isTerminalRoute = payload.type == SendToAiType.run ||
        payload.type == SendToAiType.terminal;

    if (isTerminalRoute) {
      eventBus.emit(AppEvents.navigateToTerminal);
      await Future.delayed(const Duration(milliseconds: 150));
      terminalOps.sendTerminalInput('$message\n');
    } else {
      eventBus.emit(AppEvents.navigateToChat);
      await Future.delayed(const Duration(milliseconds: 150));
      chatOps.sendChat(message);
    }

    _log.info('已发送到AI: type=${payload.type.name}, route=${isTerminalRoute ? "terminal" : "chat"}, len=${message.length}');
    return true;
  }
}
