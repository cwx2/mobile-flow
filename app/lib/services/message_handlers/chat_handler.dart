/// chat_handler.dart — Handler for chat stream, done, error, history, and replay messages.
library;

import 'dart:convert';

import '../../models/protocol.dart';
import '../../models/chat_message.dart';
import '../../models/payloads/chat_payloads.g.dart';
import '../../utils/logger.dart';
import '../foreground_service.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

final _log = getLogger('ChatHandler');

/// Handles all chat-related incoming messages.
///
/// Message types: chatStream, chatDone, chatError,
/// chatHistoryResult, chatHistoryMoreResult, chatReplayResult.
class ChatHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    switch (msg.type) {
      case MessageType.chatStream:
        _handleChatStream(msg, ws);
      case MessageType.chatDone:
        _handleChatDone(ws);
      case MessageType.chatError:
        _handleChatError(msg, ws);
      case MessageType.chatHistoryResult:
        _handleHistoryResult(msg, ws);
      case MessageType.chatHistoryMoreResult:
        _handleHistoryMoreResult(msg, ws);
      case MessageType.chatReplayResult:
        _handleReplayResult(msg, ws);
    }
  }

  void _handleChatStream(WsMessage msg, WebSocketService ws) {
    final streamPayload = ChatStreamPayload.fromJson(msg.payload);
    final chunk = streamPayload.chunk;
    if (chunk.isEmpty) return;

    final chunkType = chunk['type'] as String? ?? '';

    // Mode/config updates are state changes, not chat content
    if (chunkType == 'mode_change') {
      ws.currentModeValue = chunk['content'] as String? ?? '';
      _log.fine('[ModeChange] mode=${ws.currentMode}');
      ws.notifyUI();
      return;
    }
    if (chunkType == 'config_update') {
      try {
        final optionsJson = chunk['content'] as String? ?? '[]';
        final List<dynamic> parsed = jsonDecode(optionsJson) as List;
        ws.configOptionsValue = parsed
            .map((o) => ConfigOption.fromJson(Map<String, dynamic>.from(o as Map)))
            .toList();
        _log.fine('[ConfigUpdate] ${ws.configOptions.length} options');
      } catch (e) {
        _log.severe('[ConfigUpdate] 解析失败: $e');
      }
      ws.notifyUI();
      return;
    }
    if (chunkType == 'session_info') {
      try {
        final infoJson = chunk['content'] as String? ?? '{}';
        final Map<String, dynamic> info =
            jsonDecode(infoJson) as Map<String, dynamic>;
        ws.updateSessionInfo(info);
        _log.fine('[SessionInfo] title=${info['title']}, '
            'context_usage=${info['context_usage']}');
      } catch (e) {
        _log.severe('[SessionInfo] 解析失败: $e');
      }
      ws.notifyUI();
      return;
    }

    ws.handleStreamChunk(chunk);

    // Update foreground notification with streaming text preview
    if (chunkType == 'text' && (chunk['content'] as String? ?? '').isNotEmpty) {
      ForegroundService.onStreamChunk(chunk['content'] as String);
    }
  }

  void _handleChatDone(WebSocketService ws) {
    ws.finishStream(ws.eventBus);
    ForegroundService.onStreamDone();
  }

  void _handleChatError(WsMessage msg, WebSocketService ws) {
    ws.errorStream(ChatErrorPayload.fromJson(msg.payload).error, ws.eventBus);
    ForegroundService.onStreamDone();
  }

  void _handleHistoryResult(WsMessage msg, WebSocketService ws) {
    final result = ChatHistoryResultPayload.fromJson(msg.payload);
    _log.fine('[chatHistoryResult] 收到 ${result.messages.length} 条 '
        '(total=${result.total}, hasMore=${result.hasMore}, resumed=${result.resumed})');
    ws.restoreHistory(result.messages,
        totalCount: result.total, hasMore: result.hasMore, resumed: result.resumed);
  }

  void _handleHistoryMoreResult(WsMessage msg, WebSocketService ws) {
    final result = ChatHistoryMoreResultPayload.fromJson(msg.payload);
    _log.fine('[chatHistoryMoreResult] 收到 ${result.messages.length} 条, '
        'hasMore=${result.hasMore}');
    ws.appendOlderHistory(result.messages, hasMore: result.hasMore);
  }

  void _handleReplayResult(WsMessage msg, WebSocketService ws) {
    final result = ChatReplayResultPayload.fromJson(msg.payload);

    // Track the latest sequence number for incremental replay
    if (result.seq > 0) {
      ws.updateLastStreamSeq(result.seq);
    }

    // Initial signal from Agent (empty chunks + streaming_state):
    // Determines whether to request replay or rely on chat.history.
    if (result.streamingState != null && result.chunks.isEmpty) {
      if (result.streamingState == 'streaming') {
        // AI is still actively outputting — we need replay to catch up
        // and then continue receiving real-time chunks.
        _log.info('🔄 AI 仍在输出中，请求回放: seq=${result.seq}');
        ws.chatOps.requestChatReplay(afterSeq: ws.lastStreamSeq);
      } else {
        // AI finished while we were disconnected. chat.history (already
        // requested via _handleAuthSuccess) will contain the complete
        // response. Replay is not needed — skip to avoid duplication.
        _log.info('🔄 AI 已完成，chat.history 将提供完整内容，跳过 replay');
      }
      return;
    }

    _log.info('🔄 收到流式回放: ${result.chunks.length} chunks, '
        'streaming=${result.streaming}');

    // If there's an interrupted partial message at the end (from pre-disconnect
    // streaming), remove it — the replay will provide the complete version.
    if (ws.messages.isNotEmpty && result.chunks.isNotEmpty) {
      final lastMsg = ws.messages.last;
      if (lastMsg.role == ChatRole.assistant && !lastMsg.isStreaming) {
        // Check if it was interrupted (has an interruption block added by
        // interruptCurrentStream on disconnect)
        final hasInterruption = lastMsg.blocks.any(
            (b) => b.type == BlockType.interruption);
        if (hasInterruption) {
          _log.fine('移除中断消息，将由 replay 替代');
          ws.messages.removeLast();
        }
      }
    }

    // Create a streaming assistant message if we don't have one yet
    if (ws.agentStatus == AgentStatus.idle && result.chunks.isNotEmpty) {
      ws.beginAssistantMessage();
    }

    // Replay each buffered chunk through the normal stream handler
    for (final rawMsg in result.chunks) {
      final msgMap = Map<String, dynamic>.from(rawMsg as Map);
      final payload = msgMap['payload'] as Map<String, dynamic>? ?? {};
      final msgType = msgMap['type'] as String? ?? '';
      if (msgType == MessageType.chatStream) {
        final chunk = payload['chunk'] as Map<String, dynamic>?;
        if (chunk != null) {
          ws.handleStreamChunk(chunk);
        }
      } else if (msgType == MessageType.chatDone) {
        ws.finishStream(ws.eventBus);
        ForegroundService.onStreamDone();
      }
    }
  }
}
