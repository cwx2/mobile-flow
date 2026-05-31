/// chat_operations.dart — Chat send, cancel, history, and session operations.
///
/// Holds a [WebSocketService] reference (not just MessageSender) because
/// [sendChat] must manipulate ChatStateMixin state: check agentStatus,
/// cancel if busy, add user message, beginAssistantMessage, and
/// snapshot/clear pendingContextReferences.
library;

import '../../models/chat_message.dart';
import '../../models/protocol.dart';
import '../../models/payloads/chat_payloads.g.dart';
import '../../models/payloads/session_payloads.g.dart';
import '../../utils/app_config.dart';
import '../../utils/logger.dart';
import '../websocket_service.dart';

final _log = getLogger('ChatOps');

/// Domain operations for chat messaging and session management.
///
/// Unlike other Operations classes that depend only on [MessageSender],
/// ChatOperations holds a [WebSocketService] reference because
/// [sendChat] must read and mutate chat state (agentStatus, messages,
/// pendingContextReferences) before sending the message.
class ChatOperations {
  final WebSocketService _ws;

  ChatOperations(this._ws);

  /// Send a chat message to the agent.
  ///
  /// Cancels any in-progress operation first, then adds the user message,
  /// begins streaming the assistant response, snapshots and clears
  /// pending context references, and sends the chat.send message.
  void sendChat(String text,
      {String? cli,
      List<Map<String, String>>? attachments,
      List<String>? localAttachmentPaths}) {
    final targetCli = cli ?? _ws.defaultCli;
    if (_ws.agentStatus != AgentStatus.idle) {
      cancelChat(cli: targetCli);
    }
    _ws.messages.add(ChatMessage(
      role: ChatRole.user,
      blocks: [ContentBlock.text(text)],
      attachmentPaths: localAttachmentPaths,
    ));
    _ws.beginAssistantMessage();

    // Snapshot and clear pending references before sending so the list
    // is empty by the time notifyListeners() fires from beginAssistantMessage.
    final contextRefs = _ws.pendingContextReferences.isNotEmpty
        ? _ws.pendingContextReferences.map((r) => r.toJson()).toList()
        : null;
    _ws.pendingContextReferences.clear();

    _ws.send(WsMessage(
        type: MessageType.chatSend,
        payload: ChatSendPayload(
          cli: targetCli,
          message: text,
          attachments: attachments
              ?.map((a) => Map<String, dynamic>.from(a))
              .toList(),
          contextReferences: contextRefs
              ?.map((r) => Map<String, dynamic>.from(r))
              .toList(),
        ).toJson()));
  }

  /// Cancel the current AI operation.
  void cancelChat({String? cli}) {
    _ws.send(WsMessage(
        type: MessageType.chatCancel,
        payload: ChatCancelPayload(cli: cli ?? _ws.defaultCli).toJson()));
    _ws.finishStream(_ws.eventBus);
  }

  /// Request chat history for the current or specified CLI.
  void requestChatHistory({String? cli}) {
    _ws.loadingHistory = true;
    _ws.send(WsMessage(
        type: MessageType.chatHistory,
        payload:
            ChatHistoryPayload(cli: cli ?? _ws.defaultCli).toJson()));
  }

  /// Request replay of buffered stream chunks after reconnect.
  ///
  /// Called when the Agent signals that an AI turn was in progress
  /// or recently completed during the disconnection.
  void requestChatReplay({int afterSeq = 0}) {
    _log.info('请求流式回放: after_seq=$afterSeq');
    _ws.send(WsMessage(
      type: MessageType.chatReplay,
      payload: ChatReplayPayload(afterSeq: afterSeq).toJson(),
    ));
  }

  /// Request the next page of older history messages.
  ///
  /// Called when the user scrolls to the top of the message list.
  /// [offset] is the number of messages already loaded (from the end).
  void requestMoreHistory({String? cli, int? offset, int? limit}) {
    if (_ws.isLoadingMoreHistory || !_ws.hasMoreHistory) return;
    _ws.loadingMoreHistory = true;
    _ws.send(WsMessage(
      type: MessageType.chatHistoryMore,
      payload: ChatHistoryMorePayload(
        cli: cli ?? _ws.defaultCli,
        offset: offset ?? _ws.messages.length,
        limit: limit ?? HistoryPaginationConfig.pageSize,
      ).toJson(),
    ));
  }

  /// Request the list of sessions for the current CLI.
  void requestSessionList({String? cli}) => _ws.send(WsMessage(
      type: MessageType.sessionList,
      payload: SessionListPayload(cli: cli ?? _ws.defaultCli).toJson()));

  /// Create a new chat session, clearing current messages.
  ///
  /// Only clears messages and agent streaming state — does NOT reset
  /// CLI lifecycle state because the provider is still running.
  void newSession({String? cli}) {
    if (_ws.agentStatus != AgentStatus.idle) {
      cancelChat(cli: cli ?? _ws.defaultCli);
    }
    _ws.messages.clear();
    _ws.notifyUI();
    _ws.send(WsMessage(
        type: MessageType.sessionNew,
        payload: SessionNewPayload(cli: cli ?? _ws.defaultCli).toJson()));
  }

  /// Switch to an existing session by [id].
  ///
  /// Cancels any active prompt first to prevent stale chunks from
  /// leaking into the switched session's message list.
  void switchSession(String id, {String? cli}) {
    if (_ws.agentStatus != AgentStatus.idle) {
      cancelChat(cli: cli ?? _ws.defaultCli);
    }
    _ws.messages.clear();
    _ws.loadingHistory = true;
    _ws.notifyUI();
    _ws.send(WsMessage(
        type: MessageType.sessionSwitch,
        payload: SessionSwitchPayload(
          cli: cli ?? _ws.defaultCli,
          sessionId: id,
        ).toJson()));
  }

  /// Close (delete) a session by [id].
  void closeSession(String id, {String? cli}) => _ws.send(WsMessage(
      type: MessageType.sessionClose,
      payload: SessionClosePayload(
        cli: cli ?? _ws.defaultCli,
        sessionId: id,
      ).toJson()));
}
