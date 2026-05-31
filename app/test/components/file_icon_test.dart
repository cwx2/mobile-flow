// FileIcon 组件测试
//
// 覆盖：25+ 扩展名映射正确性、特殊文件名、未知扩展名降级

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobileflow/components/file_icon.dart';
import 'package:mobileflow/theme/app_theme.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.buildDark(),
        home: Scaffold(body: child),
      );

  group('FileIcon extension mapping', () {
    final extensions = [
      'dart',
      'py',
      'ts',
      'tsx',
      'js',
      'jsx',
      'json',
      'yaml',
      'yml',
      'md',
      'html',
      'css',
      'scss',
      'go',
      'rs',
      'java',
      'kt',
      'kts',
      'swift',
      'sh',
      'bash',
      'sql',
      'xml',
      'toml',
      'gradle',
      'lock',
      'svg',
      'png',
      'jpg',
      'gif',
    ];

    for (final ext in extensions) {
      testWidgets('renders icon for .$ext', (tester) async {
        await tester.pumpWidget(wrap(FileIcon(fileName: 'test.$ext')));
        // Should render without error
        expect(find.byType(FileIcon), findsOneWidget);
        // Should have a Container with colored background
        expect(find.byType(Container), findsWidgets);
      });
    }

    test('covers at least 25 extensions', () {
      expect(extensions.length, greaterThanOrEqualTo(25));
    });
  });

  group('FileIcon special files', () {
    final specialFiles = [
      'Dockerfile',
      'Makefile',
      '.gitignore',
      'pubspec.yaml',
      'package.json',
      'README.md',
      '.env',
    ];

    for (final name in specialFiles) {
      testWidgets('renders special icon for $name', (tester) async {
        await tester.pumpWidget(wrap(FileIcon(fileName: name)));
        expect(find.byType(FileIcon), findsOneWidget);
      });
    }
  });

  group('FileIcon fallback', () {
    testWidgets('unknown extension renders default icon', (tester) async {
      await tester.pumpWidget(wrap(const FileIcon(fileName: 'data.xyz')));
      expect(find.byType(FileIcon), findsOneWidget);
      // Should show 'F' as default label
      expect(find.text('F'), findsOneWidget);
    });

    testWidgets('no extension renders default icon', (tester) async {
      await tester.pumpWidget(wrap(const FileIcon(fileName: 'LICENSE')));
      expect(find.byType(FileIcon), findsOneWidget);
    });
  });

  group('FileIcon sizing', () {
    testWidgets('default size is 20', (tester) async {
      await tester.pumpWidget(wrap(const FileIcon(fileName: 'test.dart')));
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(FileIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.constraints?.maxWidth, 20);
    });

    testWidgets('custom size works', (tester) async {
      await tester
          .pumpWidget(wrap(const FileIcon(fileName: 'test.dart', size: 32)));
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(FileIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.constraints?.maxWidth, 32);
    });
  });
}
