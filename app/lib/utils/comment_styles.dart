/// comment_styles.dart — Language comment style registry.
///
/// Single source of truth for comment syntax per programming language.
/// Used by CodeEditorView (for CodeEditor's commentFormatter) and
/// EditorExtraKeys (for the "//" toggle button).
library;

import '../editor/editor.dart';

/// Comment style definition for a programming language.
typedef CommentStyle = ({String? single, String? multiOpen, String? multiClose});

// ── Comment style presets ──

const CommentStyle _cStyle    = (single: '//',  multiOpen: '/*',   multiClose: '*/');
const CommentStyle _hashStyle = (single: '#',   multiOpen: null,   multiClose: null);
const CommentStyle _xmlStyle  = (single: null,  multiOpen: '<!--', multiClose: '-->');
const CommentStyle _cssStyle  = (single: null,  multiOpen: '/*',   multiClose: '*/');
const CommentStyle _luaStyle  = (single: '--',  multiOpen: '--[[', multiClose: ']]');
const CommentStyle _sqlStyle  = (single: '--',  multiOpen: '/*',   multiClose: '*/');
const CommentStyle _scssStyle = (single: '//',  multiOpen: '/*',   multiClose: '*/');

/// Comment style config per language.
///
/// Keys match the language names returned by [detectLanguage].
const commentStyles = <String, CommentStyle>{
  // C-family: //  /* */
  'dart': _cStyle, 'javascript': _cStyle, 'typescript': _cStyle,
  'java': _cStyle, 'kotlin': _cStyle, 'swift': _cStyle,
  'go': _cStyle, 'rust': _cStyle, 'cpp': _cStyle,
  'csharp': _cStyle, 'php': _cStyle,
  // Hash: #
  'python': _hashStyle, 'ruby': _hashStyle, 'bash': _hashStyle,
  'yaml': _hashStyle, 'r': _hashStyle, 'ini': _hashStyle,
  // Others
  'css': _cssStyle, 'scss': _scssStyle,
  'lua': _luaStyle, 'sql': _sqlStyle,
  'xml': _xmlStyle, 'markdown': _xmlStyle,
};

/// Build a [CodeCommentFormatter] for the given language name.
///
/// Returns null if the language has no known comment style.
CodeCommentFormatter? buildCommentFormatter(String lang) {
  final style = commentStyles[lang];
  if (style == null) return null;
  return DefaultCodeCommentFormatter(
    singleLinePrefix: style.single,
    multiLinePrefix: style.multiOpen,
    multiLineSuffix: style.multiClose,
  );
}
