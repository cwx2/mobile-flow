/// project_picker_sheet.dart — Project picker BottomSheet widget.
///
/// Module: widgets/
/// Responsibility:
///   Search-first project picker with three modes:
///   1. Recent projects (default) — shown when search is empty
///   2. Search results — replaces recent when user types (300ms debounce)
///   3. Directory browser — collapsible section with breadcrumb navigation
///   Also includes manual path input for advanced users.
///
/// Called by:
///   - SettingsScreen._showAddProjectDialog()
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../components/glass_card.dart';
import '../l10n/app_localizations.dart';
import '../models/protocol.dart';
import '../models/payloads/project_payloads.g.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../utils/logger.dart';

final _log = getLogger('ProjectPicker');

/// Project picker BottomSheet with search, recent projects, and directory browsing.
///
/// Presented as a [DraggableScrollableSheet] (half-screen default, draggable to full).
/// Listens to [WebSocketService.messageStream] for [MessageType.projectSearchResult]
/// messages and updates the UI incrementally.
class ProjectPickerSheet extends StatefulWidget {
  /// Called when the user selects a project path (tap result or "Select This Directory").
  final void Function(String path) onProjectSelected;

  const ProjectPickerSheet({super.key, required this.onProjectSelected});

  @override
  State<ProjectPickerSheet> createState() => _ProjectPickerSheetState();
}

class _ProjectPickerSheetState extends State<ProjectPickerSheet> {
  // Search state
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  // Browse state
  bool _isBrowsing = false;
  String _currentBrowsePath = '';
  List<String> _breadcrumbs = [];
  List<Map<String, dynamic>> _browseResults = [];
  bool _isBrowseLoading = false;

  // Recent projects (loaded on open)
  List<Map<String, dynamic>> _recentProjects = [];
  bool _recentLoaded = false;

  // Manual path input
  bool _showManualInput = false;
  final _manualPathController = TextEditingController();

  // Message subscription
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    _sub = ws.messageStream.listen(_onMessage);
    _log.fine('项目选择器已打开，请求最近项目列表');
    ws.projectOps.searchProjects('');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _sub?.cancel();
    _searchController.dispose();
    _manualPathController.dispose();
    super.dispose();
  }

  // ── Message handling ──

  void _onMessage(WsMessage msg) {
    if (msg.type != MessageType.projectSearchResult) return;
    final p = ProjectSearchResultPayload.fromJson(msg.payload);
    final results = p.results;
    final isBrowsing = p.isBrowsing;
    final currentPath = p.currentPath;
    if (!mounted) return;

    if (isBrowsing) {
      _log.fine('收到目录浏览结果: path=$currentPath, count=${results.length}');
      setState(() {
        _browseResults = results;
        _currentBrowsePath = currentPath;
        _breadcrumbs = _parseBreadcrumbs(currentPath);
        _isBrowseLoading = false;
      });
    } else if (_hasSearched || _searchController.text.isNotEmpty) {
      _log.fine('收到搜索结果: count=${results.length}');
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } else {
      _log.fine('收到最近项目列表: count=${results.length}');
      setState(() {
        _recentProjects = results;
        _recentLoaded = true;
      });
    }
  }

  // ── Path helpers ──

  List<String> _parseBreadcrumbs(String path) {
    if (path.isEmpty) return [];
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (normalized.startsWith('/')) {
      if (parts.isEmpty) return ['/'];
      parts[0] = '/${parts[0]}';
    }
    return parts;
  }

  String _pathFromBreadcrumbs(int index) {
    if (_breadcrumbs.isEmpty) return '';
    final segments = _breadcrumbs.sublist(0, index + 1);
    final first = segments.first;
    if (first.startsWith('/')) {
      if (segments.length == 1) return first;
      return '$first/${segments.skip(1).join('/')}';
    }
    if (first.contains(':')) {
      return segments.join('/');
    }
    return segments.join('/');
  }

  // ── Actions ──

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _log.fine('搜索项目: query=$query');
      setState(() => _hasSearched = true);
      context.read<WebSocketService>().projectOps.searchProjects(query);
    });
  }

  void _browseTo(String path) {
    _log.fine('浏览目录: path=$path');
    setState(() => _isBrowseLoading = true);
    context.read<WebSocketService>().projectOps.browseDirectory(path);
  }

  void _toggleBrowse() {
    HapticFeedback.selectionClick();
    if (_isBrowsing) {
      setState(() {
        _isBrowsing = false;
        _browseResults = [];
        _breadcrumbs = [];
        _currentBrowsePath = '';
      });
    } else {
      setState(() => _isBrowsing = true);
      // Start with filesystem roots (drives on Windows, / on Unix)
      _browseTo('');
    }
  }

  void _submitManualPath() {
    final path = _manualPathController.text.trim();
    if (path.isEmpty) return;
    _log.info('手动输入路径: path=$path');
    widget.onProjectSelected(path);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.surfaceElevated,
                colors.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: colors.scrim.withValues(alpha: isDark ? 0.4 : 0.12),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(
                    horizontal: context.spacing.md,
                  ),
                  children: [
                    if (_isBrowsing)
                      _buildBrowseSection()
                    else ...[
                      if (_hasSearched || _searchController.text.isNotEmpty)
                        _buildSearchResults()
                      else
                        _buildRecentProjects(),
                      SizedBox(height: context.spacing.lg),
                      _buildActionCards(),
                    ],
                    SizedBox(height: context.spacing.xl),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Sheet header: drag handle + title.
  Widget _buildHeader() {
    final colors = context.colors;
    final spacing = context.spacing;

    return Column(
      children: [
        SizedBox(height: spacing.sm),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colors.onSurfaceMuted.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(height: spacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_copy_outlined, size: 20, color: colors.primary),
            SizedBox(width: spacing.sm),
            Text(S.of(context).projectPickerTitle, style: context.typography.titleMedium),
          ],
        ),
        SizedBox(height: spacing.sm),
      ],
    );
  }

  /// Search bar with surfaceVariant background.
  Widget _buildSearchBar() {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.sm,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(context.radii.lg),
          border: Border.all(
            color: colors.border.withValues(alpha: 0.4),
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: colors.onSurfaceMuted, size: 20),
            SizedBox(width: spacing.sm),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: typography.bodyMedium,
                decoration: InputDecoration(
                  hintText: S.of(context).projectPickerSearchHint,
                  hintStyle: typography.bodyMedium.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: spacing.sm),
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.onSurfaceMuted.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, color: colors.onSurfaceMuted, size: 14),
                ),
              ),
            if (_isSearching)
              Padding(
                padding: EdgeInsets.only(left: spacing.sm),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Recent projects list (default view).
  Widget _buildRecentProjects() {
    final colors = context.colors;
    final spacing = context.spacing;

    if (!_recentLoaded) {
      return Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }

    if (_recentProjects.isEmpty) {
      return _buildEmptyHint(
        icon: Icons.rocket_launch_outlined,
        title: S.of(context).projectPickerFirstProject,
        description: S.of(context).projectPickerFirstProjectDesc,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(S.of(context).projectPickerRecent, Icons.history_rounded),
        SizedBox(height: spacing.xs),
        ..._recentProjects.map((p) => _buildProjectTile(p)),
      ],
    );
  }

  /// Search results list.
  Widget _buildSearchResults() {
    final colors = context.colors;
    final spacing = context.spacing;

    if (_isSearching && _searchResults.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }

    if (_hasSearched && _searchResults.isEmpty && !_isSearching) {
      return _buildEmptyHint(
        icon: Icons.search_off_rounded,
        title: S.of(context).projectPickerNoMatch,
        description: S.of(context).projectPickerNoMatchDesc,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          S.of(context).projectPickerFoundCount(_searchResults.length),
          Icons.search_rounded,
        ),
        SizedBox(height: spacing.xs),
        ..._searchResults.map((p) => _buildProjectTile(p)),
      ],
    );
  }

  /// Compact empty hint — lighter than full EmptyState, fits inside the sheet.
  Widget _buildEmptyHint({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;
    final isDark = context.isDark;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.primary.withValues(alpha: isDark ? 0.18 : 0.1),
                    colors.secondary.withValues(alpha: isDark ? 0.12 : 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(context.radii.xl),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(icon, size: 32, color: colors.primary),
            ),
            SizedBox(height: spacing.lg),
            Text(title, style: typography.titleSmall),
            SizedBox(height: spacing.xs),
            Text(
              description,
              style: typography.bodySmall.copyWith(
                color: colors.onSurfaceMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Section label with icon.
  Widget _buildSectionLabel(String text, IconData icon) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.only(left: spacing.xs, top: spacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.onSurfaceMuted),
          SizedBox(width: spacing.xs),
          Text(
            text,
            style: typography.labelMedium.copyWith(
              color: colors.onSurfaceMuted,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Single project/directory entry tile.
  Widget _buildProjectTile(Map<String, dynamic> entry) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;
    final path = entry['path'] as String? ?? '';
    final name = entry['name'] as String? ?? '';
    final projectType = entry['project_type'] as String?;
    final hasGit = entry['has_git'] as bool? ?? false;
    final exists = entry['exists'] as bool? ?? true;

    return Opacity(
      opacity: exists ? 1.0 : 0.45,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: spacing.xxs),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.radii.md),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(context.radii.md),
            onTap: exists
                ? () {
                    HapticFeedback.selectionClick();
                    _log.info('选择项目: path=$path');
                    widget.onProjectSelected(path);
                  }
                : null,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.md,
                vertical: spacing.sm,
              ),
              child: Row(
                children: [
                  // Project type icon with tinted background
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (exists
                              ? _projectTypeColor(projectType, colors)
                              : colors.onSurfaceMuted)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(context.radii.md),
                    ),
                    child: Icon(
                      _projectTypeIcon(projectType),
                      color: exists
                          ? _projectTypeColor(projectType, colors)
                          : colors.onSurfaceMuted,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  // Name + path
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: typography.bodyMedium.copyWith(
                                  color: exists
                                      ? colors.onSurface
                                      : colors.onSurfaceMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasGit) _buildBadge('git', colors.secondary),
                            if (projectType != null) ...[
                              SizedBox(width: spacing.xxs),
                              _buildBadge(
                                projectType,
                                _projectTypeColor(projectType, colors),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 2),
                        Text(
                          exists ? path : S.of(context).projectPickerDirNotExist(path),
                          style: typography.codeSmall.copyWith(
                            color: colors.onSurfaceMuted,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (exists)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.onSurfaceMuted.withValues(alpha: 0.5),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Small colored badge (git, python, node, etc.).
  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(context.radii.xs),
      ),
      child: Text(
        label,
        style: context.typography.labelSmall.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Action cards: browse + manual input, grouped in a card.
  Widget _buildActionCards() {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Browse directories
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(context.radii.lg),
                bottom: _showManualInput
                    ? Radius.zero
                    : Radius.circular(context.radii.lg),
              ),
              onTap: _toggleBrowse,
              child: Padding(
                padding: EdgeInsets.all(spacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(context.radii.sm),
                      ),
                      child: Icon(
                        Icons.folder_open_rounded,
                        color: colors.primary,
                        size: 18,
                      ),
                    ),
                    SizedBox(width: spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(S.of(context).projectPickerBrowse, style: typography.bodyMedium),
                          Text(
                            S.of(context).projectPickerBrowseDesc,
                            style: typography.labelSmall.copyWith(
                              color: colors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: colors.borderSubtle, indent: 60),
          // Manual path input toggle
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.vertical(
                top: Radius.zero,
                bottom: Radius.circular(context.radii.lg),
              ),
              onTap: () => setState(() => _showManualInput = !_showManualInput),
              child: Padding(
                padding: EdgeInsets.all(spacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(context.radii.sm),
                      ),
                      child: Icon(
                        Icons.edit_road_rounded,
                        color: colors.secondary,
                        size: 18,
                      ),
                    ),
                    SizedBox(width: spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(S.of(context).projectPickerManualInput, style: typography.bodyMedium),
                          Text(
                            S.of(context).projectPickerManualInputDesc,
                            style: typography.labelSmall.copyWith(
                              color: colors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _showManualInput
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: colors.onSurfaceMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Manual path input field (expanded)
          if (_showManualInput) ...[
            Divider(height: 1, color: colors.borderSubtle, indent: 16, endIndent: 16),
            Padding(
              padding: EdgeInsets.all(spacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualPathController,
                      style: typography.codeSmall,
                      decoration: InputDecoration(
                        hintText: '/home/user/my-project',
                        hintStyle: typography.codeSmall.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                        filled: true,
                        fillColor: colors.surfaceVariant.withValues(alpha: 0.4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(context.radii.sm),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(context.radii.sm),
                          borderSide: BorderSide(color: colors.primary, width: 1.5),
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: spacing.md,
                          vertical: spacing.sm,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _submitManualPath,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(context.radii.sm),
                        ),
                      ),
                      child: Text(S.of(context).commonAdd),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Directory browser section with breadcrumbs and subdirectory listing.
  Widget _buildBrowseSection() {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with back button
        Row(
          children: [
            GestureDetector(
              onTap: _toggleBrowse,
              child: Container(
                padding: EdgeInsets.all(spacing.xs),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(context.radii.sm),
                ),
                child: Icon(Icons.arrow_back_rounded, color: colors.onSurfaceVariant, size: 18),
              ),
            ),
            SizedBox(width: spacing.sm),
            Icon(Icons.folder_open_rounded, color: colors.primary, size: 18),
            SizedBox(width: spacing.xs),
            Text(
              S.of(context).projectPickerBrowse,
              style: typography.titleSmall,
            ),
          ],
        ),
        SizedBox(height: spacing.sm),

        // Breadcrumb navigation
        if (_breadcrumbs.isNotEmpty) _buildBreadcrumbs(),

        SizedBox(height: spacing.sm),

        if (_isBrowseLoading)
          Padding(
            padding: EdgeInsets.all(spacing.xl),
            child: Center(
              child: CircularProgressIndicator(
                color: colors.primary,
                strokeWidth: 2,
              ),
            ),
          )
        else if (_browseResults.isEmpty)
          _buildEmptyHint(
            icon: Icons.folder_off_outlined,
            title: S.of(context).projectPickerDirEmpty,
            description: S.of(context).projectPickerDirEmptyDesc,
          )
        else ...[
          ..._browseResults.map((entry) {
            final name = entry['name'] as String? ?? '';
            final path = entry['path'] as String? ?? '';
            final projectType = entry['project_type'] as String?;
            final hasGit = entry['has_git'] as bool? ?? false;

            return Container(
              margin: EdgeInsets.symmetric(vertical: spacing.xxs),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radii.md),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _browseTo(path);
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          projectType != null
                              ? _projectTypeIcon(projectType)
                              : Icons.folder_rounded,
                          color: projectType != null
                              ? _projectTypeColor(projectType, colors)
                              : colors.onSurfaceMuted,
                          size: 20,
                        ),
                        SizedBox(width: spacing.md),
                        Expanded(
                          child: Text(
                            name,
                            style: typography.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasGit) ...[
                          _buildBadge('git', colors.secondary),
                          SizedBox(width: spacing.xs),
                        ],
                        if (projectType != null) ...[
                          _buildBadge(projectType, _projectTypeColor(projectType, colors)),
                          SizedBox(width: spacing.xs),
                        ],
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: colors.onSurfaceMuted.withValues(alpha: 0.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // "Select This Directory" button
          SizedBox(height: spacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                _log.info('选择当前目录: path=$_currentBrowsePath');
                widget.onProjectSelected(_currentBrowsePath);
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(S.of(context).projectPickerSelectDir),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                elevation: 0,
                padding: EdgeInsets.symmetric(vertical: spacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Breadcrumb navigation bar for browse mode.
  Widget _buildBreadcrumbs() {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < _breadcrumbs.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.spacing.xxs),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: colors.onSurfaceMuted.withValues(alpha: 0.5),
                  ),
                ),
              GestureDetector(
                onTap: () => _browseTo(_pathFromBreadcrumbs(i)),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.spacing.sm,
                    vertical: context.spacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: i == _breadcrumbs.length - 1
                        ? colors.primary.withValues(alpha: 0.1)
                        : colors.surfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(context.radii.sm),
                  ),
                  child: Text(
                    _breadcrumbs[i],
                    style: typography.labelSmall.copyWith(
                      color: i == _breadcrumbs.length - 1
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      fontWeight: i == _breadcrumbs.length - 1
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Helpers ──

  IconData _projectTypeIcon(String? type) {
    switch (type) {
      case 'python':
        return Icons.code;
      case 'node':
        return Icons.javascript;
      case 'flutter':
        return Icons.flutter_dash;
      case 'rust':
        return Icons.settings;
      case 'go':
        return Icons.code;
      case 'java':
        return Icons.coffee;
      case 'cpp':
        return Icons.memory;
      case 'dotnet':
        return Icons.window;
      default:
        return Icons.folder_rounded;
    }
  }

  Color _projectTypeColor(String? type, dynamic colors) {
    switch (type) {
      case 'python':
        return const Color(0xFF3776AB);
      case 'node':
        return const Color(0xFF339933);
      case 'flutter':
        return const Color(0xFF02569B);
      case 'rust':
        return const Color(0xFFDEA584);
      case 'go':
        return const Color(0xFF00ADD8);
      case 'java':
        return const Color(0xFFED8B00);
      case 'cpp':
        return const Color(0xFF00599C);
      case 'dotnet':
        return const Color(0xFF512BD4);
      default:
        return colors.onSurfaceMuted as Color;
    }
  }
}
