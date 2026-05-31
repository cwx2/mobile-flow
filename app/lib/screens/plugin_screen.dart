/// plugin_screen.dart — Plugin management screen.
//
// Module: screens/
// Responsibility:
//   Displays installed plugin list with enable/disable, uninstall, and install support.
//   Communicates with the Agent via WebSocket plugin.* messages.
//
// Called by:
//   - SettingsScreen "Plugin Management" entry

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/loading_state.dart';
import '../models/protocol.dart';
import '../models/payloads/plugin_payloads.g.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/plugin_operations.dart';
import '../theme/theme_extensions.dart';
import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';

final _log = getLogger('PluginScreen');

/// Plugin management screen for installing, enabling, and removing plugins.
class PluginScreen extends StatefulWidget {
  const PluginScreen({super.key});

  @override
  State<PluginScreen> createState() => _PluginScreenState();
}

class _PluginScreenState extends State<PluginScreen> with LoadingStateMixin {
  List<Map<String, dynamic>> _plugins = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();

    _sub = ws.messageStream.listen((msg) {
      if (msg.type == MessageType.pluginListResult) {
        final p = PluginListResultPayload.fromJson(msg.payload);
        _log.fine('收到插件列表: ${p.plugins.length} 个');
        markDataReceived();
        setState(() {
          _plugins = p.plugins;
        });
      }
      if (msg.type == MessageType.pluginStateChanged) {
        // Refresh list after state change
        ws.pluginOps.requestPluginList();
      }
      if (msg.type == MessageType.pluginInstallResult) {
        final p = PluginInstallResultPayload.fromJson(msg.payload);
        if (mounted) {
          if (p.success) {
            _log.info('插件操作成功: ${p.message}');
            AppToast.show(context, p.message);
            ws.pluginOps.requestPluginList();
          } else {
            _log.warning('插件操作失败: ${p.message}');
            _showErrorDialog(p.message);
          }
        }
      }
    });

    ws.pluginOps.requestPluginList();
    startLoadingTimeout();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(S.of(context).pluginTitle, style: typography.titleMedium),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colors.onSurfaceVariant),
            onPressed: () {
              setState(() => resetLoading());
              startLoadingTimeout();
              context.read<PluginOperations>().requestPluginList();
            },
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(color: colors.primary),
            )
          : loadingError.isNotEmpty
              ? _buildErrorState(colors, typography)
              : _plugins.isEmpty
                  ? _buildEmptyState(colors, typography)
                  : _buildPluginList(colors, typography),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.primary,
        onPressed: _showInstallDialog,
        child: Icon(Icons.add, color: colors.onPrimary),
      ),
    );
  }

  Widget _buildEmptyState(dynamic colors, dynamic typography) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_off, size: 64, color: colors.onSurfaceMuted),
          SizedBox(height: context.spacing.md),
          Text(S.of(context).pluginEmpty, style: typography.titleMedium),
          SizedBox(height: context.spacing.xs),
          Text(
            S.of(context).pluginEmptyHint,
            style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginList(dynamic colors, dynamic typography) {
    return ListView.separated(
      padding: EdgeInsets.all(context.spacing.md),
      itemCount: _plugins.length,
      separatorBuilder: (_, __) => SizedBox(height: context.spacing.sm),
      itemBuilder: (_, i) => _buildPluginCard(_plugins[i], colors, typography),
    );
  }

  Widget _buildPluginCard(
      Map<String, dynamic> plugin, dynamic colors, dynamic typography) {
    final id = plugin['id'] as String? ?? '';
    final name = plugin['name'] as String? ?? id;
    final version = plugin['version'] as String? ?? '';
    final description = plugin['description'] as String? ?? '';
    final enabled = plugin['enabled'] == true;
    final status = plugin['status'] as String? ?? 'disabled';
    final error = plugin['error'] as String?;
    final capabilities = (plugin['capabilities'] as List?)?.cast<String>() ?? [];

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: _buildStatusDot(status, colors),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    name.isNotEmpty ? name : id,
                    style: typography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (version.isNotEmpty)
                  Text(
                    'v$version',
                    style: typography.labelSmall
                        .copyWith(color: colors.onSurfaceMuted),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (description.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      description,
                      style: typography.bodySmall
                          .copyWith(color: colors.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                SizedBox(height: 4),
                Row(
                  children: [
                    _buildStatusLabel(status, colors, typography),
                    if (capabilities.isNotEmpty) ...[
                      SizedBox(width: 8),
                      ...capabilities.map((c) => Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(c,
                                  style: typography.labelSmall
                                      .copyWith(color: colors.primary)),
                            ),
                          )),
                    ],
                  ],
                ),
              ],
            ),
            trailing: Switch(
              value: enabled,
              activeTrackColor: colors.primary,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                if (v) {
                  context.read<PluginOperations>().enablePlugin(id);
                } else {
                  context.read<PluginOperations>().disablePlugin(id);
                }
              },
            ),
          ),
          if (error != null)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, size: 16, color: colors.error),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(error,
                          style: typography.labelSmall
                              .copyWith(color: colors.error)),
                    ),
                  ],
                ),
              ),
            ),
          // Uninstall button
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _confirmUninstall(id, name),
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: colors.error),
                  label: Text(S.of(context).commonUninstall,
                      style: typography.labelSmall
                          .copyWith(color: colors.error)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot(String status, dynamic colors) {
    final color = switch (status) {
      'active' => colors.success as Color,
      'disabled' => colors.onSurfaceMuted as Color,
      'error' => colors.error as Color,
      'unavailable' => colors.warning as Color,
      _ => colors.onSurfaceMuted as Color,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildStatusLabel(
      String status, dynamic colors, dynamic typography) {
    final (label, color) = switch (status) {
      'active' => (S.of(context).pluginStatusActive, colors.success as Color),
      'disabled' => (S.of(context).pluginStatusDisabled, colors.onSurfaceMuted as Color),
      'error' => (S.of(context).pluginStatusError, colors.error as Color),
      'unavailable' => (S.of(context).pluginStatusUnavailable, colors.warning as Color),
      _ => (S.of(context).pluginStatusUnknown, colors.onSurfaceMuted as Color),
    };
    return Text(label,
        style: (typography.labelSmall as TextStyle).copyWith(color: color));
  }

  void _confirmUninstall(String id, String name) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radii.lg),
        ),
        title: Text(S.of(context).pluginUninstallTitle, style: context.typography.titleMedium),
        content: Text(S.of(context).pluginUninstallMessage(name),
            style: context.typography.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).commonCancel,
                style: TextStyle(color: colors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              context.read<PluginOperations>().uninstallPlugin(id);
              Navigator.pop(ctx);
            },
            child: Text(S.of(context).commonUninstall, style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }

  void _showInstallDialog() {
    final colors = context.colors;
    final urlCtrl = TextEditingController();
    String sourceType = 'git';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radii.lg),
          ),
          title: Text(S.of(context).pluginInstallTitle, style: context.typography.titleMedium),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source type selector
                Text(S.of(context).pluginInstallSource, style: context.typography.labelSmall),
                SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'git', label: Text('Git')),
                    ButtonSegment(value: 'npm', label: Text('npm')),
                    ButtonSegment(value: 'url', label: Text('URL')),
                  ],
                  selected: {sourceType},
                  onSelectionChanged: (v) {
                    setDialogState(() => sourceType = v.first);
                  },
                  style: ButtonStyle(
                    backgroundColor:
                        WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return colors.primary;
                      }
                      return colors.surface;
                    }),
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: urlCtrl,
                  style: context.typography.codeSmall,
                  decoration: InputDecoration(
                    hintText: switch (sourceType) {
                      'git' => 'https://github.com/user/plugin.git',
                      'npm' => '@scope/plugin-name',
                      'url' => 'https://example.com/plugin.zip',
                      _ => '',
                    },
                    hintStyle: context.typography.codeSmall
                        .copyWith(color: colors.onSurfaceMuted),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(context.radii.sm),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(context).commonCancel,
                  style: TextStyle(color: colors.onSurfaceVariant)),
            ),
            TextButton(
              onPressed: () {
                final url = urlCtrl.text.trim();
                if (url.isNotEmpty) {
                  context.read<PluginOperations>().installPlugin(
                        sourceType: sourceType,
                        sourceUrl: url,
                      );
                }
                Navigator.pop(ctx);
              },
              child:
                  Text(S.of(context).commonInstall, style: TextStyle(color: colors.secondary)),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radii.lg),
        ),
        title: Text(S.of(context).pluginInstallFailed, style: context.typography.titleMedium),
        content: Text(message, style: context.typography.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text(S.of(context).commonGotIt, style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(dynamic colors, dynamic typography) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: colors.error),
          SizedBox(height: context.spacing.md),
          Text(S.of(context).pluginLoadFailed, style: typography.titleMedium),
          SizedBox(height: context.spacing.xs),
          Text(
            loadingError,
            style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: context.spacing.lg),
          TextButton.icon(
            onPressed: () {
              setState(() => resetLoading());
              startLoadingTimeout();
              context.read<PluginOperations>().requestPluginList();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(S.of(context).commonRetry),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    disposeLoading();
    _sub?.cancel();
    super.dispose();
  }
}
