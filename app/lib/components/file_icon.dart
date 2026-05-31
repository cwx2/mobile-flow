/// file_icon.dart — File type icon component.
///
/// Module: components/
/// Responsibility:
///   Displays a unique colored icon based on file extension or special
///   file name. Color scheme follows Material Icon Theme conventions.
///   Supports 25+ extensions and 7 special file names.
///
/// Design pattern: Factory Pattern
library;

import 'package:flutter/material.dart';

/// File icon configuration.
class _FileIconConfig {
  final String label;
  final Color color;
  const _FileIconConfig(this.label, this.color);
}

/// File icon component.
class FileIcon extends StatelessWidget {
  final String fileName;
  final double size;

  const FileIcon({
    super.key,
    required this.fileName,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final config = _resolveIcon(fileName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: config.color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          config.label,
          style: TextStyle(
            fontSize: size * 0.4,
            color: Colors.white,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }

  static _FileIconConfig _resolveIcon(String name) {
    // Match special file names first
    final baseName = name.split('/').last;
    const specialMap = {
      'Dockerfile': _FileIconConfig('D', Color(0xFF2496ED)),
      'Makefile': _FileIconConfig('M', Color(0xFF6D8086)),
      '.gitignore': _FileIconConfig('G', Color(0xFFF05032)),
      'pubspec.yaml': _FileIconConfig('P', Color(0xFF02569B)),
      'package.json': _FileIconConfig('N', Color(0xFF339933)),
      'README.md': _FileIconConfig('R', Color(0xFF083FA1)),
      '.env': _FileIconConfig('E', Color(0xFFECD53F)),
    };
    if (specialMap.containsKey(baseName)) return specialMap[baseName]!;

    // Match by extension
    final ext =
        baseName.contains('.') ? baseName.split('.').last.toLowerCase() : '';
    const extMap = {
      'dart': _FileIconConfig('D', Color(0xFF02569B)),
      'py': _FileIconConfig('Py', Color(0xFF3776AB)),
      'ts': _FileIconConfig('TS', Color(0xFF3178C6)),
      'tsx': _FileIconConfig('TX', Color(0xFF3178C6)),
      'js': _FileIconConfig('JS', Color(0xFFF7DF1E)),
      'jsx': _FileIconConfig('JX', Color(0xFFF7DF1E)),
      'json': _FileIconConfig('{}', Color(0xFF5B5B5B)),
      'yaml': _FileIconConfig('Y', Color(0xFFCB171E)),
      'yml': _FileIconConfig('Y', Color(0xFFCB171E)),
      'md': _FileIconConfig('M', Color(0xFF083FA1)),
      'html': _FileIconConfig('H', Color(0xFFE34F26)),
      'css': _FileIconConfig('C', Color(0xFF1572B6)),
      'scss': _FileIconConfig('S', Color(0xFFCC6699)),
      'go': _FileIconConfig('Go', Color(0xFF00ADD8)),
      'rs': _FileIconConfig('Rs', Color(0xFFDEA584)),
      'java': _FileIconConfig('J', Color(0xFFB07219)),
      'kt': _FileIconConfig('Kt', Color(0xFF7F52FF)),
      'kts': _FileIconConfig('Kt', Color(0xFF7F52FF)),
      'swift': _FileIconConfig('Sw', Color(0xFFF05138)),
      'sh': _FileIconConfig('\$', Color(0xFF4EAA25)),
      'bash': _FileIconConfig('\$', Color(0xFF4EAA25)),
      'sql': _FileIconConfig('SQ', Color(0xFFE38C00)),
      'xml': _FileIconConfig('X', Color(0xFF0060AC)),
      'toml': _FileIconConfig('T', Color(0xFF9C4121)),
      'gradle': _FileIconConfig('G', Color(0xFF02303A)),
      'lock': _FileIconConfig('L', Color(0xFF6D8086)),
      'svg': _FileIconConfig('SV', Color(0xFFFFB13B)),
      'png': _FileIconConfig('Pg', Color(0xFF4CAF50)),
      'jpg': _FileIconConfig('Jp', Color(0xFF4CAF50)),
      'gif': _FileIconConfig('Gf', Color(0xFF4CAF50)),
    };
    return extMap[ext] ?? const _FileIconConfig('F', Color(0xFF6D8086));
  }
}
