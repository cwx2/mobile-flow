/// file_tab_bar.dart — File tab bar (chip style).
///
/// Horizontally scrollable file tabs with switch, close, and modified indicators.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/file_icon.dart';
import '../theme/theme_extensions.dart';

/// Horizontally scrollable file tab bar with chip-style tabs.
class FileTabBar extends StatelessWidget {
  final List<String> openTabs;
  final String? currentFile;
  final Set<String> modifiedFiles;
  final ValueChanged<String> onTabTap;
  final ValueChanged<int> onTabClose;

  const FileTabBar({
    super.key,
    required this.openTabs,
    required this.currentFile,
    required this.modifiedFiles,
    required this.onTabTap,
    required this.onTabClose,
  });

  @override
  Widget build(BuildContext context) {
    if (openTabs.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: openTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final path = openTabs[index];
          final name = path.split('/').last;
          final isActive = path == currentFile;
          final isModified = modifiedFiles.contains(path);

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTabTap(path);
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              onTabClose(index);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? colors.primary.withValues(alpha: 0.15)
                    : colors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? colors.primary : colors.borderSubtle,
                  width: isActive ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modified indicator
                  if (isModified)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colors.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  FileIcon(fileName: name, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive ? colors.primary : colors.onSurface,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Close button
                  GestureDetector(
                    onTap: () => onTabClose(index),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
