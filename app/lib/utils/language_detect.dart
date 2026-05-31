/// language_detect.dart — Programming language detection utility.
///
/// Detects programming language from file path for syntax highlighting
/// and comment formatting. Reuses re_highlight's built-in language
/// registry as the source of truth — only overrides are maintained here.
library;

import 'package:re_highlight/languages/all.dart';

/// Extension-to-language overrides for cases where the file extension
/// doesn't match the re_highlight language key directly.
///
/// Most extensions (dart, css, json, go, lua, sql, ...) match the
/// re_highlight key as-is and don't need an entry here.
const _extOverrides = <String, String>{
  // Shortened extensions
  'py': 'python',
  'js': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'jsx': 'javascript',
  'rb': 'ruby',
  'rs': 'rust',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'cs': 'csharp',
  'sh': 'bash',
  'zsh': 'bash',
  'md': 'markdown',
  'yml': 'yaml',
  // C/C++ family — re_highlight uses 'cpp' for all
  'c': 'cpp',
  'h': 'cpp',
  'hpp': 'cpp',
  'cc': 'cpp',
  'cxx': 'cpp',
  'hxx': 'cpp',
  // Markup
  'html': 'xml',
  'htm': 'xml',
  'xhtml': 'xml',
  'svg': 'xml',
  'plist': 'xml',
  // Config formats — re_highlight uses 'ini' for these
  'toml': 'ini',
  'cfg': 'ini',
  'conf': 'ini',
  'env': 'ini',
  'properties': 'properties',
  // Objective-C
  'm': 'objectivec',
  'mm': 'objectivec',
  // Scala / Elixir / Haskell etc.
  'sc': 'scala',
  'ex': 'elixir',
  'exs': 'elixir',
  'hs': 'haskell',
  'erl': 'erlang',
  'fs': 'fsharp',
  'fsx': 'fsharp',
  'pl': 'perl',
  'pm': 'perl',
  // Other common
  'ps1': 'powershell',
  'psm1': 'powershell',
  'tex': 'latex',
  'v': 'verilog',
  'vhd': 'vhdl',
  'proto': 'protobuf',
  'gql': 'graphql',
  'graphql': 'graphql',
};

/// Detect programming language from a file path.
///
/// Returns a language key compatible with re_highlight's
/// [builtinAllLanguages]. Falls back to 'plaintext' for unknown extensions.
///
/// Resolution order:
/// 1. Special filename match (Dockerfile, Makefile, etc.)
/// 2. Extension override map (py → python, js → javascript, etc.)
/// 3. Direct extension match against re_highlight's language registry
/// 4. Fallback to 'plaintext'
String detectLanguage(String filePath) {
  final fileName = filePath.split('/').last.toLowerCase();

  // Special filenames without meaningful extensions
  if (fileName == 'dockerfile' || fileName.startsWith('dockerfile.')) return 'dockerfile';
  if (fileName == 'makefile' || fileName == 'gnumakefile') return 'makefile';
  if (fileName == 'cmakelists.txt') return 'cmake';
  if (fileName == 'vagrantfile') return 'ruby';
  if (fileName == 'gemfile') return 'ruby';
  if (fileName == 'rakefile') return 'ruby';
  if (fileName == 'podfile') return 'ruby';

  final ext = fileName.contains('.') ? fileName.split('.').last : '';
  if (ext.isEmpty) return 'plaintext';

  // 1. Check override map (handles py→python, js→javascript, etc.)
  final override = _extOverrides[ext];
  if (override != null) return override;

  // 2. Check if extension directly matches a re_highlight language key
  if (builtinAllLanguages.containsKey(ext)) return ext;

  return 'plaintext';
}
