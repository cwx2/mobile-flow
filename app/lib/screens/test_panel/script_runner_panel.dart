/// script_runner_panel.dart — Script execution panel for the Test Panel.
///
/// Module: screens/test_panel/
/// Responsibility:
///   Command input, execution control (run/stop), and terminal-style
///   output display. Listens to messageStream for script.output and
///   script.done messages from the Agent.
///
/// Called by:
///   - TestPanelScreen (Phase 6, Task 11.1) as one of the sub-panels
///   - Can be used standalone for testing during Phase 1
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/payloads/test_panel_payloads.dart';
import '../../models/protocol.dart';
import '../../l10n/app_localizations.dart';
import '../../services/websocket_service.dart';
import '../../services/ws_operations/test_panel_operations.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/logger.dart';

final _log = getLogger('ScriptRunner');

/// Maximum number of output lines to keep in the buffer.
///
/// Prevents unbounded memory growth for long-running commands.
/// Oldest lines are trimmed when the limit is exceeded.
const int _kMaxOutputLines = 10000;

/// Maximum number of commands to keep in history.
const int _kMaxHistorySize = 20;

/// Script execution state.
enum _ScriptState { idle, running, completed, failed, killed }

/// Script Runner Panel — command input + terminal-style output.
///
/// Provides a simple interface for running arbitrary commands on the
/// Agent desktop. Output is displayed in a monospace scrollable area
/// with auto-scroll behavior.
class ScriptRunnerPanel extends StatefulWidget {
  const ScriptRunnerPanel({super.key});

  @override
  State<ScriptRunnerPanel> createState() => _ScriptRunnerPanelState();
}

class _ScriptRunnerPanelState extends State<ScriptRunnerPanel> {
  final _commandController = TextEditingController();
  final _cwdController = TextEditingController();
  final _scrollController = ScrollController();
  final _commandFocusNode = FocusNode();

  /// Output lines buffer (each entry is a line of text).
  final List<_OutputLine> _outputLines = [];

  /// Command history (most recent first).
  final List<String> _history = [];

  /// Current execution state.
  _ScriptState _state = _ScriptState.idle;

  /// Last exit code (null if no command has completed yet).
  int? _exitCode;

  /// Subscription to messageStream for script.* messages.
  StreamSubscription<WsMessage>? _messageSub;

  /// Whether auto-scroll is enabled (disabled when user scrolls up).
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Rebuild when command text changes so Play button enables/disables
    _commandController.addListener(_onCommandTextChanged);
    // Subscribe to script messages after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeToMessages();
    });
  }

  void _onCommandTextChanged() {
    // Trigger rebuild to update Play button enabled state
    setState(() {});
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _commandController.dispose();
    _cwdController.dispose();
    _scrollController.dispose();
    _commandFocusNode.dispose();
    super.dispose();
  }

  void _subscribeToMessages() {
    final ws = context.read<WebSocketService>();
    _messageSub = ws.messageStream
        .where((msg) =>
            msg.type == MessageType.scriptOutput ||
            msg.type == MessageType.scriptDone)
        .listen(_handleMessage);
  }

  void _handleMessage(WsMessage msg) {
    if (msg.type == MessageType.scriptOutput) {
      final payload = ScriptOutputPayload.fromJson(msg.payload);
      _appendOutput(payload.data, isStderr: payload.stream == 'stderr');
    } else if (msg.type == MessageType.scriptDone) {
      final payload = ScriptDonePayload.fromJson(msg.payload);
      _onDone(payload);
    }
  }

  void _appendOutput(String text, {bool isStderr = false}) {
    setState(() {
      // Split by newlines to maintain line-by-line structure
      final lines = text.split('\n');
      for (final line in lines) {
        if (line.isNotEmpty || lines.length == 1) {
          _outputLines.add(_OutputLine(text: line, isStderr: isStderr));
        }
      }
      // Trim oldest lines if buffer exceeds limit
      if (_outputLines.length > _kMaxOutputLines) {
        _outputLines.removeRange(0, _outputLines.length - _kMaxOutputLines);
      }
    });
    _scrollToBottom();
  }

  void _onDone(ScriptDonePayload payload) {
    _log.info('命令完成: exit_code=${payload.exitCode}, status=${payload.status}');
    setState(() {
      _exitCode = payload.exitCode;
      switch (payload.status) {
        case 'completed':
          _state = payload.exitCode == 0
              ? _ScriptState.completed
              : _ScriptState.failed;
        case 'killed':
          _state = _ScriptState.killed;
        case 'error':
          _state = _ScriptState.failed;
          if (payload.errorMessage != null) {
            _outputLines.add(_OutputLine(
              text: payload.errorMessage!,
              isStderr: true,
            ));
          }
        default:
          _state = _ScriptState.failed;
      }
    });
  }

  void _runCommand() {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;

    final cwd = _cwdController.text.trim();
    _log.info('执行命令: $command${cwd.isNotEmpty ? " (cwd=$cwd)" : ""}');

    // Add to history (avoid duplicates at the top)
    _history.remove(command);
    _history.insert(0, command);
    if (_history.length > _kMaxHistorySize) {
      _history.removeLast();
    }

    // Clear previous output and reset state
    setState(() {
      _outputLines.clear();
      _state = _ScriptState.running;
      _exitCode = null;
      _autoScroll = true;
    });

    // Send command to Agent
    context.read<TestPanelOperations>().runScript(
      command,
      cwd: cwd.isEmpty ? null : cwd,
    );
  }

  void _stopCommand() {
    _log.info('停止命令');
    context.read<TestPanelOperations>().stopScript();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Disable auto-scroll if user scrolled up more than 50px from bottom
    final atBottom = position.pixels >= position.maxScrollExtent - 50;
    if (_autoScroll && !atBottom) {
      _autoScroll = false;
    } else if (!_autoScroll && atBottom) {
      _autoScroll = true;
    }
  }

  void _scrollToBottom() {
    if (!_autoScroll || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _selectFromHistory() {
    if (_history.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _HistorySheet(
        history: _history,
        onSelect: (cmd) {
          Navigator.pop(ctx);
          _commandController.text = cmd;
          _commandController.selection = TextSelection.fromPosition(
            TextPosition(offset: cmd.length),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _state == _ScriptState.running;

    return Column(
      children: [
        // Command input area
        _buildCommandInput(context, isRunning),

        // Working directory input (collapsible)
        _buildCwdInput(context, isRunning),

        // Exit code chip (shown after completion)
        if (_exitCode != null) _buildExitCodeChip(context),

        // Output area
        Expanded(child: _buildOutputArea(context)),
      ],
    );
  }

  Widget _buildCommandInput(BuildContext context, bool isRunning) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);

    return Padding(
      padding: EdgeInsets.all(spacing.md),
      child: Row(
        children: [
          // History button
          if (_history.isNotEmpty)
            IconButton(
              icon: Icon(Icons.history, color: colors.onSurfaceVariant),
              onPressed: _selectFromHistory,
              tooltip: l.scriptHistoryTooltip,
            ),
          // Command text field
          Expanded(
            child: TextField(
              controller: _commandController,
              focusNode: _commandFocusNode,
              enabled: !isRunning,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: colors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: l.scriptCommandHint,
                hintStyle: TextStyle(color: colors.onSurfaceMuted),
                filled: true,
                fillColor: colors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: spacing.md,
                  vertical: spacing.sm,
                ),
                isDense: true,
              ),
              onSubmitted: (_) => _runCommand(),
              textInputAction: TextInputAction.go,
            ),
          ),
          SizedBox(width: spacing.sm),
          // Run / Stop button
          if (isRunning)
            IconButton(
              icon: Icon(Icons.stop_circle, color: colors.error),
              onPressed: _stopCommand,
              tooltip: l.scriptStopTooltip,
            )
          else
            IconButton(
              icon: Icon(Icons.play_circle_fill, color: colors.success),
              onPressed: _commandController.text.trim().isEmpty
                  ? null
                  : _runCommand,
              tooltip: l.scriptRunTooltip,
            ),
        ],
      ),
    );
  }

  Widget _buildCwdInput(BuildContext context, bool isRunning) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.sm),
      child: TextField(
        controller: _cwdController,
        enabled: !isRunning,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: colors.onSurface,
        ),
        decoration: InputDecoration(
          hintText: S.of(context).scriptCwdHint,
          hintStyle: TextStyle(color: colors.onSurfaceMuted, fontSize: 13),
          filled: true,
          fillColor: colors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          isDense: true,
          prefixIcon: Icon(Icons.folder_outlined,
              size: 18, color: colors.onSurfaceMuted),
        ),
      ),
    );
  }

  Widget _buildExitCodeChip(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final code = _exitCode!;
    final isSuccess = code == 0;
    final chipColor = isSuccess ? colors.success : colors.error;
    final label = _state == _ScriptState.killed
        ? S.of(context).scriptExitKilled
        : S.of(context).scriptExitCode(code);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.md),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          label: Text(
            label,
            style: TextStyle(color: chipColor, fontSize: 12),
          ),
          backgroundColor: chipColor.withValues(alpha: 0.1),
          side: BorderSide(color: chipColor.withValues(alpha: 0.3)),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _buildOutputArea(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    if (_outputLines.isEmpty && _state == _ScriptState.idle) {
      return Center(
        child: Text(
          S.of(context).scriptIdleHint,
          style: TextStyle(color: colors.onSurfaceMuted, fontSize: 14),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.all(spacing.sm),
          itemCount: _outputLines.length,
          itemBuilder: (context, index) {
            final line = _outputLines[index];
            return Text(
              line.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
                color: line.isStderr
                    ? colors.warning
                    : colors.onSurface,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A single line of output with metadata.
class _OutputLine {
  final String text;
  final bool isStderr;

  const _OutputLine({required this.text, this.isStderr = false});
}

/// Bottom sheet for command history selection.
class _HistorySheet extends StatelessWidget {
  final List<String> history;
  final ValueChanged<String> onSelect;

  const _HistorySheet({required this.history, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Text(
              S.of(context).scriptHistoryTitle,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: history.length,
              itemBuilder: (context, index) {
                final cmd = history[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    cmd,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: colors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onSelect(cmd),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
