/// app_search_sheet.dart — Top-down searchable selection panel.
///
/// Module: components/
/// Responsibility:
///   Overlay panel that slides down from the top, occupying roughly
///   the upper 40% of the screen. Contains a title, scrollable item
///   list, and a search field at the bottom of the panel. Tapping
///   outside the panel dismisses it.
///
///   The panel does NOT cover the full screen, so the keyboard does
///   not obscure the search field — it sits above the remaining space.
///
/// Usage:
/// ```dart
/// final result = await AppSearchSheet.show<String>(
///   context: context,
///   title: '选择分支',
///   items: branchNames,
///   selected: currentBranch,
///   groupFn: (name) => name.startsWith('origin/') ? '远程' : '本地',
/// );
/// ```
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';

/// Top-down searchable selection panel (upper portion of screen).
class AppSearchSheet {
  AppSearchSheet._();

  /// Show the search panel and return the selected item, or null if dismissed.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    T? selected,
    String Function(T)? displayFn,
    String Function(T)? groupFn,
    bool showClearOption = true,
    /// Fraction of screen height the panel occupies (0.0 - 1.0).
    double heightFraction = 0.45,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
      pageBuilder: (ctx, anim, secondAnim) {
        return _SearchSheetPage<T>(
          title: title,
          items: items,
          selected: selected,
          displayFn: displayFn ?? (item) => item.toString(),
          groupFn: groupFn,
          showClearOption: showClearOption,
          heightFraction: heightFraction,
        );
      },
    );
  }
}

/// Page wrapper — positions the panel at the top and handles
/// tap-outside-to-dismiss via a transparent GestureDetector.
class _SearchSheetPage<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final T? selected;
  final String Function(T) displayFn;
  final String Function(T)? groupFn;
  final bool showClearOption;
  final double heightFraction;

  const _SearchSheetPage({
    required this.title,
    required this.items,
    required this.selected,
    required this.displayFn,
    this.groupFn,
    this.showClearOption = true,
    this.heightFraction = 0.45,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final panelHeight = screenHeight * heightFraction;
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // Tap outside to dismiss
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.translucent,
          ),
        ),
        // Panel at the top
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: panelHeight + topPadding,
          child: _SearchSheetContent<T>(
            title: title,
            items: items,
            selected: selected,
            displayFn: displayFn,
            groupFn: groupFn,
            showClearOption: showClearOption,
            topPadding: topPadding,
          ),
        ),
      ],
    );
  }
}

/// Internal stateful content of the search panel.
class _SearchSheetContent<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final T? selected;
  final String Function(T) displayFn;
  final String Function(T)? groupFn;
  final bool showClearOption;
  final double topPadding;

  const _SearchSheetContent({
    required this.title,
    required this.items,
    required this.selected,
    required this.displayFn,
    this.groupFn,
    this.showClearOption = true,
    this.topPadding = 0,
  });

  @override
  State<_SearchSheetContent<T>> createState() => _SearchSheetContentState<T>();
}

class _SearchSheetContentState<T> extends State<_SearchSheetContent<T>> {
  final _searchController = TextEditingController();

  List<T> get _filtered {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return widget.items;
    return widget.items
        .where((item) => widget.displayFn(item).toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filtered = _filtered;

    return Material(
      color: colors.surfaceElevated,
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(16),
      ),
      elevation: 8,
      child: Column(
        children: [
          // Safe area top padding
          SizedBox(height: widget.topPadding),
          // Title bar with close button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
          // Clear option
          if (widget.showClearOption && widget.selected != null)
            ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -3),
              leading: Icon(Icons.clear, size: 14, color: colors.error),
              title: Text(S.of(context).componentSearchClearFilter,
                  style: TextStyle(fontSize: 12, color: colors.error)),
              onTap: () => Navigator.pop(context, null),
            ),
          // Item list (takes remaining space)
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(S.of(context).componentSearchNoMatch,
                        style: TextStyle(color: colors.onSurfaceMuted)),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (_, i) => _buildItem(filtered, i, colors),
                  ),
          ),
          // Search field at the bottom of the panel
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: S.of(context).componentSearchHint,
                hintStyle:
                    TextStyle(fontSize: 13, color: colors.onSurfaceMuted),
                prefixIcon: Icon(Icons.search, size: 18,
                    color: colors.onSurfaceMuted),
                suffixIcon: _searchController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        child: Icon(Icons.close, size: 16,
                            color: colors.onSurfaceMuted),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 12),
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(List<T> filtered, int index, dynamic colors) {
    final item = filtered[index];
    final display = widget.displayFn(item);
    final isCurrent = item == widget.selected;

    Widget? header;
    if (widget.groupFn != null) {
      final group = widget.groupFn!(item);
      final prevGroup =
          index > 0 ? widget.groupFn!(filtered[index - 1]) : null;
      if (group != prevGroup) {
        header = Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(group,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceMuted)),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null) header,
        ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -3),
          title: Text(display,
              style: TextStyle(
                fontSize: 13,
                color: isCurrent ? colors.primary : colors.onSurface,
                fontWeight:
                    isCurrent ? FontWeight.w600 : FontWeight.normal,
              )),
          trailing: isCurrent
              ? Icon(Icons.check, size: 14, color: colors.primary)
              : null,
          onTap: () => Navigator.pop(context, item),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
