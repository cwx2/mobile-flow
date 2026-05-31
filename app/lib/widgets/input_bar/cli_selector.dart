/// cli_selector.dart — CLI selector widget for the chat input toolbar.
///
/// Shows the current CLI name; tapping opens a bottom sheet to switch.
/// Uses [AppBottomSheet] for consistent styling and focus management.
library;

import 'package:flutter/material.dart';

import '../../components/app_bottom_sheet.dart';
import '../../l10n/app_localizations.dart';
import '../../services/websocket_service.dart';
import '../../theme/theme_extensions.dart';

/// CLI selector chip for the toolbar.
class CliSelector extends StatelessWidget {
  final WebSocketService ws;

  const CliSelector({super.key, required this.ws});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: colors.secondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ws.cliDisplayName(ws.defaultCli),
                style: TextStyle(fontSize: 11, color: colors.secondary)),
            Icon(Icons.arrow_drop_down, size: 14, color: colors.secondary),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final clis = ws.installedClis;
    final currentCli = ws.defaultCli;
    final colors = context.colors;

    AppBottomSheet.show(context, builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(S.of(context).cliSelectorTitle,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          ...clis.map((cli) => ListTile(
            leading: Icon(
              cli == currentCli ? Icons.radio_button_checked : Icons.radio_button_off,
              color: cli == currentCli ? colors.primary : colors.onSurfaceVariant,
              size: 20,
            ),
            title: Text(ws.cliDisplayName(cli), style: const TextStyle(fontSize: 14)),
            dense: true,
            visualDensity: VisualDensity.compact,
            onTap: () {
              ws.cliOps.switchCLI(cli);
              Navigator.pop(ctx);
            },
          )),
        ],
      );
    });
  }
}
