/// code_formatter.dart — Comment formatting (toggle comment) API.
///
/// Provides [CodeCommentFormatter] (abstract interface) and
/// [DefaultCodeCommentFormatter] (default implementation that handles
/// single-line `//` and multi-line `/* */` comment toggling).

part of editor;

/// Interface for toggling comments on one or more selected lines.
///
/// Implement this to support language-specific comment syntax.
/// Pass an instance to [CodeEditor.commentFormatter].
abstract class CodeCommentFormatter {

  /// Toggle comments on the given [value].
  ///
  /// [indent] is the current indentation string, [single] selects between
  /// single-line and multi-line comment style.
  /// Returns a new [CodeLineEditingValue] with comments toggled.
  CodeLineEditingValue format(CodeLineEditingValue value, String indent, bool single);

}

/// Default comment formatter supporting configurable single-line and
/// multi-line comment prefixes/suffixes.
///
/// Defaults to `//` for single-line and `/* */` for multi-line comments.
abstract class DefaultCodeCommentFormatter implements CodeCommentFormatter {

  factory DefaultCodeCommentFormatter({
    String? singleLinePrefix, 
    String? multiLinePrefix,
    String? multiLineSuffix
  }) => _DefaultCodeCommentFormatter(
    singleLinePrefix: singleLinePrefix,
    multiLinePrefix: multiLinePrefix,
    multiLineSuffix: multiLineSuffix
  );

}