/// run_config_detail_screen.dart — Run Configuration detail/edit screen.
///
/// Displays an editable form for a single run configuration with fields
/// for name, command, working directory, and type-specific settings
/// (preview URL, host header). Provides action buttons for run, stop,
/// and delete operations. Auto-saves field changes on editing complete.
///
/// Called by:
///   - RunConfigListScreen (on tap for idle/stopped configs)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/run_configuration.dart';
import '../../services/run_config_provider.dart';
import '../../services/ws_operations/run_config_operations.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/logger.dart';
import 'run_config_output_view.dart';

final _log = getLogger('RunConfigDetail');

/// Detail/edit screen for a single run configuration.
///
/// Shows editable fields for the configuration properties and action
/// buttons for execution control. Watches [RunConfigProvider] for
/// live state updates (running/stopped indicators).
class RunConfigDetailScreen extends StatefulWidget {
  /// The configuration ID to display and edit.
  final String configId;

  const RunConfigDetailScreen({super.key, required this.configId});

  @override
  State<RunConfigDetailScreen> createState() => _RunConfigDetailScreenState();
}

class _RunConfigDetailScreenState extends State<RunConfigDetailScreen> {
  late TextEditingController _nameController;
  late TextEditingController _commandController;
  late TextEditingController _workDirController;
  late TextEditingController _previewUrlController;
  late TextEditingController _hostHeaderController;

  /// Debounce timer for auto-save on field changes.
  Timer? _saveDebounce;

  /// Track whether controllers have been initialized from config data.
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _commandController = TextEditingController();
    _workDirController = TextEditingController();
    _previewUrlController = TextEditingController();
    _hostHeaderController = TextEditingController();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _nameController.dispose();
    _commandController.dispose();
    _workDirController.dispose();
    _previewUrlController.dispose();
    _hostHeaderController.dispose();
    super.dispose();
  }

  /// Initialize controllers from the configuration data (once).
  void _initControllers(RunConfiguration config) {
    if (_initialized) return;
    _initialized = true;
    _nameController.text = config.name;
    _commandController.text = config.command;
    _workDirController.text = config.workingDirectory ?? '';
    _previewUrlController.text = config.preview?.url ?? '';
    _hostHeaderController.text = config.preview?.hostHeader ?? '';
  }

  /// Save a field update to the Agent with debouncing.
  void _saveField(String fieldName, String value) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _log.fine('保存字段: $fieldName');
      final ops = context.read<RunConfigOperations>();

      // Map field names to the update payload structure
      final Map<String, dynamic> updates = switch (fieldName) {
        'name' => {'name': value},
        'command' => {'command': value},
        'working_directory' => {'working_directory': value.isEmpty ? null : value},
        'preview_url' => {'preview': {'url': value}},
        'host_header' => {'preview': {'host_header': value.isEmpty ? null : value}},
        _ => {},
      };

      if (updates.isNotEmpty) {
        ops.update(widget.configId, updates);
      }
    });
  }

  /// Start execution and navigate to output view.
  void _startExecution() {
    _log.info('启动配置: ${widget.configId}');
    context.read<RunConfigOperations>().start(widget.configId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RunConfigOutputView(configId: widget.configId),
      ),
    );
  }

  /// Stop execution.
  void _stopExecution() {
    _log.info('停止配置: ${widget.configId}');
    context.read<RunConfigOperations>().stop(widget.configId);
  }

  /// Delete configuration with confirmation dialog.
  void _deleteConfig(RunConfiguration config) {
    final l = S.of(context);
    final colors = context.colors;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.runConfigDeleteConfirmTitle),
        content: Text(l.runConfigDeleteConfirmBody(config.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _log.info('删除配置: ${config.name}');
              context.read<RunConfigOperations>().delete(widget.configId);
              // Pop back to list after deletion
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: colors.error),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RunConfigProvider>();
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);

    // Find the configuration
    final config = provider.configurations
        .where((c) => c.id == widget.configId)
        .firstOrNull;

    if (config == null) {
      // Config was deleted or not found — pop back
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    // Initialize controllers from config data on first build
    _initControllers(config);

    final state = provider.getState(widget.configId);
    final isRunning = state == RunConfigState.running ||
        state == RunConfigState.beforeRun ||
        state == RunConfigState.starting;
    final isPreview = config.type == RunConfigType.preview;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(l.runConfigDetailTitle),
        backgroundColor: colors.surfaceElevated,
      ),
      body: Column(
        children: [
          // State indicator
          _buildStateIndicator(context, state),

          // Form fields
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildField(
                    l.runConfigNameLabel,
                    _nameController,
                    'name',
                  ),
                  _buildField(
                    l.runConfigCommandLabel,
                    _commandController,
                    'command',
                    monospace: true,
                  ),
                  _buildField(
                    l.runConfigWorkDirLabel,
                    _workDirController,
                    'working_directory',
                    monospace: true,
                  ),
                  if (isPreview) ...[
                    _buildField(
                      l.runConfigPreviewUrlLabel,
                      _previewUrlController,
                      'preview_url',
                    ),
                    _buildField(
                      l.runConfigHostHeaderLabel,
                      _hostHeaderController,
                      'host_header',
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Action buttons
          _buildActionBar(context, config, state, isRunning),
        ],
      ),
    );
  }

  /// Build the state indicator bar at the top.
  Widget _buildStateIndicator(BuildContext context, RunConfigState state) {
    if (state == RunConfigState.idle) return const SizedBox.shrink();

    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);

    final color = switch (state) {
      RunConfigState.idle => colors.onSurfaceMuted,
      RunConfigState.beforeRun => colors.warning,
      RunConfigState.starting => colors.warning,
      RunConfigState.running => colors.success,
      RunConfigState.stopping => colors.warning,
      RunConfigState.stopped => colors.onSurfaceMuted,
    };

    final label = switch (state) {
      RunConfigState.idle => l.runConfigStateIdle,
      RunConfigState.beforeRun => l.runConfigStateBeforeRun,
      RunConfigState.starting => l.runConfigStateStarting,
      RunConfigState.running => l.runConfigStateRunning,
      RunConfigState.stopping => l.runConfigStateStopping,
      RunConfigState.stopped => l.runConfigStateStopped,
    };

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.xs,
      ),
      color: color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          SizedBox(width: spacing.sm),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build a labeled text field for a configuration property.
  Widget _buildField(
    String label,
    TextEditingController controller,
    String fieldName, {
    bool monospace = false,
  }) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurfaceMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            style: TextStyle(
              fontSize: 14,
              fontFamily: monospace ? 'monospace' : null,
              color: colors.onSurface,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: colors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
            onChanged: (value) => _saveField(fieldName, value),
          ),
        ],
      ),
    );
  }

  /// Build the action button bar at the bottom.
  Widget _buildActionBar(
    BuildContext context,
    RunConfiguration config,
    RunConfigState state,
    bool isRunning,
  ) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(
          top: BorderSide(color: colors.surfaceVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Run or Stop button
            if (isRunning) ...[
              // View output/preview button
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RunConfigOutputView(
                            configId: widget.configId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.visibility),
                    label: Text(l.runConfigPreviewTab),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              // Stop button
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _stopExecution,
                  icon: const Icon(Icons.stop),
                  label: Text(l.runConfigStop),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.warning,
                    side: BorderSide(color: colors.warning.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _startExecution,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l.runConfigRun),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],

            SizedBox(width: spacing.sm),

            // Delete button
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _deleteConfig(config),
                icon: const Icon(Icons.delete_outline),
                label: Text(l.commonDelete),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.error,
                  side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
