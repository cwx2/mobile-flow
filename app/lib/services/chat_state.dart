/// chat_state.dart — Chat state management mixin.
///
/// Manages the chat message list, streaming reception (text/tool/diff/error
/// chunks), agent status tracking, and throttled UI notifications.
///
/// Implemented as a mixin on [ChangeNotifier] so that [WebSocketService]
/// can mix it in. This avoids splitting into multiple Providers — Flutter's
/// `context.watch` is most efficient with a single ChangeNotifier.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/payloads/cli_payloads.g.dart';
import '../utils/logger.dart';
import '../core/event_bus.dart';
import '../widgets/slash_command_menu.dart';

final _log = getLogger('ChatState');

/// Safely cast a dynamic List to List<Map<String, dynamic>>.
///
/// Used by tool_use/tool_update chunk parsing in both stream and history restore.
List<Map<String, dynamic>>? castMapList(dynamic raw) {
  if (raw == null) return null;
  return (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

/// CLI provider lifecycle state (mirrors backend ProviderLifecycleState).
enum CliLifecycleState { uninitialized, checkingEnv, starting, authRequired, ready, failed }

/// AI agent's current operational status.
enum AgentStatus { idle, thinking, toolRunning, streaming }

/// Chat state mixin providing message management and stream handling.
///
/// Mixed into [WebSocketService] to keep chat logic in a separate file
/// while sharing the same [ChangeNotifier] instance at runtime.
mixin ChatStateMixin on ChangeNotifier {
  // Chat message list
  final List<ChatMessage> messages = [];

  // Currently streaming assistant message
  ChatMessage? _currentStreamMessage;

  // History buffer for pagination — stores raw history dicts that haven't
  // been parsed into ChatMessage objects yet. Populated by restoreHistory()
  // when the total history exceeds initialPageSize. Consumed by
  // loadMoreHistory() when the user scrolls to the top.
  final List<dynamic> _historyBuffer = [];
  bool _isLoadingMoreHistory = false;

  // Server-side pagination state — whether the Agent has more pages available.
  bool _serverHasMore = false;

  /// Whether there are older messages available (local buffer or server).
  bool get hasMoreHistory => _historyBuffer.isNotEmpty || _serverHasMore;

  /// Whether a loadMoreHistory() call is currently in progress.
  bool get isLoadingMoreHistory => _isLoadingMoreHistory;

  /// Mark that a "load more" request is in flight.
  /// Called by WebSocketService.requestMoreHistory() before sending the request.
  set loadingMoreHistory(bool v) {
    _isLoadingMoreHistory = v;
    notifyListeners();
  }

  // Agent status
  AgentStatus _agentStatus = AgentStatus.idle;
  String _agentStatusDetail = '';
  AgentStatus get agentStatus => _agentStatus;
  String get agentStatusDetail => _agentStatusDetail;

  // History loading state
  bool _isLoadingHistory = false;
  bool get isLoadingHistory => _isLoadingHistory;
  set loadingHistory(bool v) {
    _isLoadingHistory = v;
    notifyListeners();
  }

  // CLI lifecycle state
  CliLifecycleState _cliLifecycleState = CliLifecycleState.uninitialized;
  String _cliStatusMessage = '';
  String? _cliErrorMessage;

  CliLifecycleState get cliLifecycleState => _cliLifecycleState;
  String get cliStatusMessage => _cliStatusMessage;
  String? get cliErrorMessage => _cliErrorMessage;

  // Auth methods (populated when state = authRequired)
  List<Map<String, dynamic>> _authMethods = [];
  List<Map<String, dynamic>> get authMethods => _authMethods;

  // Auth type for current auth_required state (env_var / device_code / agent_internal)
  String _authType = '';
  String get authType => _authType;

  // Device code info (populated when auth_type = device_code)
  String _deviceCodeUrl = '';
  String _deviceCode = '';
  String get deviceCodeUrl => _deviceCodeUrl;
  String get deviceCode => _deviceCode;

  // CLI-advertised commands, keyed by CLI adapter name.
  // Populated by cli.commands messages from the Agent.
  final Map<String, List<CliCommand>> _cliCommands = {};

  /// Get CLI commands for a specific adapter.
  List<CliCommand> getCliCommandsFor(String cli) => _cliCommands[cli] ?? [];

  /// Handle a ``cli.commands`` message — store/replace commands for a CLI.
  ///
  /// Uses replace semantics: each message replaces the previous command
  /// list for that CLI adapter. An empty list clears commands.
  void handleCliCommands(String cli, List<CliCommand> commands) {
    _cliCommands[cli] = commands;
    _log.fine('CLI 命令更新: cli=$cli, count=${commands.length}');
    notifyListeners();
  }

  /// Clear all stored CLI commands (called on disconnect).
  void clearCliCommands() {
    _cliCommands.clear();
  }

  /// Reset all CLI-related state to uninitialized.
  ///
  /// Called when the CLI context changes: switchCLI, switchProject,
  /// retryCli, reconnect. Clears lifecycle, auth, mode,
  /// and config state so the UI shows loading until the new CLI
  /// pushes its status.
  void resetCliState() {
    _cliLifecycleState = CliLifecycleState.uninitialized;
    _cliStatusMessage = '';
    _cliErrorMessage = null;
    _authMethods = [];
    _authType = '';
    _deviceCodeUrl = '';
    _deviceCode = '';
    clearCliCommands();
    notifyListeners();
  }

  /// Clear only device code info, keeping authRequired state.
  ///
  /// Used by "暂不认证" on the device code page to go back to
  /// the auth method selection without re-initializing the CLI.
  void clearDeviceCodeState() {
    _authType = '';
    _deviceCodeUrl = '';
    _deviceCode = '';
    notifyListeners();
  }

  /// Handle a `cli.status` message from the backend.
  ///
  /// Updates lifecycle state, status message, error, auth methods,
  /// and device code info.
  void handleCliStatus(CliStatusPayload payload) {
    _cliLifecycleState = _parseCliLifecycleState(payload.state);
    _cliStatusMessage = payload.message;
    _cliErrorMessage = payload.error;
    // Store auth methods when auth is required
    if (_cliLifecycleState == CliLifecycleState.authRequired) {
      _authMethods = payload.authMethods ?? [];
      // Parse auth type and device code info
      _authType = payload.authType ?? '';
      _deviceCodeUrl = payload.deviceCodeUrl ?? '';
      _deviceCode = payload.deviceCode ?? '';
      // Cancel any pending history load — auth takes over the UI
      _isLoadingHistory = false;
      // Reset streaming state — message was blocked by auth interceptor,
      // user should not see "thinking" indicator while auth is pending
      if (_agentStatus != AgentStatus.idle) {
        _agentStatus = AgentStatus.idle;
        _agentStatusDetail = '';
        // Finalize any in-progress stream message so it doesn't stay
        // in "streaming" state forever
        if (_currentStreamMessage != null) {
          _currentStreamMessage!.isStreaming = false;
          _currentStreamMessage = null;
        }
      }
    }
    // Also reset loading and agent status on failed state
    if (_cliLifecycleState == CliLifecycleState.failed) {
      _isLoadingHistory = false;
      _agentStatus = AgentStatus.idle;
      _agentStatusDetail = '';
      // Clear CLI commands — failed CLI can't serve commands
      _cliCommands.remove(payload.cli);
    }
    _log.fine('[CliStatus] state=${payload.state}, message=$_cliStatusMessage, authType=$_authType');
    notifyListeners();
  }

  /// Convert a snake_case state string to [CliLifecycleState] enum.
  static CliLifecycleState _parseCliLifecycleState(String state) {
    switch (state) {
      case 'checking_env': return CliLifecycleState.checkingEnv;
      case 'starting': return CliLifecycleState.starting;
      case 'auth_required': return CliLifecycleState.authRequired;
      case 'ready': return CliLifecycleState.ready;
      case 'failed': return CliLifecycleState.failed;
      default: return CliLifecycleState.uninitialized;
    }
  }

  // Stream throttle (max one UI notify per 80ms to avoid jank)
  Timer? _streamThrottle;
  bool _streamDirty = false;
  static const _streamInterval = Duration(milliseconds: 80);

  // Text chunk counter — only the first chunk logs, rest are silent
  int _textChunkCount = 0;

  // Thinking chunk counter — same throttle strategy as text
  int _thinkingChunkCount = 0;

  /// Begin a new assistant message (called after user sends a message).
  void beginAssistantMessage() {
    _log.fine('开始接收助手消息，当前消息数: ${messages.length}');
    _currentStreamMessage =
        ChatMessage(role: ChatRole.assistant, isStreaming: true);
    messages.add(_currentStreamMessage!);
    _agentStatus = AgentStatus.thinking;
    _agentStatusDetail = '';
    notifyListeners();
  }

  /// Process a streaming chunk from the agent.
  ///
  /// Dispatches to type-specific handlers (text, thinking, diff,
  /// tool_use, tool_update, error).
  void handleStreamChunk(Map<String, dynamic> chunk) {
    if (_currentStreamMessage == null) return;
    final type = chunk['type'] as String? ?? 'text';
    final content = chunk['content'] as String? ?? '';

    // Mark the last thought block as done when a non-thinking chunk arrives.
    // This lets ThoughtBlock switch from "思考中..." pulse to static "思考过程".
    if (type != 'thinking' && _thinkingChunkCount > 0) {
      _markThinkingDone();
    }

    switch (type) {
      case 'text':
        if (_textChunkCount == 0) {
          final preview = content.length > 50 ? '${content.substring(0, 50)}...' : content;
          _log.fine('📝 文本流开始: "$preview"');
        }
        _currentStreamMessage!.appendText(content);
        _textChunkCount++;
        if (_agentStatus != AgentStatus.toolRunning) {
          _agentStatus = AgentStatus.streaming;
        }
        scheduleStreamNotify();
        return; // throttled — don't notify immediately
      case 'thinking':
        if (_thinkingChunkCount == 0) {
          _log.fine('💭 思考流开始');
        }
        _thinkingChunkCount++;
        _currentStreamMessage!.appendThought(content);
        scheduleStreamNotify();
        return; // throttled — same as text chunks
      case 'diff':
        _log.fine('📄 diff chunk: file=${chunk['file_path'] ?? ""}');
        _handleDiffChunk(chunk);
      case 'tool_use':
        // Detailed log is inside _handleToolUseChunk
        _handleToolUseChunk(chunk, content);
      case 'tool_update':
        // Detailed log is inside _handleToolUpdateChunk
        _handleToolUpdateChunk(chunk);
      case 'error':
        _log.severe('❌ error chunk: $content');
        _currentStreamMessage!.addBlock(ContentBlock.error(content));
      default:
        _log.fine('❓ unknown chunk type: $type');
    }
    // Use throttled notify for all chunk types (not just text/thinking).
    // Direct notifyListeners() here would bypass streamNotifyPaused,
    // causing the ListView to rebuild and shift the user's scroll
    // position during tool_use/tool_update/diff/error chunks.
    scheduleStreamNotify();
  }

  /// Mark the last thought block as done (thinking phase ended).
  ///
  /// Called when a non-thinking chunk arrives after thinking chunks,
  /// so ThoughtBlock can switch from pulsing "思考中..." to static "思考过程".
  void _markThinkingDone() {
    if (_currentStreamMessage == null) return;
    for (var i = _currentStreamMessage!.blocks.length - 1; i >= 0; i--) {
      if (_currentStreamMessage!.blocks[i].type == BlockType.thought) {
        _currentStreamMessage!.blocks[i].isThinkingDone = true;
        _log.fine('💭 思考流结束: $_thinkingChunkCount chunks');
        break;
      }
    }
    _thinkingChunkCount = 0;
  }

  /// Handle a diff chunk — group edits to the same file.
  void _handleDiffChunk(Map<String, dynamic> chunk) {
    final path = chunk['file_path'] as String? ?? '';
    final oldC = chunk['old_content'] as String? ?? '';
    final newC = chunk['new_content'] as String? ?? '';

    // Edits to the same path are grouped into one FileEditGroup
    final existing = _currentStreamMessage!.blocks.lastWhere(
      (b) => b.type == BlockType.fileEdit && b.filePath == path,
      orElse: () => ContentBlock(type: BlockType.text),
    );

    if (existing.type == BlockType.fileEdit) {
      // Existing edit group for this file → append new entry (don't overwrite)
      existing.editEntries.add(FileEditEntry(
        oldContent: oldC,
        newContent: newC,
      ));
      // Update top-level old/new to latest (for the Diff button)
      existing.oldContent = oldC;
      existing.newContent = newC;
    } else {
      // New file → create a FileEditGroup
      _currentStreamMessage!.addBlock(ContentBlock.fileEdit(
          path: path, oldContent: oldC, newContent: newC));
    }
  }

  /// Handle a tool_use chunk — create or merge a tool call card.
  void _handleToolUseChunk(Map<String, dynamic> chunk, String content) {
    final locs = castMapList(chunk['locations']);
    final blocks = castMapList(chunk['content_blocks']);
    final toolId = chunk['tool_id'] as String?;
    final kind = chunk['kind'] as String?;
    final newName = content.replaceAll('🔧 ', '');

    _log.fine('🔧 工具调用: name=$newName, kind=$kind, id=${toolId ?? ""}');

    // ACP may send multiple tool_call events for the same toolCallId
    // (e.g. internal start + MCP tool start). Merge into one card.
    if (toolId != null && toolId.isNotEmpty && _currentStreamMessage != null) {
      for (final block in _currentStreamMessage!.blocks) {
        if (block.type == BlockType.toolCall && block.toolId == toolId) {
          if (newName.isNotEmpty) block.toolName = newName;
          block.toolKind ??= kind;
          block.toolProgress ??= chunk['tool_input'] as String?;
          if (locs != null && locs.isNotEmpty) block.toolLocations = locs;
          if (blocks != null && blocks.isNotEmpty) block.contentBlocks = blocks;
          block.terminalId ??= chunk['terminal_id'] as String?;
          _agentStatus = AgentStatus.toolRunning;
          _agentStatusDetail = newName;
          return;
        }
      }
    }

    _currentStreamMessage!.addBlock(ContentBlock.toolCall(
      name: newName,
      kind: kind,
      toolInput: chunk['tool_input'] as String?,
      id: toolId,
      locations: locs,
      terminalId: chunk['terminal_id'] as String?,
      contentBlocks: blocks,
    ));
    _agentStatus = AgentStatus.toolRunning;
    _agentStatusDetail = newName;
  }

  /// Handle a tool_update chunk — update status and merge content blocks.
  void _handleToolUpdateChunk(Map<String, dynamic> chunk) {
    final toolId = chunk['tool_id'] as String? ?? '';
    final status = chunk['status'] as String? ?? '';
    _log.fine('🔧 tool_update: id=${toolId.length > 12 ? toolId.substring(0, 12) : toolId}..., status=$status');
    final progress = chunk['tool_input'] as String?;
    final blocks = castMapList(chunk['content_blocks']);
    _currentStreamMessage!.updateToolStatus(toolId, status, progress: progress, contentBlocks: blocks);
    if (status == 'completed' || status == 'failed') {
      _agentStatus = AgentStatus.thinking;
      _agentStatusDetail = '';
    }
  }

  /// Finish the current streaming turn.
  void finishStream(AppEventBus? eventBus) {
    _log.info('流式响应完成，消息总数: ${messages.length}');
    // Edge case: stream ends while still in thinking phase
    if (_thinkingChunkCount > 0) _markThinkingDone();
    _textChunkCount = 0;
    _thinkingChunkCount = 0;
    _streamNotifyPaused = false; // Always unpause when stream ends
    flushStreamNotify();
    _currentStreamMessage?.finalizeAllTools();
    _currentStreamMessage?.isStreaming = false;
    _currentStreamMessage = null;
    _agentStatus = AgentStatus.idle;
    _agentStatusDetail = '';
    eventBus?.emit(AppEvents.chatDone);
    notifyListeners();
  }

  /// Handle a stream error — append error block and finish.
  void errorStream(String error, AppEventBus? eventBus) {
    _log.severe('流式响应出错: $error');
    _currentStreamMessage?.addBlock(ContentBlock.error(error));
    finishStream(eventBus);
    eventBus?.emit(AppEvents.chatError, {'error': error});
  }

  /// Mark the current streaming message as interrupted.
  ///
  /// Called by: watchdog timeout, connection drop (onDone/onError),
  /// manual disconnect, or failed state transition.
  ///
  /// Idempotent: safe to call multiple times — won't add duplicate
  /// interruption markers or modify an already-interrupted message.
  void interruptCurrentStream() {
    if (_currentStreamMessage == null) return;
    if (_currentStreamMessage!.isInterrupted) return; // idempotent guard

    _log.warning('流式消息被中断');
    _currentStreamMessage!.isInterrupted = true;
    _currentStreamMessage!.isStreaming = false;
    _currentStreamMessage!.finalizeAllTools();
    _currentStreamMessage!.addBlock(ContentBlock.interruption());
    _currentStreamMessage = null;
    _agentStatus = AgentStatus.idle;
    _agentStatusDetail = '';
    _textChunkCount = 0;
    _thinkingChunkCount = 0;
    _streamNotifyPaused = false;
    flushStreamNotify();
    notifyListeners();
  }

  /// Clear all messages (e.g. /clear command).
  void clearMessages() {
    _log.info('清空所有消息，原消息数: ${messages.length}');
    messages.clear();
    _historyBuffer.clear();
    _serverHasMore = false;
    notifyListeners();
  }

  /// Restore chat history from a paginated response.
  ///
  /// The Agent sends only the last page of messages. [totalCount] and
  /// [hasMore] indicate whether older pages are available on the server.
  /// The App can request them via requestMoreHistory().
  ///
  /// When [resumed] is true, the session was restored via session/resume
  /// (fast path, no history transfer). The App retains its existing local
  /// messages and only clears the loading state.
  void restoreHistory(List<dynamic> historyList, {int totalCount = 0, bool hasMore = false, bool resumed = false}) {
    if (resumed) {
      // Session was resumed — keep existing local messages intact.
      // The server restored context without replaying history, so the
      // App's local message list is already up-to-date.
      _isLoadingHistory = false;
      _log.info('会话已恢复 (resumed)，保留本地消息: ${messages.length} 条');
      notifyListeners();
      return;
    }

    _log.info('恢复聊天历史: ${historyList.length} 条 (total=$totalCount, hasMore=$hasMore)');
    messages.clear();
    _historyBuffer.clear();
    _serverHasMore = hasMore;

    _parseHistoryItems(historyList);

    _isLoadingHistory = false;
    _log.info('历史恢复完成，消息数: ${messages.length}, 服务端还有更多: $_serverHasMore');
    notifyListeners();
  }

  /// Append older history messages received from the server.
  ///
  /// Called when the App receives a chat.history.more.result response.
  /// Parses the messages and inserts them at the beginning of the list.
  /// Returns the number of ChatMessage objects inserted (for scroll
  /// position compensation by the UI).
  int appendOlderHistory(List<dynamic> olderItems, {bool hasMore = false}) {
    _serverHasMore = hasMore;
    _isLoadingMoreHistory = false;

    if (olderItems.isEmpty) {
      notifyListeners();
      return 0;
    }

    // Parse into ChatMessage objects
    final oldCount = messages.length;
    final parsed = <ChatMessage>[];
    ChatMessage? currentAssistant;

    for (final item in olderItems) {
      final role = item['role'] as String? ?? '';
      final type = item['type'] as String? ?? 'text';
      final content = item['content'] as String? ?? '';
      final data = item['data'] as Map<String, dynamic>?;

      if (role == 'user') {
        currentAssistant = null;
        if (content.isNotEmpty) {
          parsed.add(ChatMessage(role: ChatRole.user, blocks: [ContentBlock.text(content)]));
        }
        continue;
      }

      currentAssistant ??= () {
        final msg = ChatMessage(role: ChatRole.assistant);
        parsed.add(msg);
        return msg;
      }();

      _parseAssistantBlock(currentAssistant, type, content, data);
    }

    messages.insertAll(0, parsed);
    final insertedCount = messages.length - oldCount;
    _log.info('加载更多历史: +$insertedCount 条消息, 服务端还有更多: $_serverHasMore');
    notifyListeners();
    return insertedCount;
  }

  /// Parse a list of raw history items into ChatMessage objects and
  /// append them to [messages]. Shared by restoreHistory (initial load)
  /// and the inline parsing in restoreHistory.
  void _parseHistoryItems(List<dynamic> items) {
    ChatMessage? currentAssistant;

    for (final item in items) {
      final role = item['role'] as String? ?? '';
      final type = item['type'] as String? ?? 'text';
      final content = item['content'] as String? ?? '';
      final data = item['data'] as Map<String, dynamic>?;

      if (role == 'user') {
        currentAssistant = null;
        if (content.isNotEmpty) {
          messages.add(ChatMessage(role: ChatRole.user, blocks: [ContentBlock.text(content)]));
        }
        continue;
      }

      // Assistant — group consecutive blocks into one message
      currentAssistant ??= () {
        final msg = ChatMessage(role: ChatRole.assistant);
        messages.add(msg);
        return msg;
      }();

      _parseAssistantBlock(currentAssistant, type, content, data);
    }
  }

  /// Parse a single assistant history block into a ContentBlock and add
  /// it to the given ChatMessage. Extracted to avoid duplicating the
  /// switch logic between restoreHistory and loadMoreHistory.
  void _parseAssistantBlock(
    ChatMessage msg, String type, String content, Map<String, dynamic>? data,
  ) {
    switch (type) {
      case 'text':
        if (content.isNotEmpty) msg.appendText(content);
      case 'thought':
        if (content.isNotEmpty) msg.appendThought(content);
      case 'tool_use':
        if (data != null) {
          final locs = castMapList(data['locations']);
          final cbs = castMapList(data['content_blocks']);
          msg.addBlock(ContentBlock.toolCall(
            name: data['name'] as String? ?? content,
            kind: data['kind'] as String?,
            id: data['id'] as String?,
            toolInput: data['tool_input'] as String?,
            locations: locs,
            terminalId: data['terminal_id'] as String?,
            contentBlocks: cbs,
            status: ToolStatus.completed,
          ));
        }
      case 'tool_update':
        if (data != null) {
          final cbs = castMapList(data['content_blocks']);
          msg.updateToolStatus(
            data['id'] as String? ?? '',
            data['status'] as String? ?? 'completed',
            contentBlocks: cbs,
          );
        }
      default:
        if (content.isNotEmpty) msg.addBlock(ContentBlock.text(content));
    }
  }

  // updateDiffContent removed: unified path sends full diff via chat.stream,
  // no separate diff.preview message needed to backfill content.

  /// Whether streaming UI notifications are paused.
  ///
  /// When true, [scheduleStreamNotify] still marks data as dirty but
  /// skips [notifyListeners]. This prevents the message ListView from
  /// rebuilding while the user is scrolled up reading history during
  /// AI streaming — keeping their scroll position perfectly stable.
  ///
  /// Set by ChatScreen when the user scrolls away from the bottom.
  /// When set back to false, any pending dirty data is flushed
  /// immediately so the UI catches up.
  bool _streamNotifyPaused = false;
  bool get streamNotifyPaused => _streamNotifyPaused;
  set streamNotifyPaused(bool value) {
    if (_streamNotifyPaused == value) return;
    _streamNotifyPaused = value;
    // Flush accumulated updates when unpausing
    if (!value && _streamDirty) {
      _streamDirty = false;
      notifyListeners();
    }
  }

  /// Schedule a throttled UI notification (max once per 80ms).
  ///
  /// When [streamNotifyPaused] is true, marks data as dirty but skips
  /// the actual notification. The pending update will be flushed when
  /// the pause is lifted or when [flushStreamNotify] is called.
  void scheduleStreamNotify() {
    _streamDirty = true;
    _streamThrottle ??= Timer.periodic(_streamInterval, (_) {
      if (_streamDirty && !_streamNotifyPaused) {
        _streamDirty = false;
        notifyListeners();
      }
    });
  }

  /// Flush any pending throttled notification immediately.
  void flushStreamNotify() {
    _streamThrottle?.cancel();
    _streamThrottle = null;
    if (_streamDirty) {
      _streamDirty = false;
      notifyListeners();
    }
  }

  /// Clean up timers.
  void disposeChatState() {
    _streamThrottle?.cancel();
  }
}
