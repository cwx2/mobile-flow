/// chat_input_bar.dart — IDE-style chat input bar widget.
///
/// Modeled after IDE ui/src/ui/views/chat.ts + app-chat.ts, adapted
/// for mobile. Includes: multi-line input, send/stop button, toolbar
/// (attachments, voice, file references), CLI selector, mode/config
/// controls, token estimation, slash command menu, attachment preview,
/// message queuing, and input history.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/context_reference.dart';
import '../components/app_bottom_sheet.dart';
import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../services/voice_service.dart';
import '../services/websocket_service.dart';
import '../utils/app_config.dart';
import '../utils/input_history.dart';
import '../utils/logger.dart';
import '../theme/theme_extensions.dart';
import 'autocomplete_overlay.dart';
import 'context_chip.dart';
import 'slash_command_menu.dart';
import 'chat_attachment_preview.dart';
import 'context_picker.dart';
import 'input_bar/config_panel.dart';
import 'input_bar/attachment_picker.dart' as attachment;
import 'input_bar/cli_selector.dart';

final _log = getLogger('ChatInput');

/// Maximum number of context references per message.
///
/// Matches the Agent-side `max_references` in ContextConfig (default.json).
/// Prevents users from attaching too many references that would exceed
/// the token budget on the Agent side.
const int kMaxReferences = 10;

/// Chat attachment data model.
class ChatAttachment {
  final String id;
  final String path;
  final String mimeType;

  const ChatAttachment({
    required this.id,
    required this.path,
    required this.mimeType,
  });
}

/// Payload for sending a chat message.
///
/// Encapsulates all data needed to send a message: text, target CLI,
/// base64-encoded attachments for the agent, and local image paths
/// for displaying thumbnails in the chat bubble.
class SendPayload {
  final String text;
  final String cli;
  final List<Map<String, String>> attachments;
  final List<String> localImagePaths;

  const SendPayload({
    required this.text,
    required this.cli,
    this.attachments = const [],
    this.localImagePaths = const [],
  });
}

/// Queued message data model (modeled after IDE's ChatQueueItem).
class QueuedMessage {
  static int _queueSeq = 0;
  final String id;
  final String text;
  final List<ChatAttachment> attachments;

  /// Whether this is a local slash command (executed client-side, not sent to agent).
  final String? localCommandName;

  QueuedMessage({
    String? id,
    required this.text,
    this.attachments = const [],
    this.localCommandName,
  }) : id = id ??
            '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_'
                '${_queueSeq++}';
}

/// Stop command detection (modeled after IDE's isChatStopCommand).
///
/// Typing "stop"/"esc"/"abort"/"wait" is equivalent to /stop.
bool isChatStopCommand(String text) {
  final normalized = text.trim().toLowerCase();
  return const {'stop', '/stop', 'esc', 'abort', 'wait', 'exit'}
      .contains(normalized);
}

/// Local slash commands (modeled after IDE's LOCAL_COMMANDS).
///
/// These commands are handled client-side, not sent to the agent.
const _localSlashCommands = {'new', 'clear', 'history', 'stop', 'project'};

/// IDE-style chat input bar.
///
/// Layout (top to bottom):
/// 1. Slash command menu (shown when typing /)
/// 2. Queued message indicator (messages queued while AI is busy)
/// 3. Attachment preview area (thumbnails when attachments present)
/// 4. Multi-line input field + send/stop button (top-right)
/// 5. Toolbar: left (# file ref, 📎 attach, 🎤 voice) right (CLI selector, token est., mode/config)
class ChatInputBar extends StatefulWidget {
  /// Current WebSocket service instance.
  final WebSocketService ws;

  /// Send callback with structured payload.
  final void Function(SendPayload payload) onSend;

  /// Cancel current AI operation.
  final VoidCallback onCancel;

  /// File picker callback (# button), returns selected file path.
  final Future<String?> Function()? onFileReference;

  /// Currently viewed file path (for Current File reference).
  final String? currentFilePath;

  /// Local slash command callback (/new, /clear, /history, etc.).
  final void Function(String command, String args)? onLocalCommand;

  const ChatInputBar({
    super.key,
    required this.ws,
    required this.onSend,
    required this.onCancel,
    this.onFileReference,
    this.onLocalCommand,
    this.currentFilePath,
  });

  @override
  State<ChatInputBar> createState() => ChatInputBarState();
}

class ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  // Default canRequestFocus=false prevents Flutter's route focus
  // restoration from re-focusing the TextField after dialogs close.
  // Only enabled temporarily when the user taps the TextField directly.
  final _focusNode = FocusNode(canRequestFocus: false);
  final _inputHistory = InputHistory();

  // Voice input service (STT + recording fallback)
  final VoiceService _voice = VoiceService();
  bool _sttListening = false;
  String _sttInterimText = '';

  // Swipe-up-to-cancel tracking for voice input
  bool _voiceCancelled = false;

  // Snapshot of input text before voice session starts, used to
  // restore on cancel so pre-existing user input is not lost.
  String _textBeforeVoice = '';

  // Attachment list
  final List<ChatAttachment> _attachments = [];

  // Message queue (modeled after IDE's chatQueue)
  final List<QueuedMessage> _queue = [];

  // Slash command menu state
  bool _slashMenuOpen = false;

  // # autocomplete overlay state (tracks text after the last `#`)
  bool _autocompleteOpen = false;
  String _autocompleteQuery = '';

  // Autopilot removed — use ACP mode switching instead

  // Voice/keyboard mode toggle
  bool _voiceMode = false;

  // Dequeue lock (prevents chatDone firing multiple times causing duplicate sends)
  bool _flushing = false;

  // Listen for chatDone to process queued messages (modeled after IDE's flushChatQueue)
  StreamSubscription? _chatDoneSub;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    // Track previous focus state to avoid redundant setState/log calls
    bool wasFocused = false;
    _focusNode.addListener(() {
      final isFocused = _focusNode.hasFocus;
      if (isFocused == wasFocused) return; // No actual change
      wasFocused = isFocused;
      _log.fine('输入框焦点变化: hasFocus=$isFocused');
      if (!isFocused) {
        // Re-disable focus requests after losing focus, so only
        // explicit user taps can re-acquire focus.
        _focusNode.canRequestFocus = false;
      }
      setState(() {});
    });
    _initVoice();
    _inputHistory.load(); // Restore persisted history
    _chatDoneSub = widget.ws.messageStream.listen((msg) {
      if (msg.type == 'chat.done' && _queue.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 50), _flushQueue);
      }
    });
  }

  @override
  void didUpdateWidget(ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ws != widget.ws) {
      _chatDoneSub?.cancel();
      _chatDoneSub = widget.ws.messageStream.listen((msg) {
        if (msg.type == 'chat.done' && _queue.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 50), _flushQueue);
        }
      });
      // Reset voice mode when CLI changes — the new CLI may not
      // support audio, causing the voice button to hide.
      if (_voiceMode && !_isVoiceEnabled) {
        _voiceMode = false;
      }
    }
  }

  /// Text change listener.
  ///
  /// Detects slash commands (`/`) and `#` autocomplete triggers.
  /// For `#`: scans backward from the cursor to find the last `#`
  /// that is either at position 0 or preceded by a space, then
  /// extracts the query text after it.
  void _onTextChanged() {
    final text = _controller.text;
    // Slash command detection: starts with / and no spaces (typing command name)
    final shouldShowSlash =
        text.startsWith('/') && !text.contains(' ') && text.length < 20;
    if (shouldShowSlash != _slashMenuOpen) {
      setState(() => _slashMenuOpen = shouldShowSlash);
    }

    // # autocomplete detection: find the last `#` preceded by space or at start
    bool shouldShowAutocomplete = false;
    String query = '';
    if (!_slashMenuOpen) {
      final cursor = _controller.selection.baseOffset;
      // Use cursor position if valid, otherwise scan from end
      final scanEnd = (cursor >= 0 && cursor <= text.length)
          ? cursor
          : text.length;
      final textBeforeCursor = text.substring(0, scanEnd);
      final hashIdx = textBeforeCursor.lastIndexOf('#');
      if (hashIdx >= 0) {
        // `#` must be at start or preceded by whitespace (not mid-word)
        final validStart =
            hashIdx == 0 || textBeforeCursor[hashIdx - 1] == ' ';
        if (validStart) {
          final afterHash = textBeforeCursor.substring(hashIdx + 1);
          // Show overlay only when there are chars after # and no spaces
          if (afterHash.isNotEmpty && !afterHash.contains(' ')) {
            shouldShowAutocomplete = true;
            query = afterHash;
          }
        }
      }
    }

    if (shouldShowAutocomplete != _autocompleteOpen || query != _autocompleteQuery) {
      setState(() {
        _autocompleteOpen = shouldShowAutocomplete;
        _autocompleteQuery = query;
      });
    }

    // Reset input history cursor
    _inputHistory.reset();
  }

  /// Token estimation (modeled after IDE: ~1 token per 4 chars).
  String? _tokenEstimate() {
    final len = _controller.text.length;
    if (len < 100) return null;
    return '~${(len / 4).ceil()} tokens';
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = widget.ws.agentStatus != AgentStatus.idle;
    final hasText = _controller.text.trim().isNotEmpty;
    final hasAttachments = _attachments.isNotEmpty;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final colors = context.colors;
    final noCli = widget.ws.installedClis.isEmpty;

    // No installed CLIs → show prompt
    if (noCli) {
      return Container(
        decoration: BoxDecoration(
          color: colors.surfaceDim,
          boxShadow: [
            BoxShadow(
              color: colors.scrim.withValues(alpha: context.isDark ? 0.15 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding + 16),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: colors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                S.of(context).chatInputInstallAgent,
                style: TextStyle(fontSize: 13, color: colors.onSurfaceMuted),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceDim,
            // Soft gradient shadow instead of hard border line
            boxShadow: [
              BoxShadow(
                color: colors.scrim.withValues(alpha: context.isDark ? 0.15 : 0.06),
                blurRadius: 8,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Slash command menu
              if (_slashMenuOpen)
                SlashCommandMenu(
                  filter: _controller.text.substring(1),
                  onSelect: _onSlashCommandSelected,
                  onDismiss: () => setState(() => _slashMenuOpen = false),
                  cliCommands: widget.ws.cliCommands,
                ),

              // 2. Queued message indicator
              if (_queue.isNotEmpty) _buildQueueIndicator(),

              // 3. Attachment preview
              if (hasAttachments)
                ChatAttachmentPreview(
                  attachments: _attachments,
                  onRemove: _removeAttachment,
                ),

              // 3.1 # autocomplete overlay (shown inline above input)
              if (_autocompleteOpen)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: AutocompleteOverlay(
                    query: _autocompleteQuery,
                    ws: widget.ws,
                    onSelect: _onAutocompleteSelect,
                    onDismiss: () => setState(() {
                      _autocompleteOpen = false;
                      _autocompleteQuery = '';
                    }),
                  ),
                ),

              // 3.2 Context chips row (pending references)
              if (widget.ws.pendingContextReferences.isNotEmpty)
                _buildContextChipsRow(),

              // 4. Input row: [camera] [input/hold-to-talk] [voice↔keyboard] [send]
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: _buildInputRow(isBusy, hasText),
              ),

              // 5. Toolbar
              Padding(
                padding: EdgeInsets.fromLTRB(6, 2, 6, bottomPadding + 4),
                child: _buildToolbar(isBusy),
              ),
            ],
          ),
        ),

        // Voice recording overlay — floats above the input bar,
        // does not push content or occupy layout space.
        // AnimatedSwitcher provides fade transition per spec §9.5.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            child: _sttListening
                ? Container(
                    key: const ValueKey('voice-overlay'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: _voiceCancelled
                          ? colors.error.withValues(alpha: 0.95)
                          : colors.surfaceDim.withValues(alpha: 0.95),
                    ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Interim text preview
                  if (_sttInterimText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        _sttInterimText,
                        style: TextStyle(
                          fontSize: 14,
                          color: _voiceCancelled
                              ? Colors.white.withValues(alpha: 0.6)
                              : colors.onSurface,
                          decoration: _voiceCancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // Wave animation + status
                  Row(
                    children: [
                      Icon(
                        _voiceCancelled ? Icons.cancel_outlined : Icons.mic,
                        size: 16,
                        color: _voiceCancelled ? Colors.white : colors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _VoiceWaveAnimation(
                          color: _voiceCancelled ? Colors.white : colors.error,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _voiceCancelled ? S.of(context).chatInputVoiceReleaseCancel : S.of(context).chatInputVoiceListening,
                        style: TextStyle(
                          fontSize: 12,
                          color: _voiceCancelled ? Colors.white : colors.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
                : const SizedBox.shrink(key: ValueKey('voice-hidden')),
          ),
        ),
      ],
    );
  }

  /// Input row: [camera] [text field / hold-to-talk] [voice↔keyboard] [send/stop].
  ///
  /// In keyboard mode: shows a normal text field with camera on the left.
  /// In voice mode: shows a "hold to talk" button that records on long-press.
  /// The voice/keyboard toggle button switches between the two modes.
  Widget _buildInputRow(bool isBusy, bool hasText) {
    final colors = context.colors;
    final isReady = widget.ws.cliLifecycleState == CliLifecycleState.ready;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Camera button (left side)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: GestureDetector(
            onTap: isReady ? _takePhoto : null,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceVariant,
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: 18,
                color: isReady ? colors.onSurfaceVariant : colors.onSurfaceMuted.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Center: text field (voice overlay when in voice mode)
        Expanded(
          child: _buildTextField(isBusy),
        ),
        const SizedBox(width: 4),

        // Voice/keyboard toggle (right side)
        // Only shown when voice input is actually usable:
        // STT available (text output) or recording + CLI supports audio.
        if (!isBusy && !hasText && _attachments.isEmpty && _isVoiceEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GestureDetector(
              onTap: () => setState(() => _voiceMode = !_voiceMode),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceVariant,
                ),
                child: Icon(
                  _voiceMode ? Icons.keyboard_outlined : Icons.mic_none,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),

        // Send/stop button (rightmost)
        if (isBusy || hasText || _attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _buildSendStopButton(isBusy, hasText),
          ),
      ],
    );
  }

  /// Text input field with rounded container.
  Widget _buildTextField(bool isBusy) {
    final colors = context.colors;
    final showVoiceOverlay = _voiceMode && _controller.text.isEmpty;
    return GestureDetector(
      onLongPressStart: (_) => _startVoiceRecording(),
      onLongPressMoveUpdate: (details) {
        // Swipe up to cancel: negative dy means upward movement.
        // 50dp threshold prevents accidental cancellation.
        if (!_sttListening) return;
        final cancelled = details.offsetFromOrigin.dy < -50;
        if (cancelled != _voiceCancelled) {
          setState(() => _voiceCancelled = cancelled);
        }
      },
      onLongPressEnd: (_) => _stopVoiceRecording(),
      onTap: showVoiceOverlay
          ? () => AppToast.show(context, S.of(context).chatInputVoiceHoldToTalk)
          : null,
      child: Stack(
        children: [
          // Always-present TextField (keeps consistent height)
          IgnorePointer(
            ignoring: showVoiceOverlay,
            child: Opacity(
              opacity: showVoiceOverlay ? 0.0 : 1.0,
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _focusNode.hasFocus && !showVoiceOverlay
                        ? colors.primary.withValues(alpha: 0.5)
                        : colors.borderSubtle,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 6,
                  minLines: 1,
                  style: TextStyle(fontSize: 14, color: colors.onSurface),
                  decoration: InputDecoration(
                    hintText: _getPlaceholder(isBusy),
                    hintMaxLines: 1,
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: isBusy
                          ? colors.error.withValues(alpha: 0.4)
                          : colors.onSurfaceMuted,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) => setState(() {}),
                  onTap: () {
                    _focusNode.canRequestFocus = true;
                    _focusNode.requestFocus();
                    if (_voiceMode) setState(() => _voiceMode = false);
                  },
                ),
              ),
            ),
          ),
          // Voice overlay (exact same size as TextField container)
          if (showVoiceOverlay)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: _sttListening
                      ? (_voiceCancelled
                          ? colors.error.withValues(alpha: 0.2)
                          : colors.error.withValues(alpha: 0.12))
                      : colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _sttListening
                        ? colors.error.withValues(alpha: 0.4)
                        : colors.borderSubtle,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _sttListening
                      ? (_voiceCancelled ? S.of(context).chatInputVoiceReleaseToCancel : S.of(context).chatInputVoiceSwipeToCancel)
                      : S.of(context).chatInputVoiceHoldToSpeak,
                  style: TextStyle(
                    fontSize: 14,
                    color: _sttListening
                        ? colors.error
                        : colors.onSurfaceMuted,
                    fontWeight:
                        _sttListening ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Take a photo using the camera and add as attachment.
  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: CameraConfig.imageQuality,
        maxWidth: CameraConfig.maxWidth,
      );
      if (photo != null && mounted) {
        setState(() {
          _attachments.add(ChatAttachment(
            id: '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_cam',
            path: photo.path,
            mimeType: 'image/jpeg',
          ));
        });
      }
    } catch (e) {
      _log.severe('拍照失败: $e');
      if (mounted) {
        AppToast.show(context, S.of(context).chatInputPhotoFailed, type: AppToastType.error);
      }
    }
  }

  /// Get placeholder text based on lifecycle state and input context
  String _getPlaceholder(bool isBusy) {
    final l10n = S.of(context);
    if (_sttListening) return l10n.chatInputListening;
    // Lifecycle-aware placeholders
    if (widget.ws.cliLifecycleState == CliLifecycleState.checkingEnv ||
        widget.ws.cliLifecycleState == CliLifecycleState.starting) {
      return l10n.chatInputAgentStarting;
    }
    if (widget.ws.cliLifecycleState == CliLifecycleState.failed) {
      return l10n.chatInputAgentFailed;
    }
    if (widget.ws.cliLifecycleState == CliLifecycleState.authRequired) {
      return l10n.chatInputAuthRequired;
    }
    if (isBusy) return l10n.chatInputQueuedHint;
    if (_attachments.isNotEmpty) return l10n.chatInputAttachmentHint;
    return l10n.chatInputDefaultHint;
  }

  /// Send/stop button.
  /// - AI busy: red stop button with spinner
  /// - Has text/attachments: primary send button
  Widget _buildSendStopButton(bool isBusy, bool hasText) {
    final colors = context.colors;
    if (isBusy) {
      return GestureDetector(
        onTap: widget.onCancel,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.error,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0x60FFFFFF),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Send button
    return GestureDetector(
      onTap: _handleSend,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primary,
        ),
        child: const Icon(Icons.arrow_upward, size: 18, color: Colors.white),
      ),
    );
  }

  /// Toolbar (modeled after IDE's agent-chat__toolbar).
  Widget _buildToolbar(bool isBusy) {
    final tokens = _tokenEstimate();
    final colors = context.colors;

    final caps = widget.ws.cliCapabilities;
    final isReady = widget.ws.cliLifecycleState == CliLifecycleState.ready;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // # Context reference (always visible — contains file, terminal, URL, git diff, etc.)
        _buildToolbarButton(
            icon: SizedBox(
                width: 18,
                height: 18,
                child: Center(
                  child: Text('#',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.onSurfaceVariant,
                          height: 1)),
                )),
            tooltip: S.of(context).chatInputTooltipReference,
            onTap: _handleFileReference,
          ),
        // 📎 Attachment menu (shows available types based on capabilities)
        _buildToolbarButton(
          icon: Icon(Icons.attach_file, size: 18,
              color: isReady ? colors.onSurfaceVariant : colors.onSurfaceMuted.withValues(alpha: 0.4)),
          tooltip: S.of(context).chatInputTooltipAttachment,
          onTap: isReady ? () => attachment.showAttachmentMenu(
            context: context,
            ws: widget.ws,
            isReady: isReady,
            onAdd: (att) => setState(() => _attachments.add(att)),
            currentFilePath: widget.currentFilePath,
          ) : () => AppToast.show(context, S.of(context).chatInputAgentNotReady),
        ),

        // Input history (moved from long-press on input field)
        if (_inputHistory.isNotEmpty)
          _buildToolbarButton(
            icon: Icon(Icons.history, size: 16, color: colors.onSurfaceVariant),
            tooltip: S.of(context).chatInputTooltipHistory,
            onTap: _showInputHistory,
          ),

        // token estimate
        if (tokens != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(tokens,
                style: TextStyle(fontSize: 10, color: colors.onSurfaceMuted)),
          ),

        // Reference count summary (e.g., "2 files, 1 folder")
        if (widget.ws.pendingContextReferences.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              _referenceCountSummary(),
              style: TextStyle(fontSize: 10, color: colors.primary),
            ),
          ),

        const Spacer(),

        // Right side: mode/config/CLI selectors
        if (caps.availableModes.isNotEmpty)
          ModeSelector(ws: widget.ws),
        ConfigButton(ws: widget.ws),
        if (caps.availableModes.isNotEmpty || widget.ws.configOptions.isNotEmpty)
          const SizedBox(width: 4),
        CliSelector(ws: widget.ws),
      ],
    );
  }

  /// Toolbar button (unified style, no Tooltip to avoid ticker conflicts).
  Widget _buildToolbarButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      onLongPress: () {
        AppToast.show(context, tooltip);
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: icon,
      ),
    );
  }

  /// Horizontally scrollable row of context chips above the text input.
  ///
  /// Reads from [widget.ws.pendingContextReferences] and renders a
  /// [ContextChip] for each. Each chip's remove button calls
  /// [WebSocketService.removeContextReference].
  Widget _buildContextChipsRow() {
    final refs = widget.ws.pendingContextReferences;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final ref in refs) ...[
              ContextChip(
                reference: ref,
                onRemove: () => widget.ws.removeContextReference(ref.id),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact reference count summary for the toolbar.
  ///
  /// Groups pending references by type and returns a string like
  /// "2 files, 1 folder". Keeps the format short for mobile.
  String _referenceCountSummary() {
    final refs = widget.ws.pendingContextReferences;
    final counts = <String, int>{};
    for (final ref in refs) {
      final label = switch (ref.type) {
        ContextRefType.files => 'file',
        ContextRefType.folder => 'folder',
        ContextRefType.gitDiff => 'diff',
        ContextRefType.terminal => 'terminal',
        ContextRefType.url => 'url',
        ContextRefType.problems => 'problems',
        ContextRefType.currentFile => 'file',
      };
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts.entries.map((e) => '${e.value} ${e.key}').join(', ');
  }

  /// Handle autocomplete item selection.
  ///
  /// Adds the selected [ContextReference] to pending references,
  /// removes the `#query` text from the input field, and dismisses
  /// the overlay. Enforces [kMaxReferences] limit.
  void _onAutocompleteSelect(ContextReference ref) {
    // Enforce max references limit
    if (widget.ws.pendingContextReferences.length >= kMaxReferences) {
      AppToast.show(context, S.of(context).chatInputMaxReferences);
      _log.fine('上下文引用已达上限: $kMaxReferences');
      return;
    }

    widget.ws.addContextReference(ref);
    _log.fine('自动补全添加引用: type=${ref.typeString}, path=${ref.path}');

    // Remove the #query text from the input field
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final scanEnd = (cursor >= 0 && cursor <= text.length)
        ? cursor
        : text.length;
    final textBeforeCursor = text.substring(0, scanEnd);
    final hashIdx = textBeforeCursor.lastIndexOf('#');
    if (hashIdx >= 0) {
      final afterCursor = text.substring(scanEnd);
      final beforeHash = text.substring(0, hashIdx);
      _controller.text = '$beforeHash$afterCursor';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: beforeHash.length),
      );
    }

    setState(() {
      _autocompleteOpen = false;
      _autocompleteQuery = '';
    });
  }








  /// Queued message indicator (modeled after IDE's chat-queue).
  Widget _buildQueueIndicator() {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.queue, size: 14, color: colors.warning),
          const SizedBox(width: 6),
          Text(S.of(context).chatInputQueueCount(_queue.length),
              style: TextStyle(fontSize: 12, color: colors.warning)),
          const Spacer(),
          ...List.generate(
            _queue.length > 3 ? 3 : _queue.length,
            (i) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 80),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(_queue[i].text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 10, color: colors.onSurface)),
                    ),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: () => _removeFromQueue(_queue[i].id),
                      child: Icon(Icons.close,
                          size: 10, color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_queue.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('+${_queue.length - 3}',
                  style:
                      TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  // ── Core operations ──

  /// Send message (modeled after IDE's handleSendChat).
  ///
  /// Full flow:
  /// 1. Detect stop command → cancel
  /// 2. Parse slash command → execute locally or send to agent
  /// 3. Busy → queue
  /// 4. Idle → send directly (attachments converted to base64)
  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;

    // Dismiss autocomplete overlay if open
    if (_autocompleteOpen) {
      setState(() {
        _autocompleteOpen = false;
        _autocompleteQuery = '';
      });
    }

    // 1. Stop command detection (modeled after IDE's isChatStopCommand)
    if (isChatStopCommand(text)) {
      _controller.clear();
      widget.onCancel();
      return;
    }

    // 2. Slash command parsing
    final slashParsed = _parseSlashCommand(text);
    if (slashParsed != null) {
      _controller.clear();
      setState(() => _slashMenuOpen = false);
      final (cmdName, args) = slashParsed;

      if (_localSlashCommands.contains(cmdName)) {
        final isBusy = widget.ws.agentStatus != AgentStatus.idle;
        if (isBusy) {
          setState(() {
            _queue.add(QueuedMessage(
              text: text,
              localCommandName: cmdName,
            ));
          });
        } else {
          _executeLocalCommand(cmdName, args);
        }
        return;
      }
    }

    final isBusy = widget.ws.agentStatus != AgentStatus.idle;

    // 3. Queue when busy (modeled after IDE's enqueueChatMessage)
    if (isBusy) {
      setState(() {
        _queue.add(QueuedMessage(
          text: text,
          attachments: List.from(_attachments),
        ));
        _controller.clear();
        _attachments.clear();
      });
      return;
    }

    // 4. Send directly (convert attachments to base64)
    if (text.isNotEmpty) _inputHistory.push(text);
    _sendWithAttachments(text);
  }

  /// Read attachment files, convert to base64, then send.
  ///
  /// Attachment format (modeled after IDE's dataUrlToBase64 + sendChatMessage):
  /// [{type: "image", mimeType: "image/jpeg", content: "<base64>"}]
  Future<void> _sendWithAttachments(String text) async {
    final List<Map<String, String>> apiAttachments = [];

    // Collect local image paths for UI display before base64 conversion.
    // Must be done before clearing _attachments at the end.
    final localPaths = _attachments
        .where((a) => a.mimeType.startsWith('image/'))
        .map((a) => a.path)
        .toList();

    for (final att in _attachments) {
      try {
        // File reference attachments (resource / resource_link)
        if (att.mimeType == 'resource' || att.mimeType == 'resource_link') {
          apiAttachments.add({
            'type': att.mimeType,
            'uri': 'file:///${att.path}',
            'name': att.path.split('/').last,
          });
          continue;
        }

        // Binary attachments (image / audio) — read file and base64 encode
        final file = File(att.path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final base64Data = base64Encode(bytes);
          // Determine type from mimeType prefix
          final type = att.mimeType.startsWith('audio/') ? 'audio' : 'image';
          apiAttachments.add({
            'type': type,
            'mime_type': att.mimeType,
            'content': base64Data,
          });
        }
      } catch (e) {
        _log.severe('读取附件失败: ${att.path} - $e');
      }
    }

    widget.onSend(SendPayload(
      text: text,
      cli: widget.ws.defaultCli,
      attachments: apiAttachments,
      localImagePaths: localPaths,
    ));
    _controller.clear();
    setState(() => _attachments.clear());
  }

  /// Parse slash command (modeled after IDE's parseSlashCommand).
  ///
  /// Returns (commandName, args) or null.
  (String, String)? _parseSlashCommand(String text) {
    if (!text.startsWith('/')) return null;
    final body = text.substring(1);
    final spaceIdx = body.indexOf(' ');
    if (spaceIdx == -1) return (body.toLowerCase(), '');
    return (
      body.substring(0, spaceIdx).toLowerCase(),
      body.substring(spaceIdx + 1).trim()
    );
  }

  /// Execute a local slash command (modeled after IDE's dispatchSlashCommand).
  void _executeLocalCommand(String name, String args) {
    switch (name) {
      case 'new':
        widget.onLocalCommand?.call('new', args);
      case 'clear':
        widget.ws.clearMessages();
      case 'stop':
        widget.onCancel();
      case 'history':
        widget.onLocalCommand?.call('history', args);
      case 'project':
        widget.onLocalCommand?.call('project', args);
      default:
        // Unknown local command — send to agent
        widget.onSend(SendPayload(text: '/$name $args'.trim(), cli: widget.ws.defaultCli));
    }
  }

  /// Dequeue and send the next queued message (modeled after IDE's flushChatQueue).
  ///
  /// Called automatically after chatDone.
  void _flushQueue() {
    if (_queue.isEmpty) return;
    if (widget.ws.agentStatus != AgentStatus.idle) return;
    if (_flushing) return; // Prevent duplicate calls
    _flushing = true;

    final next = _queue.removeAt(0);
    if (mounted) setState(() {});

    if (next.localCommandName != null) {
      _flushing = false;
      _executeLocalCommand(next.localCommandName!, '');
      if (_queue.isNotEmpty) {
        Future.microtask(_flushQueue);
      }
    } else {
      Future.microtask(() async {
        final List<Map<String, String>> apiAttachments = [];
        for (final att in next.attachments) {
          try {
            if (att.mimeType == 'resource' || att.mimeType == 'resource_link') {
              apiAttachments.add({
                'type': att.mimeType,
                'uri': 'file:///${att.path}',
                'name': att.path.split('/').last,
              });
              continue;
            }
            final file = File(att.path);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              final type = att.mimeType.startsWith('audio/') ? 'audio' : 'image';
              apiAttachments.add({
                'type': type,
                'mime_type': att.mimeType,
                'content': base64Encode(bytes),
              });
            }
          } catch (e) {
            _log.severe('排队附件读取失败: $e');
          }
        }
        widget.onSend(SendPayload(
          text: next.text,
          cli: widget.ws.defaultCli,
          attachments: apiAttachments,
        ));
        _flushing = false;
      });
    }
  }

  /// Remove a message from the queue.
  void _removeFromQueue(String id) {
    setState(() => _queue.removeWhere((q) => q.id == id));
  }

  /// # Context reference (replicates IDE's # menu).
  ///
  /// Tap # → show context type list (Files/Folder/Terminal/URL/...)
  /// → select type → show sub-picker → add structured reference to
  /// pending list (sent with next message via `sendChat` payload).
  /// Enforces [kMaxReferences] limit before opening the picker.
  Future<void> _handleFileReference() async {
    // Enforce max references limit before opening picker
    if (widget.ws.pendingContextReferences.length >= kMaxReferences) {
      AppToast.show(context, S.of(context).chatInputMaxReferences);
      return;
    }

    final picker = ContextPicker(
      ws: widget.ws,
      context: context,
      currentFilePath: widget.currentFilePath,
    );
    final ref = await picker.show();
    _log.fine('📋 ContextPicker 返回: ${ref?.type}');
    if (ref != null && mounted) {
      widget.ws.addContextReference(ref);
    }
  }







  /// Remove an attachment by ID.
  void _removeAttachment(String id) {
    setState(() => _attachments.removeWhere((a) => a.id == id));
  }

  /// Initialize the voice input service (STT + recording fallback).
  Future<void> _initVoice() async {
    await _voice.init();

    _voice.onFinalResult = (text) {
      if (!mounted) return;
      // Fill recognized text into input field for user to review/edit.
      // Do NOT auto-send — user decides when to send.
      // Cancel logic is handled in _stopVoiceRecording (restores snapshot).
      final current = _controller.text;
      final sep = current.isNotEmpty && !current.endsWith(' ') ? ' ' : '';
      _controller.text = '$current$sep$text';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _log.info('🎤 识别结果填入输入框: "${text.length > 40 ? '${text.substring(0, 40)}...' : text}"');
      setState(() => _sttInterimText = '');
    };

    _voice.onInterimResult = (text) {
      if (!mounted) return;
      setState(() => _sttInterimText = text);
    };

    _voice.onNoResult = () {
      if (!mounted) return;
      AppToast.show(context, S.of(context).chatInputVoiceNoResult);
    };

    _voice.onAudioRecorded = (bytes, mimeType) {
      if (!mounted) return;
      _log.info('🎤 录音完成，发送音频附件: ${(bytes.length / 1024).toStringAsFixed(1)}KB');
      // Send audio as attachment via existing multimodal channel
      widget.ws.chatOps.sendChat(
        '',
        attachments: [
          {'type': 'audio', 'mime_type': mimeType, 'content': base64Encode(bytes)},
        ],
      );
    };

    _voice.onError = (error) {
      if (!mounted) return;
      AppToast.show(context, error, type: AppToastType.error);
      setState(() {
        _sttListening = false;
        _sttInterimText = '';
      });
    };

    // Sync state when VoiceService notifies
    _voice.addListener(() {
      if (!mounted) return;
      setState(() {
        _sttListening = _voice.isListening;
        _sttInterimText = _voice.interimText;
      });
    });

    // Force rebuild after async init completes so _isVoiceEnabled
    // is re-evaluated and the voice button appears if available.
    if (mounted) setState(() {});
  }

  /// Whether voice input is usable in the current context.
  ///
  /// Voice is enabled when:
  /// - STT mode: system speech-to-text converts voice to text (works
  ///   regardless of CLI audio support).
  /// - Recording mode: CLI must support audio input to receive raw audio.
  /// Hidden entirely when neither path is viable.
  bool get _isVoiceEnabled {
    if (!_voice.isAvailable) return false;
    if (_voice.mode == VoiceMode.stt) return true;
    // Recording mode only useful when CLI can accept audio
    return widget.ws.cliCapabilities.supportsAudio;
  }

  /// Long-press to start voice input.
  void _startVoiceRecording() {
    _log.info('🎤 语音按钮按下: mode=${_voice.mode}');
    if (!_isVoiceEnabled) {
      AppToast.show(
        context,
        S.of(context).chatInputVoiceUnsupported,
        type: AppToastType.error,
      );
      return;
    }

    setState(() {
      _sttListening = true;
      _sttInterimText = '';
      _voiceCancelled = false;
      _textBeforeVoice = _controller.text;
    });

    _voice.startListening();
  }

  /// Release to stop voice input.
  ///
  /// If user swiped up (_voiceCancelled), restore input field to
  /// its pre-recording state (discard all recognized text).
  /// Otherwise, keep recognized text in the input field for the
  /// user to review/edit before sending manually.
  void _stopVoiceRecording() {
    if (!_sttListening) return;

    final wasCancelled = _voiceCancelled;
    _voice.stopListening();

    if (wasCancelled) {
      _log.info('🎤 语音输入已取消（上滑），恢复录音前文字');
      // Restore input field to pre-recording snapshot, discarding
      // any text appended by onFinalResult during this session.
      _controller.text = _textBeforeVoice;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _textBeforeVoice.length),
      );
    }

    setState(() {
      _sttListening = false;
      _sttInterimText = '';
      _voiceCancelled = false;
      // Switch back to keyboard mode so user can edit the filled text
      if (!wasCancelled && _controller.text.isNotEmpty) {
        _voiceMode = false;
      }
    });
  }

  /// Show input history (triggered by long-press on input field).
  ///
  /// Mobile doesn't have keyboard up/down arrows, so long-press
  /// opens a history list as a replacement.
  void _showInputHistory() {
    final entries = _inputHistory.entries;
    if (entries.isEmpty) {
      AppToast.show(context, S.of(context).chatInputNoHistory);
      return;
    }

    AppBottomSheet.show(context, builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top spacing already provided by AppBottomSheet drag handle
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(S.of(context).chatInputHistoryTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: entries.length,
              itemBuilder: (_, i) {
                // Already sorted by lastUsed descending from InputHistory.entries
                final entry = entries[i];
                return ListTile(
                  leading: Icon(Icons.history,
                      size: 16, color: context.colors.onSurfaceVariant),
                  title: Text(entry.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  // Show use count badge for frequently used entries
                  trailing: entry.useCount > 1
                      ? Text('${entry.useCount}×',
                          style: TextStyle(
                              fontSize: 11,
                              color: context.colors.onSurfaceMuted))
                      : null,
                  dense: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _controller.text = entry.text;
                    _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: entry.text.length),
                    );
                    _focusNode.canRequestFocus = true;
                    _focusNode.requestFocus();
                  },
                );
              },
            ),
          ),
        ],
      );
    });
  }


  /// Slash command selection callback.
  void _onSlashCommandSelected(SlashCommand cmd) {
    setState(() => _slashMenuOpen = false);
    if (cmd.immediate) {
      _controller.text = '/${cmd.name}';
      _handleSend();
    } else {
      _controller.text = '/${cmd.name} ';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _focusNode.canRequestFocus = true;
      _focusNode.requestFocus();
    }
  }

  /// Insert text at cursor position (called externally, e.g. from file reference picker).
  void insertText(String text) {
    final current = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final before = cursor >= 0 ? current.substring(0, cursor) : current;
    final after =
        cursor >= 0 && cursor < current.length ? current.substring(cursor) : '';
    _controller.text = '$before$text$after';
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: before.length + text.length),
    );
    _focusNode.canRequestFocus = true;
    _focusNode.requestFocus();
  }

  /// Get the currently selected CLI.
  String get selectedCli => widget.ws.defaultCli;

  /// Get auto-approve permissions state
  bool get isAutoApprove => widget.ws.autoApprovePermissions;

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(() {});
    _controller.dispose();
    _focusNode.dispose();
    _chatDoneSub?.cancel();
    if (_sttListening) _voice.stopListening();
    _voice.dispose();
    super.dispose();
  }
}

/// Voice wave animation (shown during recording).
class _VoiceWaveAnimation extends StatefulWidget {
  final Color color;
  const _VoiceWaveAnimation({required this.color});

  @override
  State<_VoiceWaveAnimation> createState() => _VoiceWaveAnimationState();
}

class _VoiceWaveAnimationState extends State<_VoiceWaveAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    // Bar width + horizontal margin = total width per bar
    const barWidth = 3.0;
    const barMargin = 1.5;
    const barTotal = barWidth + barMargin * 2; // 6dp per bar

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return LayoutBuilder(
          builder: (_, constraints) {
            // Dynamically calculate bar count to fill available width
            final count = (constraints.maxWidth / barTotal).floor().clamp(8, 60);
            return SizedBox(
              height: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(count, (i) {
                  final phase = (_controller.value * 2 * 3.14159) + (i * 0.4);
                  final height = 4.0 + 8.0 * ((1 + _sin(phase)) / 2);
                  return Container(
                    width: barWidth,
                    height: height,
                    margin: const EdgeInsets.symmetric(horizontal: barMargin),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  );
                }),
              ),
            );
          },
        );
      },
    );
  }

  double _sin(double x) {
    // Simple sin approximation to avoid importing dart:math
    x = x % (2 * 3.14159);
    if (x > 3.14159) x -= 2 * 3.14159;
    return x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
