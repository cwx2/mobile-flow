/// settings_screen.dart — Settings screen.
//
// Module: screens/
// Responsibility:
//   Project management, connection status, CLI tool list, theme toggle, about info.
//   Uses design system tokens + SectionHeader + StatusDot + GlassCard.
//   Grouped card layout following iOS Settings conventions.
//
// Called by:
//   - HomeScreen bottom navigation settings tab

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../components/glass_card.dart';
import '../utils/logger.dart';
import '../components/section_header.dart';
import '../components/status_dot.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import '../models/protocol.dart';
import '../models/payloads/cli_payloads.g.dart';
import '../models/payloads/project_payloads.g.dart';
import '../services/connection_service.dart';
import '../services/locale_service.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/cli_operations.dart';
import '../services/ws_operations/project_operations.dart';
import '../theme/code_theme.dart';
import '../theme/theme_extensions.dart';
import 'agent_detail_screen.dart';
import 'plugin_screen.dart';
import 'connect_screen.dart';
import '../animation/page_transition_builder.dart';
import '../components/app_toast.dart';
import '../widgets/project_picker_sheet.dart';

final _log = getLogger('Settings');

/// Settings screen with project management, connection status,
/// CLI tools, theme toggle, and about info.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Map<String, dynamic>> _cliList = [];
  List<Map<String, dynamic>> _projects = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    ws.cliOps.requestCLIList();
    ws.projectOps.requestProjectList();

    _sub = ws.messageStream.listen((msg) {
      if (msg.type == MessageType.cliListResult) {
        final listResult = CliListResultPayload.fromJson(msg.payload);
        setState(() {
          _cliList = listResult.adapters;
        });
        // Show action result toast (from add/remove/install operations)
        final actionResult = listResult.actionResult;
        if (actionResult != null && mounted) {
          final success = actionResult['success'] == true;
          final message = actionResult['message'] as String? ?? '';
          if (message.isNotEmpty) {
            AppToast.show(context, message,
                type: success ? AppToastType.success : AppToastType.error);
          }
        }
      }
      if (msg.type == MessageType.projectListResult) {
        final p = ProjectListResultPayload.fromJson(msg.payload);
        setState(() {
          _projects = p.projects;
        });
      }
      if (msg.type == MessageType.projectCurrent) {
        final p = ProjectCurrentPayload.fromJson(msg.payload);
        final name = p.name;
        final path = p.path;
        // Only refresh and show toast when a real project is active
        if (path.isNotEmpty) {
          ws.fileOps.requestFileTree(depth: 1);
          if (mounted) {
            AppToast.show(context, S.of(context).settingsSwitchedTo(name));
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionService>();
    // Watch WebSocketService to respond to CLI switching and other global state changes
    context.watch<WebSocketService>();
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background.withValues(alpha: 0.9),
        toolbarHeight: 44,
        title: Text(S.of(context).settingsTitle, style: typography.headlineMedium),
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          ListView(
            padding: EdgeInsets.symmetric(horizontal: spacing.md),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.lg),
                child: _buildControlCenterHero(connection),
              ),

              // Project management
              SectionHeader(
                icon: Icons.folder,
                iconColor: colors.warning,
                title: S.of(context).settingsProjectsSection,
              ),
              _buildCard([
                ..._projects.map((p) {
                  final isCurrent = p['is_current'] == true;
                  return ListTile(
                    leading: Icon(
                      isCurrent ? Icons.folder_open : Icons.folder_outlined,
                      color: isCurrent ? colors.primary : colors.onSurfaceMuted,
                    ),
                    title: Text(
                      p['name'] as String? ?? '',
                      style: typography.bodyMedium.copyWith(
                        color: isCurrent
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      p['path'] as String? ?? '',
                      style: typography.codeSmall
                          .copyWith(color: colors.onSurfaceMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isCurrent
                        ? Icon(Icons.check, color: colors.secondary, size: 18)
                        : null,
                    onTap: isCurrent
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            context
                                .read<ProjectOperations>()
                                .switchProject(p['path'] as String);
                          },
                    onLongPress: () => _confirmRemoveProject(
                        p['path'] as String, p['name'] as String),
                  );
                }),
                ListTile(
                  leading: Icon(Icons.add, color: colors.secondary),
                  title: Text(S.of(context).settingsAddProject,
                      style: typography.bodyMedium
                          .copyWith(color: colors.secondary)),
                  onTap: () => _showAddProjectDialog(),
                ),
              ]),

              SizedBox(height: spacing.sm),

              // Connection status
              SectionHeader(
                icon: Icons.wifi,
                iconColor: colors.success,
                title: S.of(context).settingsConnectionSection,
              ),
              _buildCard([
                ListTile(
                  leading: StatusDot(
                    state: connection.isConnected
                        ? StatusDotState.connected
                        : StatusDotState.disconnected,
                  ),
                  title: Text(
                    connection.isConnected ? S.of(context).settingsConnected : S.of(context).settingsDisconnected,
                    style: typography.bodyMedium,
                  ),
                  subtitle: connection.isConnected
                      ? Text(connection.wsUrl,
                          style: typography.codeSmall
                              .copyWith(color: colors.onSurfaceMuted))
                      : null,
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colors.error),
                  title: Text(S.of(context).settingsClearConnections, style: typography.bodyMedium),
                  subtitle: Text(S.of(context).settingsClearConnectionsDesc,
                      style: typography.labelSmall
                          .copyWith(color: colors.onSurfaceMuted)),
                  onTap: () async {
                    await ConnectScreen.forgetSavedConnections();
                    if (context.mounted) {
                      AppToast.show(context, S.of(context).settingsClearedConnections, type: AppToastType.success);
                    }
                  },
                ),
              ]),

              SizedBox(height: spacing.sm),

              // Appearance (theme toggle)
              SectionHeader(
                icon: Icons.palette,
                iconColor: colors.primary,
                title: S.of(context).settingsAppearanceSection,
              ),
              _buildCard([
                Consumer<ThemeNotifier>(
                  builder: (_, themeNotifier, __) => SwitchListTile(
                    title: Text(S.of(context).settingsDarkTheme, style: typography.bodyMedium),
                    subtitle: Text(
                      themeNotifier.isDark ? 'Signal Night' : 'Signal Paper',
                      style: typography.labelSmall
                          .copyWith(color: colors.onSurfaceMuted),
                    ),
                    value: themeNotifier.isDark,
                    activeTrackColor: colors.primary,
                    onChanged: (v) {
                      _log.fine('🎨 主题切换: isDark=$v');
                      themeNotifier.setDark(v);
                    },
                  ),
                ),
                Consumer<LocaleNotifier>(
                  builder: (_, localeNotifier, __) => ListTile(
                    title: Text(S.of(context).settingsLanguageLabel, style: typography.bodyMedium),
                    subtitle: Text(
                      localeNotifier.displayName,
                      style: typography.labelSmall
                          .copyWith(color: colors.onSurfaceMuted),
                    ),
                    trailing: Icon(Icons.chevron_right,
                        color: colors.onSurfaceMuted),
                    onTap: () => _showLanguagePicker(context, localeNotifier),
                  ),
                ),
              ]),

              SizedBox(height: spacing.sm),

              // Editor settings
              SectionHeader(
                icon: Icons.code,
                iconColor: colors.secondary,
                title: S.of(context).settingsEditorSection,
              ),
              _buildCard([
                Consumer<CodeThemeNotifier>(
                  builder: (_, codeTheme, __) => ListTile(
                    title: Text(S.of(context).settingsCodeTheme, style: typography.bodyMedium),
                    subtitle: Text(
                      codeTheme.current.label,
                      style: typography.labelSmall
                          .copyWith(color: colors.onSurfaceMuted),
                    ),
                    trailing:
                        Icon(Icons.chevron_right, color: colors.onSurfaceMuted),
                    onTap: () => _showCodeThemePicker(context, codeTheme),
                  ),
                ),
                Consumer<CodeThemeNotifier>(
                  builder: (_, codeTheme, __) => SwitchListTile(
                    title: Text(S.of(context).settingsWordWrap, style: typography.bodyMedium),
                    subtitle: Text(
                      codeTheme.wordWrap ? S.of(context).settingsWordWrapOn : S.of(context).settingsWordWrapOff,
                      style: typography.labelSmall
                          .copyWith(color: colors.onSurfaceMuted),
                    ),
                    value: codeTheme.wordWrap,
                    activeTrackColor: colors.primary,
                    onChanged: (v) => codeTheme.setWordWrap(v),
                  ),
                ),
                Consumer<CodeThemeNotifier>(
                  builder: (_, codeTheme, __) => SwitchListTile(
                    title: Text(S.of(context).settingsShowLineNumbers, style: typography.bodyMedium),
                    value: codeTheme.showLineNumbers,
                    activeTrackColor: colors.primary,
                    onChanged: (v) => codeTheme.setShowLineNumbers(v),
                  ),
                ),
                Consumer<CodeThemeNotifier>(
                  builder: (_, codeTheme, __) => ListTile(
                    title: Text(S.of(context).settingsFontSize, style: typography.bodyMedium),
                    subtitle: Text(
                      '${codeTheme.fontSize.toInt()} px',
                      style: typography.labelSmall
                          .copyWith(color: colors.onSurfaceMuted),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.remove,
                              size: 20, color: colors.onSurfaceVariant),
                          onPressed: () =>
                              codeTheme.setFontSize(codeTheme.fontSize - 1),
                        ),
                        Text('${codeTheme.fontSize.toInt()}',
                            style: typography.bodyMedium),
                        IconButton(
                          icon: Icon(Icons.add,
                              size: 20, color: colors.onSurfaceVariant),
                          onPressed: () =>
                              codeTheme.setFontSize(codeTheme.fontSize + 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),

              SizedBox(height: spacing.sm),

              // Plugin management
              SectionHeader(
                icon: Icons.extension,
                iconColor: colors.primary,
                title: S.of(context).settingsPluginsSection,
              ),
              _buildCard([
                ListTile(
                  leading: Icon(Icons.extension, color: colors.primary),
                  title: Text(S.of(context).settingsPluginManagement, style: typography.bodyMedium),
                  subtitle: Text(
                    S.of(context).settingsPluginManagementDesc,
                    style: typography.labelSmall
                        .copyWith(color: colors.onSurfaceMuted),
                  ),
                  trailing: Icon(Icons.chevron_right,
                      color: colors.onSurfaceMuted, size: 20),
                  onTap: () {
                    Navigator.push(
                      context,
                      AppPageRoute(
                        type: PageTransitionType.slideUp,
                        page: const PluginScreen(),
                      ),
                    );
                  },
                ),
              ]),

              SizedBox(height: spacing.sm),

              // CLI tools
              SectionHeader(
                icon: Icons.terminal,
                iconColor: colors.secondary,
                title: S.of(context).settingsCliToolsSection,
              ),
              _buildScrollableCard(
                maxHeight: 320,
                children: [
                  // Installed CLIs first
                  ..._cliList.where((c) => c['installed'] == true).map(
                        (cli) => _buildCLITile(cli, colors, typography),
                      ),
                  // Uninstalled CLIs after
                  ..._cliList.where((c) => c['installed'] != true).map(
                        (cli) => _buildCLITile(cli, colors, typography),
                      ),
                  // Add custom agent
                  ListTile(
                    leading: Icon(Icons.add, color: colors.secondary),
                    title: Text(S.of(context).settingsAddCustomAgent,
                        style: typography.bodyMedium
                            .copyWith(color: colors.secondary)),
                    onTap: () => _showAddCustomAgentDialog(),
                  ),
                ],
              ),

              SizedBox(height: spacing.xxl),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackdrop() {
    final colors = context.colors;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -70,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(alpha: 0.22),
                    colors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 140,
            left: -100,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.secondary.withValues(alpha: 0.16),
                    colors.secondary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlCenterHero(ConnectionService connection) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    return GlassCard(
      padding: EdgeInsets.all(spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.primary,
                      colors.secondary.withValues(alpha: 0.82)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(context.radii.lg),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary
                          .withValues(alpha: context.isDark ? 0.24 : 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(Icons.developer_mode_rounded,
                    size: 28, color: colors.onPrimary),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Signal Console', style: typography.headlineLarge),
                    SizedBox(height: spacing.xxs),
                    Text(
                      S.of(context).settingsControlCenterSubtitle,
                      style: typography.bodySmall.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.md,
                  vertical: spacing.sm,
                ),
                decoration: BoxDecoration(
                  color:
                      (connection.isConnected ? colors.success : colors.warning)
                          .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(context.radii.full),
                  border: Border.all(
                    color: (connection.isConnected
                            ? colors.success
                            : colors.warning)
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    connection.isConnected ? S.of(context).settingsLinkOnline : S.of(context).settingsLinkOffline,
                    key: ValueKey(connection.isConnected),
                    style: typography.labelMedium.copyWith(
                      color: connection.isConnected
                          ? colors.success
                          : colors.warning,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.lg),
          Text(
            S.of(context).settingsControlCenterDescription,
            style: typography.bodyMedium.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          SizedBox(height: spacing.lg),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: [
              _buildHeroChip(
                icon: Icons.palette_outlined,
                label: context.isDark ? 'Signal Night' : 'Signal Paper',
                tint: colors.primary,
              ),
              _buildHeroChip(
                icon: Icons.folder_copy_outlined,
                label: S.of(context).settingsNProjects(_projects.length),
                tint: colors.warning,
              ),
              _buildHeroChip(
                icon: Icons.memory_outlined,
                label:
                    S.of(context).settingsNClis(_cliList.where((c) => c['installed'] == true).length),
                tint: colors.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroChip({
    required IconData icon,
    required String label,
    required Color tint,
  }) {
    final typography = context.typography;
    final spacing = context.spacing;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.sm,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.full),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tint),
          SizedBox(width: spacing.xs),
          Text(
            label,
            style: typography.labelMedium.copyWith(color: tint),
          ),
        ],
      ),
    );
  }

  /// Language picker bottom sheet.
  void _showLanguagePicker(BuildContext context, LocaleNotifier localeNotifier) {
    final current = localeNotifier.locale?.languageCode;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Language', style: context.typography.titleMedium),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('System'),
              trailing: current == null
                  ? Icon(Icons.check, color: context.colors.primary)
                  : null,
              onTap: () {
                localeNotifier.setLocale(null);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('English'),
              trailing: current == 'en'
                  ? Icon(Icons.check, color: context.colors.primary)
                  : null,
              onTap: () {
                localeNotifier.setLocale(const Locale('en'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('中文'),
              trailing: current == 'zh'
                  ? Icon(Icons.check, color: context.colors.primary)
                  : null,
              onTap: () {
                localeNotifier.setLocale(const Locale('zh'));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Code theme picker
  void _showCodeThemePicker(BuildContext context, CodeThemeNotifier codeTheme) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(S.of(context).settingsSelectCodeTheme, style: context.typography.titleMedium),
            ),
            const Divider(height: 1),
            // Flexible + ListView prevents overflow when the theme list
            // exceeds the available screen height on small devices.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: availableCodeThemes.map((entry) => ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: entry.backgroundColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: entry.id == codeTheme.themeId
                                ? context.colors.primary
                                : context.colors.borderSubtle,
                            width: entry.id == codeTheme.themeId ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'A',
                            style: TextStyle(
                              color: entry.foregroundColor,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      title: Text(entry.label),
                      trailing: entry.id == codeTheme.themeId
                          ? Icon(Icons.check, color: context.colors.primary)
                          : null,
                      onTap: () {
                        codeTheme.setTheme(entry.id);
                        Navigator.pop(context);
                      },
                    )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Grouped card container
  Widget _buildCard(List<Widget> children) {
    final colors = context.colors;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: context.spacing.xs),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.surfaceElevated,
            colors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(context.radii.xl),
        border:
            Border.all(color: colors.border.withValues(alpha: 0.6), width: 1),
        boxShadow: [
          BoxShadow(
            color: colors.scrim.withValues(alpha: context.isDark ? 0.16 : 0.05),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                color: colors.borderSubtle,
                indent: 56,
              ),
          ],
        ],
      ),
    );
  }

  /// Scrollable grouped card with fixed max height
  Widget _buildScrollableCard({
    required List<Widget> children,
    double maxHeight = 300,
  }) {
    final colors = context.colors;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: context.spacing.xs),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.surfaceElevated,
            colors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(context.radii.xl),
        border:
            Border.all(color: colors.border.withValues(alpha: 0.6), width: 1),
        boxShadow: [
          BoxShadow(
            color: colors.scrim.withValues(alpha: context.isDark ? 0.16 : 0.05),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: children.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: colors.borderSubtle,
          indent: 56,
        ),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }

  void _showAddProjectDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProjectPickerSheet(
        onProjectSelected: (path) {
          Navigator.pop(ctx);
          context.read<ProjectOperations>().addProject(path);
        },
      ),
    );
  }

  /// Single CLI list tile
  Widget _buildCLITile(
      Map<String, dynamic> cli, dynamic colors, dynamic typography) {
    final installed = cli['installed'] == true;
    final isCustom = cli['is_custom'] == true;
    final name = cli['name'] as String? ?? '';
    final displayName = cli['display_name'] as String? ?? '';
    final executionEnv = cli['execution_env'] as String? ?? 'native';
    final isWsl = executionEnv == 'wsl';
    final canInstall = cli['can_install'] == true;
    final installHint = cli['install_hint'] as String?;
    final isInstalling = _installingCli == name;
    final isUninstalling = _uninstallingCli == name;
    final isBusy = isInstalling || isUninstalling;
    final ws = context.read<WebSocketService>();
    final isSelected = installed && name == ws.defaultCli;

    // Build subtitle: show progress during install/uninstall, otherwise status
    String subtitle;
    if (isBusy && _progressLabel.isNotEmpty) {
      subtitle = _progressLabel;
    } else if (installed) {
      subtitle = S.of(context).settingsInstalled;
    } else {
      subtitle = installHint ?? S.of(context).settingsNotInstalled;
    }

    return Column(
      children: [
        ListTile(
          selected: isSelected,
          selectedTileColor: colors.primary.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radii.lg),
          ),
          leading: Icon(
            installed
                ? (isSelected ? Icons.radio_button_checked : Icons.radio_button_off)
                : Icons.circle_outlined,
            color: installed
                ? (isSelected ? colors.primary : colors.onSurfaceVariant)
                : colors.onSurfaceMuted,
          ),
          title: Row(
            children: [
              Flexible(child: Text(displayName, style: typography.bodyMedium)),
              if (isWsl) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('WSL', style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w600,
                    color: colors.primary,
                  )),
                ),
              ],
            ],
          ),
          subtitle: Text(
            subtitle,
            style: typography.labelSmall.copyWith(color: colors.onSurfaceMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _buildCLITrailing(
              installed, isCustom, isSelected, name, displayName, canInstall, isBusy, colors),
          onTap: installed
              ? () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    AppPageRoute(
                      type: PageTransitionType.slideUp,
                      page: AgentDetailScreen(adapter: cli),
                    ),
                  );
                }
              : null,
          onLongPress: installed && canInstall && !isCustom
              ? () => _confirmUninstallCLI(name, displayName)
              : null,
        ),
        // Progress bar during install/uninstall
        if (isBusy && _progressTotal > 0)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.lg),
            child: LinearProgressIndicator(
              value: _progressTotal > 1
                  ? (_progressStep - 1) / _progressTotal
                  : null,
              backgroundColor: colors.surfaceVariant,
              color: isUninstalling ? colors.error : colors.secondary,
              minHeight: 2,
            ),
          ),
      ],
    );
  }

  /// CLI trailing button: install, uninstall, or custom remove.
  Widget? _buildCLITrailing(bool installed, bool isCustom, bool isSelected,
      String name, String displayName, bool canInstall, bool isBusy,
      dynamic colors) {
    // Custom agent → remove button (same icon as uninstall for visual consistency)
    if (isCustom) {
      return IconButton(
        icon: Icon(Icons.delete_outline, size: 18, color: colors.onSurfaceMuted),
        tooltip: S.of(context).settingsRemoveTooltip,
        onPressed: () => _confirmRemoveCLI(name),
      );
    }
    // Busy (installing/uninstalling) → spinner
    if (isBusy) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.secondary,
        ),
      );
    }
    // Installed + can uninstall + not currently selected → uninstall icon
    if (installed && canInstall && !isSelected) {
      return IconButton(
        icon: Icon(Icons.delete_outline, size: 18, color: colors.onSurfaceMuted),
        tooltip: S.of(context).settingsUninstallTooltip,
        onPressed: () => _confirmUninstallCLI(name, displayName),
      );
    }
    // Not installed + can install → install button
    if (!installed && canInstall) {
      return TextButton(
        onPressed: () => _installCLI(name),
        style: TextButton.styleFrom(
          foregroundColor: colors.secondary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: colors.secondary.withValues(alpha: 0.28)),
          ),
        ),
        child: Text(S.of(context).commonInstall),
      );
    }
    return null;
  }

  String? _installingCli;
  String? _uninstallingCli;
  String _progressLabel = '';
  int _progressStep = 0;
  int _progressTotal = 0;

  /// Install a CLI with progress feedback.
  void _installCLI(String name) {
    HapticFeedback.selectionClick();
    setState(() {
      _installingCli = name;
      _progressLabel = S.of(context).settingsPreparingInstall;
      _progressStep = 0;
      _progressTotal = 0;
    });
    final ws = context.read<WebSocketService>();
    ws.cliOps.installCLI(name);

    late StreamSubscription sub;
    sub = ws.messageStream.listen((msg) {
      // Progress updates
      if (msg.type == MessageType.cliInstallProgress &&
          msg.payload['cli'] == name) {
        if (mounted) {
          final progress = CliInstallProgressPayload.fromJson(msg.payload);
          setState(() {
            _progressStep = progress.step;
            _progressTotal = progress.totalSteps;
            _progressLabel = S.of(context).settingsInstallingProgress(progress.label, progress.step, progress.totalSteps);
          });
        }
      }
      // Final result
      if (msg.type == MessageType.cliInstallResult &&
          msg.payload['cli'] == name) {
        sub.cancel();
        if (mounted) {
          final result = CliInstallResultPayload.fromJson(msg.payload);
          setState(() {
            _installingCli = null;
            _progressLabel = '';
            _progressStep = 0;
            _progressTotal = 0;
          });
          if (result.success) {
            // Auto-switch to the newly installed CLI so the user
            // lands on the chat page with the new agent ready to go
            context.read<CliOperations>().switchCLI(name);
            AppToast.show(context, result.message);
          } else {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: context.colors.surfaceElevated,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.radii.lg),
                ),
                title: Text(S.of(context).settingsInstallFailed, style: context.typography.titleMedium),
                content: Text(result.message, style: context.typography.bodyMedium),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(S.of(context).commonGotIt,
                        style: TextStyle(color: context.colors.primary)),
                  ),
                ],
              ),
            );
          }
        }
      }
    });
  }

  /// Confirm and uninstall a CLI.
  void _confirmUninstallCLI(String name, String displayName) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radii.lg),
        ),
        title: Text(S.of(context).settingsUninstallAgent, style: context.typography.titleMedium),
        content: Text(S.of(context).settingsUninstallConfirm(displayName),
            style: context.typography.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).commonCancel, style: TextStyle(color: colors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _uninstallCLI(name);
            },
            child: Text(S.of(context).commonUninstall, style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }

  /// Uninstall a CLI with progress feedback.
  void _uninstallCLI(String name) {
    HapticFeedback.selectionClick();
    setState(() {
      _uninstallingCli = name;
      _progressLabel = S.of(context).settingsPreparingUninstall;
      _progressStep = 0;
      _progressTotal = 0;
    });
    final ws = context.read<WebSocketService>();
    ws.cliOps.uninstallCLI(name);

    late StreamSubscription sub;
    sub = ws.messageStream.listen((msg) {
      if (msg.type == MessageType.cliInstallProgress &&
          msg.payload['cli'] == name) {
        if (mounted) {
          final progress = CliInstallProgressPayload.fromJson(msg.payload);
          setState(() {
            _progressStep = progress.step;
            _progressTotal = progress.totalSteps;
            _progressLabel = S.of(context).settingsUninstallingProgress(progress.label, progress.step, progress.totalSteps);
          });
        }
      }
      if (msg.type == MessageType.cliUninstallResult &&
          msg.payload['cli'] == name) {
        sub.cancel();
        if (mounted) {
          final result = CliUninstallResultPayload.fromJson(msg.payload);
          setState(() {
            _uninstallingCli = null;
            _progressLabel = '';
            _progressStep = 0;
            _progressTotal = 0;
          });
          AppToast.show(context, result.message,
              type: result.success ? AppToastType.success : AppToastType.error);
        }
      }
    });
  }

  /// Add custom agent dialog
  void _showAddCustomAgentDialog() {
    final colors = context.colors;
    final nameCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    final argsCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radii.lg),
        ),
        title: Text(S.of(context).settingsAddCustomAgentTitle, style: context.typography.titleMedium),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: context.typography.bodyMedium,
                decoration: InputDecoration(
                  labelText: S.of(context).settingsAgentNameLabel,
                  hintText: S.of(context).settingsAgentNameHint,
                  hintStyle: context.typography.bodyMedium
                      .copyWith(color: colors.onSurfaceMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.radii.sm),
                  ),
                ),
              ),
              SizedBox(height: context.spacing.sm),
              TextField(
                controller: cmdCtrl,
                style: context.typography.codeSmall,
                decoration: InputDecoration(
                  labelText: S.of(context).settingsAgentCommandLabel,
                  hintText: S.of(context).settingsAgentCommandHint,
                  hintStyle: context.typography.codeSmall
                      .copyWith(color: colors.onSurfaceMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.radii.sm),
                  ),
                ),
              ),
              SizedBox(height: context.spacing.sm),
              TextField(
                controller: argsCtrl,
                style: context.typography.codeSmall,
                decoration: InputDecoration(
                  labelText: S.of(context).settingsAgentArgsLabel,
                  hintText: S.of(context).settingsAgentArgsHint,
                  hintStyle: context.typography.codeSmall
                      .copyWith(color: colors.onSurfaceMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.radii.sm),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).commonCancel, style: TextStyle(color: colors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              final name = cmdCtrl.text
                  .trim()
                  .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
              final displayName = nameCtrl.text.trim();
              final command = cmdCtrl.text.trim();
              final args = argsCtrl.text.trim().split(RegExp(r'\s+'))
                ..removeWhere((s) => s.isEmpty);
              if (name.isEmpty || command.isEmpty || displayName.isEmpty) {
                return;
              }
              // Close dialog and send request — result will be shown
              // as a toast via action_result in cliListResult handler
              Navigator.pop(ctx);
              context.read<CliOperations>().addCustomCLI(
                    name: name,
                    command: command,
                    args: args,
                    displayName: displayName,
                  );
            },
            child: Text(S.of(context).commonAdd, style: TextStyle(color: colors.secondary)),
          ),
        ],
      ),
    );
  }

  /// Confirm remove custom agent
  void _confirmRemoveCLI(String name) {
    final colors = context.colors;
    final cli = _cliList.firstWhere((c) => c['name'] == name,
        orElse: () => <String, dynamic>{});
    final displayName = cli['display_name'] as String? ?? name;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radii.lg),
        ),
        title: Text(S.of(context).settingsRemoveAgent, style: context.typography.titleMedium),
        content: Text(S.of(context).settingsRemoveAgentConfirm(displayName),
            style: context.typography.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).commonCancel, style: TextStyle(color: colors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              context.read<CliOperations>().removeCLI(name);
              Navigator.pop(ctx);
            },
            child: Text(S.of(context).commonRemove, style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveProject(String path, String name) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radii.lg),
        ),
        title: Text(S.of(context).settingsDeleteProject, style: context.typography.titleMedium),
        content: Text(S.of(context).settingsDeleteProjectConfirm(name),
            style: context.typography.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).commonCancel, style: TextStyle(color: colors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              context.read<ProjectOperations>().removeProject(path);
              Navigator.pop(ctx);
            },
            child: Text(S.of(context).commonDelete, style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
