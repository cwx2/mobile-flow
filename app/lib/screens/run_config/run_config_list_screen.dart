/// run_config_list_screen.dart — Run Configuration list display.
///
/// Displays all configurations grouped by folder name, with type-specific
/// icons, running state indicators, and tap interactions for execution
/// control. Ungrouped configurations appear first.
///
/// Called by:
///   - TestPanelScreen or HomeScreen (as a tab/sub-panel)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/protocol.dart';
import '../../models/run_configuration.dart';
import '../../l10n/app_localizations.dart';
import '../../services/run_config_provider.dart';
import '../../services/websocket_service.dart';
import '../../services/ws_operations/run_config_operations.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/logger.dart';
import 'run_config_detail_screen.dart';
import 'run_config_output_view.dart';

final _log = getLogger('RunConfigList');

/// Run Configuration List Screen.
///
/// Shows all configurations grouped by [RunConfiguration.folderName].
/// Ungrouped configs (folderName == null) appear first. Each item
/// shows type icon, name, state indicator, and responds to taps.
///
/// Includes a "Quick Run" FAB that creates a temporary script
/// configuration from a user-entered command and immediately starts it.
class RunConfigListScreen extends StatefulWidget {
  const RunConfigListScreen({super.key});

  @override
  State<RunConfigListScreen> createState() => _RunConfigListScreenState();
}

class _RunConfigListScreenState extends State<RunConfigListScreen> {
  StreamSubscription<WsMessage>? _messageSub;
  bool _didRequestList = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeAndRequest();
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  void _subscribeAndRequest() {
    // Subscribe to run_config.* messages from the WebSocket stream
    final ws = context.read<WebSocketService>();
    final provider = context.read<RunConfigProvider>();

    _messageSub = ws.messageStream
        .where((msg) => msg.type.startsWith('run_config.'))
        .listen((msg) => provider.handleMessage(msg));

    // Request the configuration list from Agent
    if (!_didRequestList) {
      _didRequestList = true;
      context.read<RunConfigOperations>().requestList();
      context.read<RunConfigOperations>().requestStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RunConfigProvider>();
    final configs = provider.configurations;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: configs.isEmpty
          ? _EmptyState()
          : _buildList(context, configs),
      floatingActionButton: _QuickRunFab(),
    );
  }

  Widget _buildList(BuildContext context, List<RunConfiguration> configs) {
    // Group configurations by folder name
    final ungrouped = <RunConfiguration>[];
    final grouped = <String, List<RunConfiguration>>{};

    for (final config in configs) {
      if (config.folderName == null || config.folderName!.isEmpty) {
        ungrouped.add(config);
      } else {
        grouped.putIfAbsent(config.folderName!, () => []).add(config);
      }
    }

    return ListView(
      padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
      children: [
        // Ungrouped configurations first
        for (final config in ungrouped)
          _ConfigTile(config: config),

        // Grouped configurations with section headers
        for (final entry in grouped.entries) ...[
          _SectionHeader(title: entry.key),
          for (final config in entry.value)
            _ConfigTile(config: config),
        ],
      ],
    );
  }
}

/// Quick Run floating action button.
///
/// Shows a dialog with a command input field. On submit, creates a
/// temporary script configuration and immediately starts it, then
/// navigates to the output view.
class _QuickRunFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return FloatingActionButton.small(
      backgroundColor: colors.primary,
      foregroundColor: colors.surface,
      tooltip: S.of(context).runConfigQuickRun,
      onPressed: () => _showQuickRunDialog(context),
      child: const Icon(Icons.play_arrow),
    );
  }

  void _showQuickRunDialog(BuildContext context) {
    final controller = TextEditingController();
    final colors = context.colors;
    // Capture providers from the outer context (dialog context may not have them)
    final ops = context.read<RunConfigOperations>();
    final provider = context.read<RunConfigProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).runConfigQuickRun),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: S.of(context).runConfigQuickRunHint,
            border: const OutlineInputBorder(),
          ),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            color: colors.onSurface,
          ),
          onSubmitted: (_) => _submit(context, ops, provider, controller),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).runConfigCancel),
          ),
          FilledButton(
            onPressed: () => _submit(context, ops, provider, controller),
            child: Text(S.of(context).runConfigRun),
          ),
        ],
      ),
    );
  }

  void _submit(
    BuildContext outerContext,
    RunConfigOperations ops,
    RunConfigProvider provider,
    TextEditingController controller,
  ) {
    final command = controller.text.trim();
    if (command.isEmpty) return;

    Navigator.of(outerContext, rootNavigator: true).pop(); // Close dialog

    _log.info('Quick Run: $command');

    // Create a temporary script configuration and start it.
    // The provider will receive the 'created' message with the new config ID.
    // We listen for the next created config to navigate to its output.
    ops.create('script', initialFields: {
      'command': command,
      'is_temporary': true,
      'name': command.length > 30 ? '${command.substring(0, 30)}...' : command,
    });

    // Listen for the created config to start it and navigate
    void listener() {
      final configs = provider.configurations;
      if (configs.isEmpty) return;

      // Find the most recently added temporary config matching our command
      final created = configs.lastWhere(
        (c) => c.isTemporary && c.command == command,
        orElse: () => configs.last,
      );

      provider.removeListener(listener);

      // Start execution
      ops.start(created.id);

      // Navigate to output view
      if (outerContext.mounted) {
        Navigator.of(outerContext).push(
          MaterialPageRoute(
            builder: (_) => RunConfigOutputView(configId: created.id),
          ),
        );
      }
    }

    provider.addListener(listener);

    // Safety timeout: remove listener if Agent never responds (10s)
    Future.delayed(const Duration(seconds: 10), () {
      provider.removeListener(listener);
    });
  }
}

/// Empty state shown when no configurations exist.
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l = S.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 48,
              color: colors.onSurfaceMuted,
            ),
            SizedBox(height: context.spacing.md),
            Text(
              l.runConfigNoConfigs,
              style: context.typography.titleMedium.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
            SizedBox(height: context.spacing.sm),
            Text(
              l.runConfigNoConfigsDesc,
              textAlign: TextAlign.center,
              style: context.typography.bodySmall.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section header for grouped configurations.
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.md, spacing.md, spacing.md, spacing.xs),
      child: Text(
        title,
        style: context.typography.labelSmall.copyWith(
          color: colors.onSurfaceMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A single configuration list tile with state indicators.
class _ConfigTile extends StatelessWidget {
  final RunConfiguration config;

  const _ConfigTile({required this.config});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RunConfigProvider>();
    final colors = context.colors;
    final spacing = context.spacing;
    final state = provider.getState(config.id);
    final isSelected = provider.selectedId == config.id;
    final isRunning = state == RunConfigState.running;
    final isActive = state != RunConfigState.idle &&
        state != RunConfigState.stopped;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? colors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isSelected
            ? Border.all(color: colors.primary.withValues(alpha: 0.3))
            : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: spacing.md),
        leading: _buildLeadingIcon(context, state),
        title: Text(
          config.name,
          style: context.typography.bodyMedium.copyWith(
            color: colors.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _stateLabel(state, context),
          style: context.typography.labelSmall.copyWith(
            color: _stateColor(state, context),
          ),
        ),
        trailing: isActive
            ? _RunningIndicator(color: _stateColor(state, context))
            : null,
        onTap: () => _onTap(context, state, isRunning),
      ),
    );
  }

  /// Build the leading icon with type-specific icon.
  Widget _buildLeadingIcon(BuildContext context, RunConfigState state) {
    final colors = context.colors;
    final icon = _typeIcon(config.type);
    final iconColor = state == RunConfigState.running
        ? colors.success
        : colors.onSurfaceVariant;

    return Icon(icon, size: 22, color: iconColor);
  }

  /// Get the icon for a configuration type.
  IconData _typeIcon(RunConfigType type) => switch (type) {
        RunConfigType.preview => Icons.language,
        RunConfigType.script => Icons.terminal,
        RunConfigType.test => Icons.check_circle_outline,
        RunConfigType.custom => Icons.settings,
      };

  /// Get a human-readable label for the current state.
  String _stateLabel(RunConfigState state, BuildContext context) {
    final l = S.of(context);
    return switch (state) {
      RunConfigState.idle => l.runConfigStateIdle,
      RunConfigState.beforeRun => l.runConfigStateBeforeRun,
      RunConfigState.starting => l.runConfigStateStarting,
      RunConfigState.running => l.runConfigStateRunning,
      RunConfigState.stopping => l.runConfigStateStopping,
      RunConfigState.stopped => l.runConfigStateStopped,
    };
  }

  /// Get the color for a state indicator.
  Color _stateColor(RunConfigState state, BuildContext context) {
    final colors = context.colors;
    return switch (state) {
      RunConfigState.idle => colors.onSurfaceMuted,
      RunConfigState.beforeRun => colors.warning,
      RunConfigState.starting => colors.warning,
      RunConfigState.running => colors.success,
      RunConfigState.stopping => colors.warning,
      RunConfigState.stopped => colors.onSurfaceMuted,
    };
  }

  /// Handle tap on a configuration tile.
  void _onTap(BuildContext context, RunConfigState state, bool isRunning) {
    // Always navigate to detail screen regardless of state.
    // Detail screen shows Run/Stop buttons based on current state.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RunConfigDetailScreen(configId: config.id),
      ),
    );
  }

  /// Show bottom sheet with options for an active configuration.
  void _showActiveConfigSheet(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.md),
                child: Text(
                  config.name,
                  style: context.typography.titleSmall.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
              SizedBox(height: spacing.md),
              // View Output
              ListTile(
                leading: Icon(Icons.terminal, color: colors.onSurfaceVariant),
                title: Text(l.runConfigViewOutput),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RunConfigOutputView(configId: config.id),
                    ),
                  );
                },
              ),
              // Stop
              ListTile(
                leading: Icon(Icons.stop_circle, color: colors.error),
                title: Text(l.runConfigStop),
                onTap: () {
                  Navigator.pop(ctx);
                  _log.info('停止配置: ${config.name}');
                  context.read<RunConfigOperations>().stop(config.id);
                },
              ),
              // Restart
              ListTile(
                leading: Icon(Icons.refresh, color: colors.warning),
                title: Text(l.runConfigRestart),
                onTap: () {
                  Navigator.pop(ctx);
                  _log.info('重启配置: ${config.name}');
                  context.read<RunConfigOperations>().restart(config.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small animated dot indicating a running process.
class _RunningIndicator extends StatefulWidget {
  final Color color;

  const _RunningIndicator({required this.color});

  @override
  State<_RunningIndicator> createState() => _RunningIndicatorState();
}

class _RunningIndicatorState extends State<_RunningIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(
            alpha: 0.4 + (_controller.value * 0.6),
          ),
        ),
      ),
    );
  }
}
