/// chat_screen.dart — AI chat main interface.
///
/// Contains the message list, status indicator, IDE-style input bar,
/// and scroll/immersive mode management. Permission dialogs, session
/// picker, and lifecycle state UIs are extracted to separate widgets.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_dialog.dart';
import '../components/app_toast.dart';
import '../core/ui_config.dart';
import '../l10n/app_localizations.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/chat_operations.dart';
import '../services/ws_operations/cli_operations.dart';
import '../theme/theme_extensions.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/cli_lifecycle_states.dart';
import '../widgets/connection_status_indicator.dart';
import '../widgets/pending_review_banner.dart';
import '../widgets/permission_dialog.dart';
import '../widgets/session_picker.dart';
import 'terminal_screen.dart';

/// Main chat screen shown in the Chat tab of [HomeScreen].
///
/// Manages the message list, scroll-lock during streaming, immersive
/// reading mode, and coordinates with extracted widgets for permission
/// dialogs, session picker, and CLI lifecycle states.
/// Includes an embedded terminal view toggled via an AppBar button.
class ChatScreen extends StatefulWidget {
  /// Notifier shared with [HomeScreen] to hide/show the bottom tab bar
  /// when the user enters/exits immersive reading mode.
  final ValueNotifier<bool>? immersiveMode;

  /// Notifier to control terminal visibility from outside (e.g. HomeScreen
  /// responding to navigateToTerminal events).
  final ValueNotifier<bool>? showTerminal;

  const ChatScreen({super.key, this.immersiveMode, this.showTerminal});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  final _inputBarKey = GlobalKey<ChatInputBarState>();
  late final PermissionDialogManager _permissionManager;

  // Session picker open guard (prevents double-open)
  final _sessionPickerOpen = ValueNotifier<bool>(false);

  // ── Scroll-lock during streaming ──
  // When the user scrolls up to read history while AI is streaming,
  // the reverse ListView's index-0 item (newest message) keeps growing.
  // This pushes all older messages upward, shifting what the user sees
  // even though scroll offset doesn't change. We detect when the user
  // has scrolled away from the bottom and pause streaming UI updates
  // so the ListView doesn't rebuild and shift their view.
  static const _kScrollLockThreshold = 20.0;
  bool _userScrolledUp = false;
  late final WebSocketService _ws;

  // ── Immersive reading mode ──
  // Single source of truth is [widget.immersiveMode] ValueNotifier.
  // This screen writes to it on scroll; HomeScreen and this screen's
  // build method both read from it via ValueListenableBuilder.
  // No local _immersive bool — avoids dual-state sync bugs.

  @override
  void initState() {
    super.initState();
    _ws = context.read<WebSocketService>();
    _scrollController.addListener(_onScroll);

    // Exit immersive mode when AI starts responding — the user needs
    // to see the status indicator and input bar during active streaming.
    _ws.addListener(_onWebSocketChanged);

    // Rebuild when immersive mode changes (driven by scroll or AI status).
    widget.immersiveMode?.addListener(_onImmersiveModeChanged);

    // Permission dialog queue manager
    _permissionManager = PermissionDialogManager(context);
    _permissionManager.listen(_ws);

    // Listen for external terminal toggle (from HomeScreen navigateToTerminal)
    widget.showTerminal?.addListener(_onTerminalToggleChanged);
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final colors = context.colors;

    // Read immersive state from the single source of truth (ValueNotifier).
    final immersive = widget.immersiveMode?.value ?? false;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(immersive ? 0 : 44),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: immersive ? 0 : null,
            child: AnimatedOpacity(
              opacity: immersive ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: _buildAppBar(ws),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _isTerminalVisible ? 1 : 0,
        children: [
          // Index 0: Chat content
          Column(
            children: [
              // Pending review banner (shows when AI has unreviewed file edits)
              const PendingReviewBanner(),

              // Message list (AnimatedSwitcher for smooth lifecycle transitions)
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  behavior: HitTestBehavior.translucent,
                  child: ws.currentProjectPath.isEmpty
                      ? const ChatNoProjectState()
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                                opacity: animation, child: child);
                          },
                          child: _buildChatBody(ws),
                        ),
                ),
              ),

              // Status indicator (always visible, auto-hides when idle)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _buildStatusIndicator(ws),
              ),

              // Input bar — hidden in immersive mode
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: immersive
                    ? _buildImmersiveFloatingBar()
                    : ChatInputBar(
                        key: _inputBarKey,
                        ws: ws,
                        onSend: (payload) => _send(ws, payload),
                        onCancel: () => context.read<ChatOperations>().cancelChat(),
                        onLocalCommand: (cmd, args) =>
                            _handleLocalCommand(ws, cmd, args),
                      ),
              ),
            ],
          ),
          // Index 1: Embedded terminal
          const TerminalScreen(embedded: true),
        ],
      ),
    );
  }

  // ── AppBar ──

  AppBar _buildAppBar(WebSocketService ws) {
    final colors = context.colors;
    final typography = context.typography;
    return AppBar(
      backgroundColor: colors.surface,
      titleSpacing: 12,
      toolbarHeight: 44,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            ws.currentProjectName.isNotEmpty
                ? ws.currentProjectName
                : 'MobileFlow',
            style: typography.titleMedium,
          ),
          if (ws.currentProjectPath.isNotEmpty)
            Text(
              ws.currentProjectPath,
              style: typography.codeSmall
                  .copyWith(color: colors.onSurfaceMuted),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
        ],
      ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (ws.cliLifecycleState == CliLifecycleState.ready) ...[
              _AppBarAction(
                icon: Icons.add_comment_outlined,
                onTap: () => _guardSessionSwitch(
                  () => context.read<ChatOperations>().newSession(),
                ),
                color: colors.onSurfaceVariant,
              ),
              _AppBarAction(
                icon: Icons.history,
                onTap: () => showSessionPicker(
                  context: context,
                  openGuard: _sessionPickerOpen,
                  guardSessionSwitch: _guardSessionSwitch,
                ),
                color: colors.onSurfaceVariant,
              ),
            ] else if (ws.cliLifecycleState ==
                CliLifecycleState.failed) ...[
              _AppBarAction(
                icon: Icons.refresh,
                onTap: () => context.read<CliOperations>().retryCli(),
                color: colors.warning,
              ),
            ],
            // Terminal toggle button
            _AppBarAction(
              icon: _isTerminalVisible
                  ? Icons.chat_bubble
                  : Icons.terminal,
              onTap: _toggleTerminal,
              color: _isTerminalVisible
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
            const ConnectionStatusIndicator(),
            const SizedBox(width: 8),
          ],
        ),
      ],
    );
  }

  // ── Chat body ──

  /// Lifecycle-aware chat body: switches UI based on CLI lifecycle state.
  Widget _buildChatBody(WebSocketService ws) {
    final colors = context.colors;
    switch (ws.cliLifecycleState) {
      case CliLifecycleState.checkingEnv:
      case CliLifecycleState.starting:
        return KeyedSubtree(
          key: const ValueKey('initializing'),
          child: CliInitializingState(ws: ws),
        );
      case CliLifecycleState.failed:
        return KeyedSubtree(
          key: const ValueKey('failed'),
          child: CliFailedState(ws: ws),
        );
      case CliLifecycleState.authRequired:
        return KeyedSubtree(
          key: const ValueKey('auth'),
          child: CliAuthRequiredState(ws: ws),
        );
      case CliLifecycleState.ready:
      case CliLifecycleState.uninitialized:
        if (ws.cliLifecycleState == CliLifecycleState.uninitialized &&
            ws.defaultCli.isNotEmpty) {
          return KeyedSubtree(
            key: const ValueKey('initializing'),
            child: CliInitializingState(ws: ws),
          );
        }
        if (ws.isLoadingHistory) {
          return KeyedSubtree(
            key: const ValueKey('loading-history'),
            child: Center(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(S.of(context).chatLoadingHistory,
                    style: TextStyle(color: colors.onSurfaceMuted)),
              ],
            )),
          );
        }
        if (ws.messages.isEmpty) {
          return KeyedSubtree(
            key: const ValueKey('empty'),
            child: ChatEmptyState(onSuggestionTap: _onSuggestionTap),
          );
        }
        return _buildMessageList(ws);
    }
  }

  /// The main message ListView (reverse, with pagination).
  Widget _buildMessageList(WebSocketService ws) {
    final colors = context.colors;
    return ListView.builder(
      key: const ValueKey('messages'),
      controller: _scrollController,
      reverse: true,
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.md,
        vertical: context.spacing.sm,
      ),
      itemCount: ws.messages.length + (ws.hasMoreHistory ? 1 : 0),
      itemBuilder: (context, index) {
        final totalMessages = ws.messages.length;
        // Last item in reversed list = top of screen = "load more"
        if (ws.hasMoreHistory && index == totalMessages) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: ws.isLoadingMoreHistory
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      S.of(context).chatScrollLoadMore,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceMuted,
                      ),
                    ),
            ),
          );
        }
        final msgIndex = totalMessages - 1 - index;
        return ChatBubble(message: ws.messages[msgIndex]);
      },
    );
  }

  // ── Status indicator ──

  Widget _buildStatusIndicator(WebSocketService ws) {
    final colors = context.colors;

    if (ws.agentStatus == AgentStatus.idle) {
      return const SizedBox.shrink();
    }

    final (IconData icon, String label, Color color) =
        switch (ws.agentStatus) {
      AgentStatus.thinking => (
          Icons.psychology,
          S.of(context).chatStatusThinking,
          colors.primary
        ),
      AgentStatus.toolRunning => (
          Icons.build_circle,
          ws.agentStatusDetail.isNotEmpty
              ? '${S.of(context).chatStatusExecuting}: ${ws.agentStatusDetail}'
              : S.of(context).chatStatusToolRunning,
          colors.warning,
        ),
      AgentStatus.streaming => (
          Icons.edit_note,
          S.of(context).chatStatusStreaming,
          colors.secondary
        ),
      AgentStatus.idle => (Icons.circle, '', colors.onSurfaceMuted),
    };

    return AnimatedContainer(
      duration: context.motion.normal,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border:
            Border(top: BorderSide(color: color.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child:
                CircularProgressIndicator(strokeWidth: 1.5, color: color),
          ),
          const SizedBox(width: 4),
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Expanded(
            child: AnimatedSwitcher(
              duration: context.motion.normal,
              child: Text(
                label,
                key: ValueKey(label),
                style: TextStyle(fontSize: 10, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ──

  /// Guard session switch: confirm with user if AI is actively responding.
  void _guardSessionSwitch(VoidCallback onConfirmed) {
    final ws = context.read<WebSocketService>();
    if (ws.agentStatus == AgentStatus.idle) {
      onConfirmed();
      return;
    }

    showAppConfirmDialog(
      context,
      title: S.of(context).chatAiResponding,
      message: S.of(context).chatSwitchSessionWarning,
      confirmLabel: S.of(context).chatSwitchSessionConfirm,
      cancelLabel: S.of(context).commonCancel,
      isDanger: true,
    ).then((confirmed) {
      if (confirmed == true) {
        context.read<ChatOperations>().cancelChat();
        onConfirmed();
      }
    });
  }

  /// Handle local slash commands.
  void _handleLocalCommand(WebSocketService ws, String cmd, String args) {
    switch (cmd) {
      case 'history':
        showSessionPicker(
          context: context,
          openGuard: _sessionPickerOpen,
          guardSessionSwitch: _guardSessionSwitch,
        );
      case 'new':
        _guardSessionSwitch(
          () => context.read<ChatOperations>().newSession(),
        );
      case 'project':
        AppToast.show(context, S.of(context).chatManageProjectHint);
    }
  }

  /// Handle suggestion chip tap from empty state.
  void _onSuggestionTap(String text) {
    _userScrolledUp = false;
    final ws = context.read<WebSocketService>();
    ws.streamNotifyPaused = false;
    context.read<ChatOperations>().sendChat(text);
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut);
    }
  }

  /// Send a message with optional attachments.
  void _send(WebSocketService ws, SendPayload payload) {
    if (payload.text.isEmpty && payload.attachments.isEmpty) return;
    // Reset scroll-lock — user is starting a new turn
    _userScrolledUp = false;
    ws.streamNotifyPaused = false;
    context.read<ChatOperations>().sendChat(payload.text,
        cli: payload.cli,
        attachments:
            payload.attachments.isNotEmpty ? payload.attachments : null,
        localAttachmentPaths: payload.localImagePaths.isNotEmpty
            ? payload.localImagePaths
            : null);
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut);
    }
  }

  // ── Immersive reading mode ──

  /// Exits immersive mode when AI starts responding.
  /// Respects user's scroll position during streaming.
  void _onWebSocketChanged() {
    final ws = context.read<WebSocketService>();
    if (ws.agentStatus != AgentStatus.idle &&
        !_userScrolledUp &&
        (widget.immersiveMode?.value ?? false)) {
      widget.immersiveMode?.value = false;
    }
  }

  void _onImmersiveModeChanged() {
    if (mounted) setState(() {});
  }

  Widget _buildImmersiveFloatingBar() {
    final colors = context.colors;
    final spacing = context.spacing;
    final typography = context.typography;
    final radii = context.radii;
    return GestureDetector(
      onTap: _exitImmersive,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: spacing.sm),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.85),
          border: Border(
            top: BorderSide(
              color: colors.borderSubtle.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.xs,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceElevated.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(radii.full),
              border: Border.all(
                color: colors.borderSubtle.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_alt_outlined,
                    size: 18, color: colors.onSurfaceMuted),
                SizedBox(width: spacing.xs),
                Text(
                  S.of(context).chatTapToInput,
                  style: typography.labelSmall.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _exitImmersive() {
    widget.immersiveMode?.value = false;
    _userScrolledUp = false;
    context.read<WebSocketService>().streamNotifyPaused = false;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ── Scroll handling ──

  /// Scroll listener: scroll-lock, immersive mode, and pagination.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final ws = context.read<WebSocketService>();

    // Scroll-lock: pause streaming UI updates when user reads history
    final wasScrolledUp = _userScrolledUp;
    _userScrolledUp = pos.pixels > _kScrollLockThreshold;
    if (_userScrolledUp != wasScrolledUp) {
      ws.streamNotifyPaused = _userScrolledUp;
    }

    // Immersive mode
    final shouldBeImmersive = pos.pixels > kImmersiveScrollThreshold;
    final currentlyImmersive = widget.immersiveMode?.value ?? false;
    if (shouldBeImmersive != currentlyImmersive) {
      widget.immersiveMode?.value = shouldBeImmersive;
    }

    // Pagination
    final threshold = pos.maxScrollExtent * 0.6;
    final distanceFromTop = pos.maxScrollExtent - pos.pixels;
    if (distanceFromTop <= threshold &&
        ws.hasMoreHistory &&
        !ws.isLoadingMoreHistory) {
      context.read<ChatOperations>().requestMoreHistory();
    }
  }

  @override
  void dispose() {
    _permissionManager.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _ws.removeListener(_onWebSocketChanged);
    widget.immersiveMode?.removeListener(_onImmersiveModeChanged);
    widget.showTerminal?.removeListener(_onTerminalToggleChanged);
    super.dispose();
  }

  /// Rebuild when terminal visibility is toggled externally.
  void _onTerminalToggleChanged() {
    if (mounted) setState(() {});
  }

  /// Toggle between chat and terminal views.
  void _toggleTerminal() {
    final notifier = widget.showTerminal;
    if (notifier != null) {
      notifier.value = !notifier.value;
    }
  }

  /// Whether the terminal view is currently shown.
  bool get _isTerminalVisible => widget.showTerminal?.value ?? false;
}

/// Compact action button for the chat AppBar.
class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _AppBarAction({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
