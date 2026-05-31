/// git_shell_tab.dart — Git Shell command input and history.
///
/// Module: widgets/
/// Responsibility:
///   Safe git command execution with history display, dangerous command
///   confirmation, and output formatting.

import 'package:flutter/material.dart';

import '../services/websocket_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';

/// Git Shell tab: command input field + scrollable history output.
///
/// Displays executed commands with their stdout/stderr output.
/// Dangerous commands (reset --hard, push --force) show a confirmation
/// prompt before execution.
class GitShellTab extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final TextEditingController controller;
  final WebSocketService ws;

  const GitShellTab({
    super.key,
    required this.history,
    required this.controller,
    required this.ws,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        // Command history output
        Expanded(
          child: history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.terminal,
                          size: 48, color: colors.onSurfaceMuted),
                      const SizedBox(height: 12),
                      Text('Git Shell',
                          style: TextStyle(
                              fontSize: 16, color: colors.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(S.of(context).gitShellHint,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 4),
                      Text(S.of(context).gitShellRestriction,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[700])),
                    ],
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  itemCount: history.length,
                  itemBuilder: (_, i) {
                    final item = history[history.length - 1 - i];
                    return _ShellHistoryItem(item: item, ws: ws);
                  },
                ),
        ),
        // Input field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text('git ',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: colors.secondary)),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'status, log, rebase ...',
                    hintStyle:
                        TextStyle(color: colors.onSurfaceMuted, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onSubmitted: (cmd) {
                    if (cmd.trim().isNotEmpty) {
                      ws.gitOps.execGitCommand('git ${cmd.trim()}');
                      controller.clear();
                    }
                  },
                ),
              ),
              GestureDetector(
                onTap: () {
                  final cmd = controller.text.trim();
                  if (cmd.isNotEmpty) {
                    ws.gitOps.execGitCommand('git $cmd');
                    controller.clear();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.send, size: 18, color: colors.secondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Single command history entry with output display.
class _ShellHistoryItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final WebSocketService ws;

  const _ShellHistoryItem({required this.item, required this.ws});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cmd = item['command'] as String? ?? '';
    final stdout = item['stdout'] as String? ?? '';
    final stderr = item['stderr'] as String? ?? '';
    final success = item['success'] == true;
    final blocked = item['blocked'] == true;
    final dangerous = item['dangerous'] == true;
    final reason = item['reason'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Command line
          Row(
            children: [
              Text('\$ ',
                  style: TextStyle(
                      color: success ? colors.secondary : colors.error,
                      fontFamily: 'monospace',
                      fontSize: 13)),
              Expanded(
                  child: Text(cmd,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13))),
            ],
          ),
          // Blocked / dangerous warning
          if (blocked || dangerous)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Row(
                children: [
                  Icon(dangerous ? Icons.warning_amber : Icons.block,
                      size: 14,
                      color: dangerous ? colors.warning : colors.error),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(reason,
                          style: TextStyle(
                              fontSize: 12,
                              color: dangerous
                                  ? colors.warning
                                  : colors.error))),
                  if (dangerous)
                    TextButton(
                      onPressed: () => ws.gitOps.execGitCommand(cmd, confirmed: true),
                      child: Text(S.of(context).gitShellConfirmExecute,
                          style: TextStyle(
                              fontSize: 11, color: colors.warning)),
                    ),
                ],
              ),
            ),
          // Stdout
          if (stdout.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: SelectableText(
                  stdout.length > 10000
                      ? '${stdout.substring(0, 5000)}\n\n... (${stdout.length} chars, middle collapsed) ...\n\n${stdout.substring(stdout.length - 2000)}'
                      : stdout,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: colors.onSurfaceVariant)),
            ),
          // Stderr
          if (stderr.isNotEmpty && !blocked)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(stderr,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: colors.error)),
            ),
          Divider(height: 8, color: colors.border),
        ],
      ),
    );
  }
}
