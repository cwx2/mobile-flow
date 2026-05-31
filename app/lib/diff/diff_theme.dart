/// diff_theme.dart — Diff color constants using Rosé Pine palette.
//
// Color scheme for diff rendering:
// - Deleted lines: red background
// - Added lines: green background
// - Character-level changes: deeper red/green
// - Context lines: no background
// - Line numbers: grey

import 'package:flutter/material.dart';

class DiffTheme {
  // Deleted lines
  static const deletedBg = Color(0x30EB6F92); // light red background
  static const deletedCharBg = Color(0x60EB6F92); // deep red (character-level)
  static const deletedText = Color(0xFFE0DEF4); // text color
  static const deletedGutter = Color(0xFFEB6F92); // gutter color

  // Added lines
  static const addedBg = Color(0x309CCFD8); // light green background
  static const addedCharBg = Color(0x609CCFD8); // deep green (character-level)
  static const addedText = Color(0xFFE0DEF4);
  static const addedGutter = Color(0xFF9CCFD8);

  // Context lines
  static const contextBg = Colors.transparent;
  static const contextText = Color(0xFF908CAA); // grey

  // Line numbers
  static const lineNumText = Color(0xFF6E6A86);
  static const lineNumBg = Color(0xFF1A1826);

  // Separator / fold region
  static const separator = Color(0xFF393952);
  static const foldedBg = Color(0xFF232332);
  static const foldedText = Color(0xFF6E6A86);

  // Hunk header
  static const hunkHeaderBg = Color(0xFF1F1D2E);
  static const hunkHeaderText = Color(0xFFC4A7E7);

  // Code font
  static const fontFamily = 'monospace';
  static const fontSize = 12.0;
  static const lineHeight = 1.4;
}
