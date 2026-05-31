/// git_log_tab.dart — Git commit history list with search, filters, and pagination.
///
/// Module: widgets/
/// Responsibility:
///   Displays the commit log with hash, message, author, and date.
///   Supports searching by message/author, structured filters (branch,
///   author, date range) via horizontal chip bar, infinite scroll
///   pagination, and tapping a commit to view its details.
///
///   Each filter chip opens its own focused bottom sheet with search.
///   Selections apply immediately — no "apply" button needed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../animation/page_transition_builder.dart';
import '../components/app_bottom_sheet.dart';
import '../components/app_search_sheet.dart';
import '../l10n/app_localizations.dart';
import '../models/payloads/git_payloads.g.dart';
import '../models/protocol.dart';
import '../screens/commit_detail_screen.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/git_operations.dart';
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';

// ignore: unused_element
final _log = getLogger('GitLogTab');

/// Git log tab: searchable, filterable, paginated commit list.
class GitLogTab extends StatefulWidget {
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> branches;
  final ValueChanged<int>? onCountChanged;

  const GitLogTab({
    super.key,
    required this.entries,
    this.branches = const [],
    this.onCountChanged,
  });

  @override
  State<GitLogTab> createState() => _GitLogTabState();
}

class _GitLogTabState extends State<GitLogTab> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  StreamSubscription? _sub;

  // Filter state
  String _filterBranch = '';
  String _filterAuthor = '';
  String _filterSince = '';
  String _filterUntil = '';
  List<String> _availableAuthors = [];
  bool get _hasFilters =>
      _filterBranch.isNotEmpty || _filterAuthor.isNotEmpty ||
      _filterSince.isNotEmpty || _filterUntil.isNotEmpty;
  bool get _hasActiveQuery =>
      _searchController.text.trim().isNotEmpty || _hasFilters;

  // Pagination state
  bool _loadingMore = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _allEntries = [];

  List<Map<String, dynamic>> get _displayEntries => _allEntries;

  @override
  void initState() {
    super.initState();
    _allEntries = List.of(widget.entries);
    _scrollController.addListener(_onScroll);
    final ws = context.read<WebSocketService>();
    _sub = ws.messageStream.listen(_onMessage);
    // Notify parent of initial count so tab title is accurate from the start
    _notifyCount();
  }

  @override
  void didUpdateWidget(GitLogTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries != oldWidget.entries && !_hasActiveQuery) {
      _allEntries = List.of(widget.entries);
      _hasMore = true;
      _notifyCount();
    }
  }

  /// Notify parent of the current entry count after the current build frame.
  ///
  /// Uses [addPostFrameCallback] because this is often called from
  /// [didUpdateWidget] or [_onMessage] during the build phase, where
  /// calling the parent's setState directly would crash.
  void _notifyCount() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCountChanged?.call(_allEntries.length);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore && _hasMore) {
      _loadMore();
    }
  }

  void _loadMore() {
    setState(() => _loadingMore = true);
    context.read<GitOperations>().gitLogSearch(
      query: _searchController.text.trim(),
      skip: _allEntries.length,
      branch: _filterBranch, author: _filterAuthor,
      since: _filterSince, until: _filterUntil,
    );
  }

  /// Reload from scratch with current search + filters.
  void _reloadWithFilters() {
    setState(() {
      _allEntries.clear();
      _hasMore = true;
      _loadingMore = true;
    });
    context.read<GitOperations>().gitLogSearch(
      query: _searchController.text.trim(),
      skip: 0,
      branch: _filterBranch, author: _filterAuthor,
      since: _filterSince, until: _filterUntil,
    );
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _reloadWithFilters();
    });
  }

  void _onMessage(WsMessage msg) {
    if (!mounted) return;
    if (msg.type == MessageType.gitLogSearchResult) {
      final p = GitLogSearchResultPayload.fromJson(msg.payload);
      setState(() {
        _allEntries.addAll(p.entries);
        _hasMore = p.hasMore;
        _loadingMore = false;
      });
      _notifyCount();
    }
    if (msg.type == MessageType.gitLogAuthorsResult) {
      final p = GitLogAuthorsResultPayload.fromJson(msg.payload);
      setState(() => _availableAuthors = p.authors);
    }
  }

  void _openCommitDetail(Map<String, dynamic> entry) {
    final hash = entry['hash'] as String? ?? '';
    if (hash.isEmpty) return;
    Navigator.push(context, AppPageRoute(
      type: PageTransitionType.slideUp,
      page: CommitDetailScreen(
        commitHash: hash,
        shortHash: entry['short_hash'] as String? ?? '',
        message: entry['message'] as String? ?? '',
      ),
    ));
  }

  // ── Filter chip pickers ──

  void _pickBranch() async {
    final branchNames = <String>[];
    final branchGroups = <String, String>{};
    for (final b in widget.branches) {
      final name = b['name'] as String? ?? '';
      if (name.isEmpty) continue;
      branchNames.add(name);
      branchGroups[name] = b['remote'] == true ? S.of(context).gitLogRemote : S.of(context).gitLogLocal;
    }

    final result = await AppSearchSheet.show<String>(
      context: context,
      title: S.of(context).gitLogSelectBranch,
      items: branchNames,
      selected: _filterBranch.isEmpty ? null : _filterBranch,
      groupFn: (name) => branchGroups[name] ?? '',
    );

    // null with selected = clear, null without selected = dismissed
    if (result == null && _filterBranch.isNotEmpty) {
      setState(() => _filterBranch = '');
      _hasFilters ? _reloadWithFilters() : _restoreDefaults();
    } else if (result != null && result != _filterBranch) {
      setState(() => _filterBranch = result);
      _reloadWithFilters();
    }
  }

  void _pickAuthor() async {
    if (_availableAuthors.isEmpty) {
      context.read<GitOperations>().gitLogAuthors();
    }

    final result = await AppSearchSheet.show<String>(
      context: context,
      title: S.of(context).gitLogSelectAuthor,
      items: _availableAuthors,
      selected: _filterAuthor.isEmpty ? null : _filterAuthor,
    );

    if (result == null && _filterAuthor.isNotEmpty) {
      setState(() => _filterAuthor = '');
      _hasFilters ? _reloadWithFilters() : _restoreDefaults();
    } else if (result != null && result != _filterAuthor) {
      setState(() => _filterAuthor = result);
      _reloadWithFilters();
    }
  }

  /// Restore default entries when all filters are cleared.
  void _restoreDefaults() {
    setState(() {
      _allEntries = List.of(widget.entries);
      _hasMore = true;
    });
    _notifyCount();
  }

  void _pickDateRange() {
    final colors = context.colors;
    // Preset date options for quick selection
    final presets = <String, String>{
      S.of(context).gitLogToday: _formatDate(DateTime.now()),
      S.of(context).gitLogLast7Days: _formatDate(DateTime.now().subtract(const Duration(days: 7))),
      S.of(context).gitLogLast30Days: _formatDate(DateTime.now().subtract(const Duration(days: 30))),
      S.of(context).gitLogLast90Days: _formatDate(DateTime.now().subtract(const Duration(days: 90))),
    };

    AppBottomSheet.show(context, builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(S.of(context).gitLogSelectDateRange,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          // Quick presets
          ...presets.entries.map((e) => ListTile(
            dense: true,
            title: Text(e.key, style: const TextStyle(fontSize: 14)),
            trailing: _filterSince == e.value
                ? Icon(Icons.check, size: 18, color: colors.primary)
                : null,
            onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _filterSince = e.value;
                _filterUntil = '';
              });
              _reloadWithFilters();
            },
          )),
          const Divider(height: 1),
          // Custom range
          ListTile(
            dense: true,
            leading: Icon(Icons.date_range, size: 18,
                color: colors.onSurfaceVariant),
            title: Text(S.of(context).gitLogCustomRange, style: TextStyle(fontSize: 14)),
            onTap: () async {
              Navigator.pop(ctx);
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
                initialDateRange: _filterSince.isNotEmpty
                    ? DateTimeRange(
                        start: DateTime.tryParse(_filterSince) ?? DateTime.now().subtract(const Duration(days: 30)),
                        end: DateTime.tryParse(_filterUntil.isNotEmpty ? _filterUntil : _formatDate(DateTime.now())) ?? DateTime.now(),
                      )
                    : null,
              );
              if (range != null) {
                setState(() {
                  _filterSince = _formatDate(range.start);
                  _filterUntil = _formatDate(range.end);
                });
                _reloadWithFilters();
              }
            },
          ),
          // Clear
          if (_filterSince.isNotEmpty || _filterUntil.isNotEmpty)
            ListTile(
              dense: true,
              leading: Icon(Icons.clear, size: 18, color: colors.error),
              title: Text(S.of(context).gitLogClearDateFilter,
                  style: TextStyle(fontSize: 14, color: colors.error)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                    _filterSince = ''; _filterUntil = '';
                });
                if (_hasFilters) {
                  _reloadWithFilters();
                } else {
                  _restoreDefaults();
                }
              },
            ),
          const SizedBox(height: 8),
        ],
      );
    });
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Date chip display text.
  String get _dateChipLabel {
    if (_filterSince.isNotEmpty && _filterUntil.isNotEmpty) {
      return '$_filterSince ~ $_filterUntil';
    }
    if (_filterSince.isNotEmpty) return '${S.of(context).gitLogFrom} $_filterSince';
    if (_filterUntil.isNotEmpty) return '${S.of(context).gitLogUntil} $_filterUntil';
    return S.of(context).gitLogDate;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = _displayEntries;

    return Column(
      children: [
        // Search bar + filter chips in one row
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              // Search field takes remaining space
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: S.of(context).gitLogSearchCommit,
                    hintStyle: TextStyle(
                        fontSize: 13, color: colors.onSurfaceMuted),
                    prefixIcon: Icon(Icons.search, size: 18,
                        color: colors.onSurfaceMuted),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                            child: Icon(Icons.close, size: 16,
                                color: colors.onSurfaceMuted),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 4, horizontal: 12),
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                ),
              ),
              const SizedBox(width: 6),
              // Filter chips (scrollable if they overflow)
              _FilterChip(
                label: _filterBranch.isEmpty ? S.of(context).gitLogBranch : _filterBranch,
                isActive: _filterBranch.isNotEmpty,
                onTap: _pickBranch,
                onClear: _filterBranch.isEmpty ? null : () {
                  setState(() => _filterBranch = '');
                  _hasFilters ? _reloadWithFilters() : _restoreDefaults();
                },
              ),
              const SizedBox(width: 4),
              _FilterChip(
                label: _filterAuthor.isEmpty ? S.of(context).gitLogAuthor : _filterAuthor,
                isActive: _filterAuthor.isNotEmpty,
                onTap: _pickAuthor,
                onClear: _filterAuthor.isEmpty ? null : () {
                  setState(() => _filterAuthor = '');
                  _hasFilters ? _reloadWithFilters() : _restoreDefaults();
                },
              ),
              const SizedBox(width: 4),
              _FilterChip(
                label: (_filterSince.isEmpty && _filterUntil.isEmpty)
                    ? S.of(context).gitLogDate : _dateChipLabel,
                isActive: _filterSince.isNotEmpty || _filterUntil.isNotEmpty,
                onTap: _pickDateRange,
                onClear: (_filterSince.isEmpty && _filterUntil.isEmpty) ? null : () {
                  setState(() { _filterSince = ''; _filterUntil = ''; });
                  if (_hasFilters) { _reloadWithFilters(); } else {
                    setState(() { _allEntries = List.of(widget.entries); _hasMore = true; });
                  }
                },
              ),
            ],
          ),
        ),
        // Commit list
        Expanded(
          child: entries.isEmpty && !_loadingMore
              ? Center(
                  child: Text(
                    _hasActiveQuery ? S.of(context).gitLogNoMatchingCommits
                        : _hasFilters ? S.of(context).gitLogNoFilteredCommits
                        : S.of(context).gitLogNoHistory,
                    style: TextStyle(color: colors.onSurfaceMuted),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: entries.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == entries.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )),
                      );
                    }
                    return _buildCommitItem(entries[i], colors);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCommitItem(Map<String, dynamic> entry, dynamic colors) {
    final hash = entry['short_hash'] as String? ?? '';
    final message = entry['message'] as String? ?? '';
    final author = entry['author'] as String? ?? '';
    final date = entry['date'] as String? ?? '';

    return InkWell(
      onTap: () => _openCommitDetail(entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(hash,
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace',
                      color: colors.warning)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: const TextStyle(fontSize: 13),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('$author · $date',
                      style: TextStyle(fontSize: 10,
                          color: colors.onSurfaceMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16,
                color: colors.onSurfaceMuted),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}


/// Compact filter chip with active/inactive states.
///
/// When active (filter applied), shows primary color background and
/// a close button. When inactive, shows subtle border. Tapping opens
/// the corresponding picker.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? colors.primary.withValues(alpha: 0.12)
              : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? colors.primary.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isActive)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.expand_more, size: 14,
                    color: colors.onSurfaceMuted),
              ),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? colors.primary : colors.onSurfaceVariant,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 14,
                    color: isActive ? colors.primary : colors.onSurfaceMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
