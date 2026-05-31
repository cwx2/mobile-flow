/// config_panel.dart — ACP mode selector and config options panel.
///
/// Renders mode switching and dynamic config options from ACP.
/// Mode list comes from CliCapabilities.availableModes.
/// Config options come from ACP config_option_update events.
/// Uses [AppBottomSheet] for consistent styling and focus management.
library;

import 'package:flutter/material.dart';

import '../../components/app_bottom_sheet.dart';
import '../../components/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../../models/protocol.dart';
import '../../services/websocket_service.dart';
import '../../theme/theme_extensions.dart';

/// Mode selector chip for the toolbar.
class ModeSelector extends StatelessWidget {
  final WebSocketService ws;

  const ModeSelector({super.key, required this.ws});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final modes = ws.cliCapabilities.availableModes;
    if (modes.isEmpty) return const SizedBox.shrink();

    final current = ws.currentMode;
    final currentName = modes
        .where((m) => m['id'] == current)
        .map((m) => m['name'] as String? ?? m['id'] as String? ?? '')
        .firstOrNull ?? (current.isNotEmpty ? current : 'Mode');

    return GestureDetector(
      onTap: () => _showModePicker(context, modes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(currentName,
                style: TextStyle(fontSize: 11, color: colors.primary)),
            Icon(Icons.arrow_drop_down, size: 14, color: colors.primary),
          ],
        ),
      ),
    );
  }

  void _showModePicker(BuildContext context, List<Map<String, dynamic>> modes) {
    final colors = context.colors;
    final activeMode = ws.currentMode;

    AppBottomSheet.show(context, builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in modes)
              ListTile(
                leading: Icon(
                  activeMode == (mode['id'] as String? ?? '')
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: colors.primary, size: 20,
                ),
                title: Text(mode['name'] as String? ?? '', style: const TextStyle(fontSize: 14)),
                onTap: () {
                  final modeName = mode['name'] as String? ?? mode['id'] as String? ?? '';
                  Navigator.pop(ctx);
                  ws.cliOps.setMode(mode['id'] as String? ?? '');
                  AppToast.show(context, S.of(context).configPanelSwitchedTo(modeName));
                },
              ),
          ],
        ),
      );
    });
  }
}

/// Config button that opens the settings panel.
class ConfigButton extends StatelessWidget {
  final WebSocketService ws;

  const ConfigButton({super.key, required this.ws});

  @override
  Widget build(BuildContext context) {
    final hasNonModeOptions = ws.configOptions.any((o) => o.category != 'mode');
    if (!hasNonModeOptions) return const SizedBox.shrink();
    final colors = context.colors;
    return GestureDetector(
      onTap: () => showConfigPanel(context, ws),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Icon(Icons.tune, size: 16, color: colors.onSurfaceVariant),
      ),
    );
  }
}

/// Show the config panel as a bottom sheet.
void showConfigPanel(BuildContext context, WebSocketService ws) {
  final colors = context.colors;
  AppBottomSheet.show(context, builder: (ctx) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.of(context).configPanelAgentSettings, style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: colors.onSurface,
          )),
          const SizedBox(height: 12),
          for (final opt in ws.configOptions.where((o) => o.category != 'mode')) ...[
            _ConfigOptionTile(option: opt, ws: ws, parentContext: ctx),
            const SizedBox(height: 8),
          ],
          SwitchListTile(
            title: Text(S.of(context).configPanelAutoApprove, style: TextStyle(fontSize: 14)),
            subtitle: Text(S.of(context).configPanelAutoApproveDesc, style: TextStyle(fontSize: 12)),
            value: ws.autoApprovePermissions,
            onChanged: (v) {
              ws.autoApprovePermissions = v;
              Navigator.pop(ctx);
            },
            dense: true,
          ),
        ],
      ),
    );
  });
}

class _ConfigOptionTile extends StatelessWidget {
  final ConfigOption option;
  final WebSocketService ws;
  final BuildContext parentContext;

  const _ConfigOptionTile({required this.option, required this.ws, required this.parentContext});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (option.type == 'boolean') {
      return SwitchListTile(
        title: Text(option.name, style: const TextStyle(fontSize: 14)),
        subtitle: option.description != null
            ? Text(option.description!, style: const TextStyle(fontSize: 12))
            : null,
        value: option.currentValue == true,
        onChanged: (v) {
          ws.cliOps.setConfigOption(option.id, v);
          Navigator.pop(parentContext);
          AppToast.show(parentContext, '${option.name}: ${v ? S.of(parentContext).configPanelOn : S.of(parentContext).configPanelOff}');
        },
        dense: true,
      );
    }
    final currentName = option.options
        ?.where((o) => o.value == option.currentValue)
        .map((o) => o.name)
        .firstOrNull ?? (option.currentValue?.toString() ?? '');
    return ListTile(
      title: Text(option.name, style: const TextStyle(fontSize: 14)),
      subtitle: option.description != null
          ? Text(option.description!, style: const TextStyle(fontSize: 12))
          : null,
      trailing: Text(currentName, style: TextStyle(fontSize: 12, color: colors.primary)),
      dense: true,
      onTap: () {
        Navigator.pop(parentContext);
        _showOptionPicker(context);
      },
    );
  }

  void _showOptionPicker(BuildContext context) {
    showSelectOptionPicker(context, option: option, ws: ws);
  }
}

/// Show a bottom sheet picker for a select-type [ConfigOption].
///
/// Shared by [_ConfigOptionTile] in the chat input bar and
/// [AgentDetailScreen] in the agent detail page. Displays radio
/// buttons for each option value and calls [ws.cliOps.setConfigOption]
/// on selection.
void showSelectOptionPicker(
  BuildContext context, {
  required ConfigOption option,
  required WebSocketService ws,
}) {
  final colors = context.colors;
  AppBottomSheet.show(context, builder: (ctx) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(option.name, style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: colors.onSurface,
            )),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final opt in option.options ?? [])
                  ListTile(
                    leading: Icon(
                      option.currentValue == opt.value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: colors.primary, size: 20,
                    ),
                    title: Text(opt.name, style: const TextStyle(fontSize: 14)),
                    subtitle: opt.description != null
                        ? Text(opt.description!, style: const TextStyle(fontSize: 12))
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      ws.cliOps.setConfigOption(option.id, opt.value);
                      AppToast.show(context, '${option.name}: ${opt.name}');
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  });
}
