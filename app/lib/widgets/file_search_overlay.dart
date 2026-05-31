/// file_search_overlay.dart — File search results overlay.
///
/// Displays filename search and content search result lists.
/// Content search groups results by file with keyword highlighting.
///
/// Used by: FilesScreen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/file_icon.dart';
import '../l10n/app_localizations.dart';
import '../services/ws_operations/file_operations.dart';
import '../theme/theme_extensions.dart';

/// Overlay that displays file search results for filename and content search.
class FileSearchOverlay extends StatelessWidget {
  final bool searching;
  final String searchText;
  final String searchMode; // 'filename' | 'content'
  final List<Map<String, dynamic>> results;
  final VoidCallback onCloseSearch;

  const FileSearchOverlay({
    super.key,
    required this.searching,
    required this.searchText,
    required this.searchMode,
    required this.results,
    required this.onCloseSearch,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    if (searching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchText.trim().isEmpty) {
      return Center(
        child: Text(
          S.of(context).fileSearchTypeToSearch,
          style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Text(
          searchMode == 'filename' ? S.of(context).fileSearchNoFileMatch : S.of(context).fileSearchNoContentMatch,
          style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
        ),
      );
    }

    if (searchMode == 'content') {
      return _buildContentResults(context, colors, typography);
    }
    return _buildFilenameResults(context, colors, typography);
  }

  Widget _buildContentResults(BuildContext context, dynamic colors, dynamic typography) {
    final grouped = _groupResultsByFile();
    final fileCount = grouped.length;
    final matchCount = results.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            S.of(context).fileSearchResultCount(fileCount, matchCount),
            style: typography.labelSmall.copyWith(color: colors.onSurfaceMuted),
          ),
        ),
        Expanded(
          child: ListView(
            children: grouped.entries.map((entry) {
              final path = entry.key;
              final matches = entry.value;
              final fileName = path.split('/').last;
              final dirPath = path.contains('/')
                  ? path.substring(0, path.lastIndexOf('/'))
                  : '';

              return ExpansionTile(
                key: PageStorageKey<String>('search_$path'),
                initiallyExpanded: true,
                leading: FileIcon(fileName: fileName, size: 20),
                title: Text(fileName, style: typography.bodyMedium),
                subtitle: dirPath.isNotEmpty
                    ? Text(
                        dirPath,
                        style: typography.labelSmall.copyWith(color: colors.onSurfaceMuted),
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${matches.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                children: matches.map((result) =>
                  _ContentResultTile(result: result, path: path, onCloseSearch: onCloseSearch),
                ).toList(),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFilenameResults(BuildContext context, dynamic colors, dynamic typography) {
    final fileCount = results.map((r) => r['path'] as String? ?? '').toSet().length;
    final matchCount = results.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            S.of(context).fileSearchResultCount(fileCount, matchCount),
            style: typography.labelSmall.copyWith(color: colors.onSurfaceMuted),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final path = results[index]['path'] as String? ?? '';
              final name = path.split('/').last;
              return ListTile(
                leading: FileIcon(fileName: name, size: 20),
                title: Text(path, style: typography.bodyMedium),
                onTap: () {
                  onCloseSearch();
                  context.read<FileOperations>().requestFileRead(path);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupResultsByFile() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final result in results) {
      final path = result['path'] as String? ?? '';
      grouped.putIfAbsent(path, () => []).add(result);
    }
    return grouped;
  }
}

/// Single match line in content search results.
class _ContentResultTile extends StatelessWidget {
  final Map<String, dynamic> result;
  final String path;
  final VoidCallback onCloseSearch;

  const _ContentResultTile({
    required this.result,
    required this.path,
    required this.onCloseSearch,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final line = result['line'] as int? ?? 0;
    final before = result['before'] as String? ?? '';
    final inside = result['inside'] as String? ?? '';
    final after = result['after'] as String? ?? '';
    final text = result['text'] as String? ?? '';
    final hasHighlight = inside.isNotEmpty;

    return InkWell(
      onTap: () {
        onCloseSearch();
        context.read<FileOperations>().requestFileRead(path);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '$line',
                style: typography.labelSmall.copyWith(color: colors.onSurfaceMuted),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: hasHighlight
                  ? RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: before,
                            style: typography.codeSmall.copyWith(color: colors.onSurface),
                          ),
                          TextSpan(
                            text: inside,
                            style: typography.codeSmall.copyWith(
                              color: colors.onPrimary,
                              backgroundColor: colors.warning.withValues(alpha: 0.6),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: after,
                            style: typography.codeSmall.copyWith(color: colors.onSurface),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      text,
                      style: typography.codeSmall.copyWith(color: colors.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
