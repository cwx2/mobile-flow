/// plan_card.dart — Multi-step plan card.
///
/// Maps to ACP plan events (AgentPlanUpdate).
/// Displays the AI's multi-step execution plan with status icons:
/// ⬜ pending / ⏳ in progress / ✅ completed.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_message.dart';
import '../../theme/theme_extensions.dart';

/// Renders a multi-step plan with status indicators per entry.
class PlanCard extends StatelessWidget {
  final List<PlanEntry> entries;
  const PlanCard({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📋 ${S.of(context).planCardTitle}',
              style: TextStyle(
                  fontSize: 13,
                  color: colors.warning,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          ...entries.map((e) {
            final icon = e.status == 'completed'
                ? '✅'
                : e.status == 'in_progress'
                    ? '⏳'
                    : '⬜';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('$icon ${e.title}',
                  style: TextStyle(fontSize: 13, color: colors.onSurface)),
            );
          }),
        ],
      ),
    );
  }
}
