/// code_theme.dart — Code syntax highlighting theme manager.
//
// Manages syntax highlighting themes for the editor and file viewer.
// Injected via Provider so all CodeEditor instances share the same theme.
// Theme data sourced from re_highlight (based on highlight.js v11.9.0).

import 'package:flutter/material.dart';
import 'package:re_highlight/styles/atom-one-dark.dart' as hl;
import 'package:re_highlight/styles/github.dart' as hl_github;
import 'package:re_highlight/styles/monokai-sublime.dart' as hl_monokai;
import 'package:re_highlight/styles/night-owl.dart' as hl_night_owl;
import 'package:re_highlight/styles/nord.dart' as hl_nord;
import 'package:re_highlight/styles/shades-of-purple.dart' as hl_purple;
import 'package:re_highlight/styles/tokyo-night-dark.dart' as hl_tokyo;
import 'package:re_highlight/styles/vs2015.dart' as hl_vs2015;

// flutter_highlight themes (for diff_viewer and other HighlightView consumers)
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/night-owl.dart';
import 'package:flutter_highlight/themes/nord.dart';
import 'package:flutter_highlight/themes/vs2015.dart';

/// Theme entry.
class CodeThemeEntry {
  final String id;
  final String label;

  /// re_highlight theme (for CodeEditor).
  final Map<String, TextStyle> reTheme;

  /// flutter_highlight theme (for HighlightView / diff_viewer).
  final Map<String, TextStyle> hlTheme;

  const CodeThemeEntry({
    required this.id,
    required this.label,
    required this.reTheme,
    required this.hlTheme,
  });

  Color get backgroundColor =>
      reTheme['root']?.backgroundColor ?? const Color(0xFF1E1E1E);
  Color get foregroundColor =>
      reTheme['root']?.color ?? const Color(0xFFDCDCDC);
}

/// All available themes.
final List<CodeThemeEntry> availableCodeThemes = [
  CodeThemeEntry(
      id: 'vs2015',
      label: 'VS Code Dark+',
      reTheme: hl_vs2015.vs2015Theme,
      hlTheme: vs2015Theme),
  CodeThemeEntry(
      id: 'atom-one-dark',
      label: 'Atom One Dark',
      reTheme: hl.atomOneDarkTheme,
      hlTheme: atomOneDarkTheme),
  CodeThemeEntry(
      id: 'monokai-sublime',
      label: 'Monokai',
      reTheme: hl_monokai.monokaiSublimeTheme,
      hlTheme: monokaiSublimeTheme),
  CodeThemeEntry(
      id: 'night-owl',
      label: 'Night Owl',
      reTheme: hl_night_owl.nightOwlTheme,
      hlTheme: nightOwlTheme),
  CodeThemeEntry(
      id: 'nord',
      label: 'Nord',
      reTheme: hl_nord.nordTheme,
      hlTheme: nordTheme),
  CodeThemeEntry(
      id: 'shades-of-purple',
      label: 'Shades of Purple',
      reTheme: hl_purple.shadesOfPurpleTheme,
      hlTheme: vs2015Theme),
  CodeThemeEntry(
      id: 'tokyo-night',
      label: 'Tokyo Night',
      reTheme: hl_tokyo.tokyoNightDarkTheme,
      hlTheme: vs2015Theme),
  CodeThemeEntry(
      id: 'github',
      label: 'GitHub Light',
      reTheme: hl_github.githubTheme,
      hlTheme: githubTheme),
];

class CodeThemeNotifier extends ChangeNotifier {
  String _themeId = 'tokyo-night';
  bool _wordWrap = false;
  double _fontSize = 13;
  bool _showLineNumbers = true;

  String get themeId => _themeId;
  bool get wordWrap => _wordWrap;
  double get fontSize => _fontSize;
  bool get showLineNumbers => _showLineNumbers;

  CodeThemeEntry get current => availableCodeThemes.firstWhere(
        (t) => t.id == _themeId,
        orElse: () => availableCodeThemes.first,
      );

  Map<String, TextStyle> get reTheme => current.reTheme;
  Map<String, TextStyle> get theme => current.hlTheme;
  Color get backgroundColor => current.backgroundColor;
  Color get foregroundColor => current.foregroundColor;

  void setTheme(String id) {
    if (_themeId == id) return;
    _themeId = id;
    notifyListeners();
  }

  void setWordWrap(bool v) {
    if (_wordWrap == v) return;
    _wordWrap = v;
    notifyListeners();
  }

  void setFontSize(double v) {
    if (_fontSize == v) return;
    _fontSize = v.clamp(10, 24);
    notifyListeners();
  }

  void setShowLineNumbers(bool v) {
    if (_showLineNumbers == v) return;
    _showLineNumbers = v;
    notifyListeners();
  }
}
