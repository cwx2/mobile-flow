/// Slash command popup menu.
///
/// Modeled after IDE chat.ts renderSlashMenu. Shows a categorized,
/// filterable command list when the user types / in the input field.
///
/// Used by:
///   - ChatInputBar when detecting / prefix input

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';

/// Slash command category.
enum SlashCommandCategory { session, tools, config, cli }

/// CLI-advertised command received from the Agent.
///
/// Represents a command advertised by an AI CLI adapter via ACP
/// AvailableCommandsUpdate events. Stored in ChatStateMixin and
/// merged into the slash command menu.
class CliCommand {
  final String name;
  final String description;

  const CliCommand({required this.name, required this.description});
}

/// Slash command definition.
class SlashCommand {
  final String name;
  final String description;
  final IconData icon;
  final SlashCommandCategory category;

  /// Whether to execute immediately (no additional args needed).
  final bool immediate;

  /// Argument hint (e.g. "<session_id>").
  final String? args;

  const SlashCommand({
    required this.name,
    required this.description,
    required this.icon,
    this.category = SlashCommandCategory.session,
    this.immediate = false,
    this.args,
  });
}

/// Built-in slash commands (modeled after IDE's SLASH_COMMANDS).
List<SlashCommand> getBuiltinSlashCommands(BuildContext context) {
  final s = S.of(context);
  return [
  // Session commands
  SlashCommand(
    name: 'new',
    description: s.slashCmdNew,
    icon: Icons.add_comment_outlined,
    category: SlashCommandCategory.session,
    immediate: true,
  ),
  SlashCommand(
    name: 'clear',
    description: s.slashCmdClear,
    icon: Icons.delete_outline,
    category: SlashCommandCategory.session,
    immediate: true,
  ),
  SlashCommand(
    name: 'history',
    description: s.slashCmdHistory,
    icon: Icons.history,
    category: SlashCommandCategory.session,
    immediate: true,
  ),

  // Tool commands
  SlashCommand(
    name: 'files',
    description: s.slashCmdFiles,
    icon: Icons.folder_outlined,
    category: SlashCommandCategory.tools,
    immediate: true,
  ),
  SlashCommand(
    name: 'terminal',
    description: s.slashCmdTerminal,
    icon: Icons.terminal,
    category: SlashCommandCategory.tools,
    immediate: true,
  ),
  SlashCommand(
    name: 'diff',
    description: s.slashCmdDiff,
    icon: Icons.difference_outlined,
    category: SlashCommandCategory.tools,
    immediate: true,
  ),

  // Config commands
  SlashCommand(
    name: 'model',
    description: s.slashCmdModel,
    icon: Icons.psychology_outlined,
    category: SlashCommandCategory.config,
    args: '<model_name>',
  ),
  SlashCommand(
    name: 'project',
    description: s.slashCmdProject,
    icon: Icons.folder_special_outlined,
    category: SlashCommandCategory.config,
    immediate: true,
  ),
];
}

/// Category labels.
Map<SlashCommandCategory, String> getCategoryLabels(BuildContext context) {
  final s = S.of(context);
  return {
  SlashCommandCategory.session: s.slashCategorySession,
  SlashCommandCategory.tools: s.slashCategoryTools,
  SlashCommandCategory.config: s.slashCategoryConfig,
  SlashCommandCategory.cli: s.slashCategoryCli,
};
}

//// slash_command_menu.dart — Slash command popup menu widget.
///
/// Pops up above the input field, showing matching commands.
/// Modeled after IDE's slash-menu style: grouped display, highlighted
/// selection, and keyboard shortcut hints at the bottom.
class SlashCommandMenu extends StatelessWidget {
  /// Current filter text (the part after /).
  final String filter;

  /// Command selection callback.
  final void Function(SlashCommand cmd) onSelect;

  /// Menu dismiss callback.
  final VoidCallback onDismiss;

  /// CLI-advertised commands from the active CLI adapter.
  final List<CliCommand> cliCommands;

  const SlashCommandMenu({
    super.key,
    required this.filter,
    required this.onSelect,
    required this.onDismiss,
    this.cliCommands = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Combine built-in commands with CLI-advertised commands
    final allCommands = <SlashCommand>[
      ...getBuiltinSlashCommands(context),
      ...cliCommands.map((c) => SlashCommand(
            name: c.name,
            description: c.description,
            icon: Icons.smart_toy_outlined,
            category: SlashCommandCategory.cli,
            immediate: true,
          )),
    ];

    // Filter matching commands
    final filtered = allCommands.where((cmd) {
      if (filter.isEmpty) return true;
      return cmd.name.toLowerCase().startsWith(filter.toLowerCase());
    }).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    // Group by category
    final grouped = <SlashCommandCategory, List<SlashCommand>>{};
    for (final cmd in filtered) {
      grouped.putIfAbsent(cmd.category, () => []).add(cmd);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
      child: Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        border: Border(
          top: BorderSide(color: colors.border),
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final category in grouped.keys) ...[
            // Category title
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                getCategoryLabels(context)[category] ?? '',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // Command list
            ...grouped[category]!.map((cmd) => _buildCommandItem(context, cmd)),
          ],
          // Bottom hint
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              S.of(context).slashCmdHint,
              style: TextStyle(fontSize: 10, color: colors.onSurfaceMuted),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildCommandItem(BuildContext context, SlashCommand cmd) {
    final colors = context.colors;
    return InkWell(
      onTap: () => onSelect(cmd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(cmd.icon, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '/${cmd.name}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
            ),
            if (cmd.args != null) ...[
              const SizedBox(width: 4),
              Text(
                cmd.args!,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceMuted),
              ),
            ],
            const Spacer(),
            Text(
              cmd.description,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            if (cmd.immediate)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  S.of(context).slashCmdImmediate,
                  style: TextStyle(fontSize: 9, color: colors.secondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
