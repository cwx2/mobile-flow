/// agent_detail_screen.dart — Agent detail and configuration page.
///
/// Module: screens/
/// Responsibility:
///   Displays full ACP capabilities, available modes, and config options
///   for a single AI CLI agent. Read-only for capabilities; editable for
///   config options and mode when the agent is the active CLI.
///   Provides a "Use this Agent" action to switch the active CLI.
///
/// Called by:
///   - SettingsScreen CLI list tile (tap on an installed agent)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../components/app_toast.dart';
import '../components/glass_card.dart';
import '../l10n/app_localizations.dart';
import '../models/protocol.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';
import '../widgets/input_bar/config_panel.dart';

final _log = getLogger('AgentDetail');

/// Agent detail screen showing ACP capabilities, modes, and config options.
class AgentDetailScreen extends StatelessWidget {
  /// Raw adapter map from cli.list.result payload.
  final Map<String, dynamic> adapter;

  const AgentDetailScreen({super.key, required this.adapter});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    final name = adapter['name'] as String? ?? '';
    final displayName = adapter['display_name'] as String? ?? name;
    final isSelected = name == ws.defaultCli;
    _log.fine('打开 Agent 详情: $displayName, active=$isSelected');

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background.withValues(alpha: 0.9),
        toolbarHeight: 44,
        title: Text(displayName, style: typography.headlineMedium),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: spacing.md),
        children: [
          // Agent info header
          _buildInfoHeader(context, ws, isSelected),

          SizedBox(height: spacing.lg),

          // ACP capabilities
          _sectionTitle(context, S.of(context).settingsAgentCapabilities,
              Icons.verified_outlined, colors.secondary),
          SizedBox(height: spacing.xs),
          _buildCapabilitiesChips(context),

          SizedBox(height: spacing.lg),

          // Modes section
          _buildModesSection(context, ws, isSelected),

          // Config section
          _buildConfigSection(context, ws, isSelected),

          // Action button
          SizedBox(height: spacing.lg),
          _buildActionButton(context, ws, name, displayName, isSelected),

          SizedBox(height: spacing.xxl),
        ],
      ),
    );
  }

  // ── Info header ──

  Widget _buildInfoHeader(
      BuildContext context, WebSocketService ws, bool isSelected) {
    final colors = context.colors;
    final spacing = context.spacing;

    final version = adapter['version'] as String?;
    final source = adapter['source'] as String? ?? 'builtin';
    final executionEnv = adapter['execution_env'] as String? ?? 'native';

    return Padding(
      padding: EdgeInsets.only(top: spacing.sm),
      child: Wrap(
        spacing: spacing.xs,
        runSpacing: spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (version != null && version.isNotEmpty)
            _infoPill(context, 'v$version', colors.onSurfaceMuted),
          _infoPill(
              context, _sourceLabel(context, source), colors.secondary),
          if (executionEnv == 'wsl')
            _infoPill(context, 'WSL', colors.primary),
          // Status badge
          _statusBadge(context, isSelected),
        ],
      ),
    );
  }

  Widget _statusBadge(BuildContext context, bool isSelected) {
    final colors = context.colors;
    final tint = isSelected ? colors.success : colors.onSurfaceMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tint.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
          ),
          const SizedBox(width: 4),
          Text(
            isSelected
                ? S.of(context).settingsAgentActive
                : S.of(context).settingsAgentInactive,
            style: TextStyle(
                fontSize: 10, color: tint, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _sourceLabel(BuildContext context, String source) {
    switch (source) {
      case 'custom':
        return S.of(context).settingsAgentSourceCustom;
      case 'plugin':
        return S.of(context).settingsAgentSourcePlugin;
      default:
        return S.of(context).settingsAgentSourceBuiltin;
    }
  }

  // ── Section title ──

  Widget _sectionTitle(
      BuildContext context, String title, IconData icon, Color tint) {
    final colors = context.colors;
    final typography = context.typography;
    return Padding(
      padding: EdgeInsets.only(left: context.spacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 15, color: tint),
          SizedBox(width: context.spacing.xs),
          Text(
            title,
            style: typography.labelLarge.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── ACP capabilities — chip grid ──

  Widget _buildCapabilitiesChips(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    final allCaps = <_CapEntry>[
      _CapEntry(S.of(context).settingsCapSessionLoad,
          adapter['supports_session_load'] == true, Icons.restore),
      _CapEntry(S.of(context).settingsCapSessionList,
          adapter['supports_session_list'] == true, Icons.list_alt),
      _CapEntry(S.of(context).settingsCapSessionClose,
          adapter['supports_session_close'] == true, Icons.close),
      _CapEntry(S.of(context).settingsCapSessionFork,
          adapter['supports_session_fork'] == true, Icons.call_split),
      _CapEntry(S.of(context).settingsCapSessionResume,
          adapter['supports_session_resume'] == true, Icons.play_arrow),
      _CapEntry(S.of(context).settingsCapImage,
          adapter['supports_image'] == true, Icons.image_outlined),
      _CapEntry(S.of(context).settingsCapAudio,
          adapter['supports_audio'] == true, Icons.mic_outlined),
      _CapEntry(S.of(context).settingsCapEmbeddedContext,
          adapter['supports_embedded_context'] == true, Icons.data_object),
      _CapEntry(S.of(context).settingsCapMcpHttp,
          adapter['supports_mcp_http'] == true, Icons.http),
      _CapEntry(S.of(context).settingsCapMcpSse,
          adapter['supports_mcp_sse'] == true, Icons.stream),
    ];

    final hasAnyCapability = allCaps.any((c) => c.enabled);

    // No real capability data — show hint instead of misleading grey chips
    if (!hasAnyCapability) {
      return _buildHintCard(
          context, S.of(context).settingsAgentSwitchToViewCaps);
    }

    final supported = allCaps.where((c) => c.enabled).toList();
    final unsupported = allCaps.where((c) => !c.enabled).toList();

    return GlassCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (supported.isNotEmpty)
            Wrap(
              spacing: spacing.xs,
              runSpacing: spacing.xs,
              children: supported
                  .map((c) => _capChip(context, c, colors.success))
                  .toList(),
            ),
          if (supported.isNotEmpty && unsupported.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: spacing.sm),
              child: Divider(height: 1, color: colors.borderSubtle),
            ),
          if (unsupported.isNotEmpty)
            Wrap(
              spacing: spacing.xs,
              runSpacing: spacing.xs,
              children: unsupported
                  .map((c) => _capChip(context, c, colors.onSurfaceMuted))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _capChip(BuildContext context, _CapEntry cap, Color tint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: cap.enabled ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(context.radii.sm),
        border: Border.all(
          color: tint.withValues(alpha: cap.enabled ? 0.25 : 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(cap.icon,
              size: 13,
              color: tint.withValues(alpha: cap.enabled ? 1.0 : 0.4)),
          const SizedBox(width: 5),
          Text(
            cap.label,
            style: TextStyle(
              fontSize: 11,
              color: tint.withValues(alpha: cap.enabled ? 1.0 : 0.4),
              fontWeight: cap.enabled ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // ── Modes section ──

  Widget _buildModesSection(
      BuildContext context, WebSocketService ws, bool isSelected) {
    final colors = context.colors;
    final spacing = context.spacing;

    // Active agent with modes → show editable mode list
    if (isSelected && ws.cliCapabilities.availableModes.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, S.of(context).settingsAgentModes,
              Icons.tune_outlined, colors.warning),
          SizedBox(height: spacing.xs),
          _buildModesCard(context, ws),
          SizedBox(height: spacing.lg),
        ],
      );
    }

    // Not active → show hint to switch first
    if (!isSelected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, S.of(context).settingsAgentModes,
              Icons.tune_outlined, colors.warning),
          SizedBox(height: spacing.xs),
          _buildHintCard(context, S.of(context).settingsAgentSwitchToConfig),
          SizedBox(height: spacing.lg),
        ],
      );
    }

    // Active but no modes → nothing to show
    return const SizedBox.shrink();
  }

  Widget _buildModesCard(BuildContext context, WebSocketService ws) {
    final colors = context.colors;
    final typography = context.typography;
    final modes = ws.cliCapabilities.availableModes;
    final currentMode = ws.currentMode;

    return GlassCard(
      padding: EdgeInsets.symmetric(
          vertical: context.spacing.xs, horizontal: context.spacing.xs),
      child: Column(
        children: [
          for (int i = 0; i < modes.length; i++) ...[
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.radii.md),
              ),
              leading: Icon(
                currentMode == (modes[i]['id'] as String? ?? '')
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: colors.primary,
                size: 20,
              ),
              title: Text(
                modes[i]['name'] as String? ?? modes[i]['id'] as String? ?? '',
                style: typography.bodyMedium,
              ),
              subtitle: modes[i]['description'] != null
                  ? Text(
                      modes[i]['description'] as String,
                      style: typography.labelSmall
                          .copyWith(color: colors.onSurfaceMuted),
                    )
                  : null,
              onTap: () {
                final modeId = modes[i]['id'] as String? ?? '';
                final modeName = modes[i]['name'] as String? ?? modeId;
                HapticFeedback.selectionClick();
                ws.cliOps.setMode(modeId);
                AppToast.show(
                    context, S.of(context).settingsAgentModeSwitched(modeName));
              },
            ),
            if (i < modes.length - 1)
              Divider(height: 1, color: colors.borderSubtle, indent: 52),
          ],
        ],
      ),
    );
  }

  // ── Config section ──

  Widget _buildConfigSection(
      BuildContext context, WebSocketService ws, bool isSelected) {
    final colors = context.colors;
    final spacing = context.spacing;

    // Only show config options when this agent is active and has options.
    // Non-active agents have no session, so no config data is available.
    // The modes section already shows a "switch to view" hint for non-active
    // agents, so we don't duplicate it here.
    if (!isSelected || ws.configOptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, S.of(context).settingsAgentConfig,
            Icons.settings_outlined, colors.primary),
        SizedBox(height: spacing.xs),
        _buildConfigCard(context, ws),
        SizedBox(height: spacing.sm),
      ],
    );
  }

  Widget _buildConfigCard(BuildContext context, WebSocketService ws) {
    final colors = context.colors;
    final typography = context.typography;
    final opts = ws.configOptions;

    return GlassCard(
      padding: EdgeInsets.symmetric(
          vertical: context.spacing.xs, horizontal: context.spacing.xs),
      child: Column(
        children: [
          for (int i = 0; i < opts.length; i++) ...[
            if (opts[i].type == 'boolean')
              SwitchListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
                title: Text(opts[i].name, style: typography.bodyMedium),
                subtitle: opts[i].description != null
                    ? Text(opts[i].description!,
                        style: typography.labelSmall
                            .copyWith(color: colors.onSurfaceMuted))
                    : null,
                value: opts[i].currentValue == true,
                activeTrackColor: colors.primary,
                onChanged: (v) {
                  ws.cliOps.setConfigOption(opts[i].id, v);
                  AppToast.show(
                      context, '${opts[i].name}: ${v ? "ON" : "OFF"}');
                },
              )
            else
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
                title: Text(opts[i].name, style: typography.bodyMedium),
                subtitle: opts[i].description != null
                    ? Text(opts[i].description!,
                        style: typography.labelSmall
                            .copyWith(color: colors.onSurfaceMuted))
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        _currentOptionName(opts[i]),
                        style: typography.labelSmall
                            .copyWith(color: colors.primary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 16, color: colors.onSurfaceMuted),
                  ],
                ),
                onTap: () => showSelectOptionPicker(context, option: opts[i], ws: ws),
              ),
            if (i < opts.length - 1)
              Divider(height: 1, color: colors.borderSubtle, indent: 16),
          ],
        ],
      ),
    );
  }

  /// Hint card shown when the agent is not active.
  Widget _buildHintCard(BuildContext context, String message) {
    final colors = context.colors;
    final typography = context.typography;
    return GlassCard(
      padding: EdgeInsets.all(context.spacing.md),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: colors.onSurfaceMuted),
          SizedBox(width: context.spacing.sm),
          Expanded(
            child: Text(
              message,
              style: typography.bodySmall
                  .copyWith(color: colors.onSurfaceMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action button ──

  /// Resolve the display name for the current value of a select config option.
  String _currentOptionName(ConfigOption opt) {
    return opt.options
            ?.where((o) => o.value == opt.currentValue)
            .map((o) => o.name)
            .firstOrNull ??
        (opt.currentValue?.toString() ?? '');
  }

  Widget _buildActionButton(
    BuildContext context,
    WebSocketService ws,
    String name,
    String displayName,
    bool isSelected,
  ) {
    final colors = context.colors;
    final typography = context.typography;

    if (isSelected) {
      return Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.radii.lg),
          border: Border.all(color: colors.success.withValues(alpha: 0.25)),
          color: colors.success.withValues(alpha: 0.06),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 18, color: colors.success),
            const SizedBox(width: 8),
            Text(
              S.of(context).settingsAgentCurrentlyUsing,
              style: typography.bodyMedium.copyWith(color: colors.success),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: () {
          HapticFeedback.selectionClick();
          ws.cliOps.switchCLI(name);
          _log.info('切换 Agent: $name');
          AppToast.show(
              context, S.of(context).settingsSwitchedTo(displayName));
          Navigator.pop(context);
        },
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: Text(S.of(context).settingsAgentUseThis),
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radii.lg),
          ),
        ),
      ),
    );
  }
}

/// Internal capability entry for chip display.
class _CapEntry {
  final String label;
  final bool enabled;
  final IconData icon;
  const _CapEntry(this.label, this.enabled, this.icon);
}
