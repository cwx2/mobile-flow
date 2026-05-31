/// code_theme.dart — Syntax highlighting theme configuration.
///
/// Provides [CodeHighlightTheme] (language rules + style map) and
/// [CodeHighlightThemeMode] (per-language mode with size safety limits).

part of editor;

/// Syntax highlighting theme combining language rules with style definitions.
///
/// Uses Re-Highlight for tokenization. Pass an instance to
/// [CodeEditorStyle.codeTheme] to enable syntax coloring.
class CodeHighlightTheme {

  const CodeHighlightTheme({
    required this.languages,
    required this.theme,
    this.plugins = const [],
  });

  /// Supported syntax highlighting language rules.
  final Map<String, CodeHighlightThemeMode> languages;

  /// The syntax highlighting style theme.
  final Map<String, TextStyle> theme;

  /// The plugins for syntax highlighting.
  final List<HLPlugin> plugins;

  @override
  int get hashCode => Object.hash(languages, theme, plugins);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeHighlightTheme
        && mapEquals(other.languages, languages)
        && mapEquals(other.theme, theme)
        && listEquals(other.plugins, plugins);
  }

}

/// Per-language highlighting mode with safety limits.
///
/// The Dart VM has a relatively small stack, so very large files or very
/// long lines can cause stack overflow during regex-based highlighting.
/// [maxSize] and [maxLineLength] disable highlighting when exceeded.
///
/// See https://github.com/dart-lang/sdk/issues/48425
class CodeHighlightThemeMode {

  const CodeHighlightThemeMode({
    required this.mode,
    this.maxSize = 4 * 1024 * 1024,
    this.maxLineLength = 1 * 1024 * 1024,
  });

  /// Syntax highlighting language rule.
  final Mode mode;

  /// If the total text length is higher than this value, syntax highlighting
  /// will not be performed.
  ///
  /// The default value is 4MB.
  final int maxSize;

  /// If the text length of a line is higher than this value, syntax highlighting
  /// will not be performed.
  ///
  /// The default value is 1MB.
  final int maxLineLength;

  @override
  int get hashCode => Object.hash(mode, maxSize, maxLineLength);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeHighlightThemeMode
        && mode == other.mode && maxSize == other.maxSize
        && maxLineLength == other.maxLineLength;
  }

}

extension CodeHighlightThemeModeExtension on Mode {

  CodeHighlightThemeMode get themeMode => CodeHighlightThemeMode(mode: this);

}