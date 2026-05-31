/// test_panel_screen.dart — Test Panel top-level container with sub-navigation.
///
/// Module: screens/
/// Responsibility:
///   6th tab in the main navigation. Contains a segmented control
///   for switching between Run Configs, Script Runner, and API Tester
///   sub-panels. Uses IndexedStack to preserve state across switches.
///
///   The "Preview" tab has been replaced by the Run Configuration list,
///   which handles both preview and script configs through the new
///   Run Configuration system.
///
/// Called by:
///   - home_screen.dart (as the 6th tab)
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';
import 'run_config/run_config_list_screen.dart';
import 'test_panel/api_tester_panel.dart';
import 'test_panel/script_runner_panel.dart';

/// Sub-panel indices for the segmented control.
enum _SubPanel { preview, script, api }

/// Test Panel Screen — top-level container with segmented sub-navigation.
///
/// Provides a segmented control to switch between three sub-panels:
/// - Run Configs: configuration list with one-tap execution (replaces Web Preview)
/// - Script Runner: command execution with terminal output
/// - API Tester: Postman-like HTTP request builder
///
/// Uses [IndexedStack] to preserve sub-panel state across switches.
class TestPanelScreen extends StatefulWidget {
  const TestPanelScreen({super.key});

  @override
  State<TestPanelScreen> createState() => _TestPanelScreenState();
}

class _TestPanelScreenState extends State<TestPanelScreen> {
  _SubPanel _currentPanel = _SubPanel.preview;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final l = S.of(context);

    return SafeArea(
      child: Column(
        children: [
          // Segmented control header
          Padding(
            padding: EdgeInsets.fromLTRB(spacing.md, spacing.sm, spacing.md, spacing.xs),
            child: SegmentedButton<_SubPanel>(
              segments: [
                ButtonSegment(
                  value: _SubPanel.preview,
                  label: Text(l.testPanelTabPreview, style: const TextStyle(fontSize: 13)),
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                ),
                ButtonSegment(
                  value: _SubPanel.script,
                  label: Text(l.testPanelTabScript, style: const TextStyle(fontSize: 13)),
                  icon: const Icon(Icons.terminal, size: 16),
                ),
                ButtonSegment(
                  value: _SubPanel.api,
                  label: Text(l.testPanelTabApi, style: const TextStyle(fontSize: 13)),
                  icon: const Icon(Icons.http, size: 16),
                ),
              ],
              selected: {_currentPanel},
              onSelectionChanged: (selected) {
                setState(() => _currentPanel = selected.first);
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          // Sub-panel content (IndexedStack preserves state)
          Expanded(
            child: IndexedStack(
              index: _currentPanel.index,
              children: const [
                RunConfigListScreen(),
                ScriptRunnerPanel(),
                ApiTesterPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
