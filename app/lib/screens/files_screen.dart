/// files_screen.dart — File browser screen.
// Lazy loading: child content is requested only when a directory is tapped.
// Features: file search, file action menu, send to AI, recent files, Git status markers.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../editor/editor.dart';

import '../components/app_dialog.dart';
import '../components/app_button.dart';
import '../components/file_icon.dart';
import '../components/workbench_state_card.dart';
import '../core/event_bus.dart';
import '../core/loading_state.dart';
import '../components/skeleton_loader.dart';
import '../models/file_node.dart';
import '../models/protocol.dart';
import '../models/send_to_ai_payload.dart';
import '../services/send_to_ai_service.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/file_operations.dart';
import '../services/ws_operations/git_operations.dart';
import '../theme/theme_extensions.dart';
import '../utils/format_utils.dart';
import '../utils/git_utils.dart';
import '../utils/language_detect.dart';
import '../utils/comment_styles.dart';
import '../widgets/file_actions_sheet.dart';
import '../widgets/file_search_overlay.dart';
import '../widgets/file_tab_bar.dart';
import '../widgets/code_editor_view.dart';
import '../widgets/editor_extra_keys.dart';
import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../models/payloads/file_payloads.g.dart';
import '../utils/logger.dart';

final _log = getLogger('FilesScreen');

/// File browser screen with tree navigation, search, editor tabs, and Git status.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> with LoadingStateMixin {
  List<FileNode> _tree = [];
  String? _currentFile;
  String? _fileContent;
  StreamSubscription? _sub;

  // Cached child directories already loaded
  final Map<String, List<FileNode>> _dirCache = {};
  final Set<String> _loadingDirs = {};
  final Set<String> _expandedDirs = {};
  int _treeRebuildKey = 0;

  // Open file tabs (ordered)
  final List<String> _openTabs = [];
  // File content cache: path -> content
  final Map<String, String> _fileCache = {};

  // ── Search state ──
  bool _searchActive = false;
  String _searchMode = 'filename'; // 'filename' | 'content'
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  Timer? _debounceTimer;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // ── Search options (regex / case-sensitive / whole word) ──
  bool _isRegex = false;
  bool _caseSensitive = false;
  bool _wholeWord = false;

  // ── Editor state ──
  bool _editing = false;
  bool _editorShowFind = false;
  // Per-tab editor controller group: each open file maintains its own
  // controller set so switching tabs preserves scroll position, undo history,
  // syntax highlighting cache, and selection state.
  final Map<String, _TabEditorState> _tabEditors = {};
  // Set of files with unsaved modifications
  final Set<String> _modifiedFiles = {};

  // ── Git status ──
  Map<String, String> _gitStatusMap = {};
  Timer? _gitRefreshTimer;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    ws.fileOps.requestFileTree(depth: 1);
    ws.gitOps.requestGitStatus();
    startLoadingTimeout();
    _sub = ws.messageStream.listen(_onMessage);
    // Re-fetch file tree when the active project changes
    final eventBus = context.read<AppEventBus>();
    eventBus.on(AppEvents.projectSwitched, (_) {
      if (mounted) {
        // Clear all data — isLoading automatically becomes true
        // because resetLoading() clears dataReceived and error.
        setState(() {
          resetLoading();
          _tree.clear();
          _openTabs.clear();
          _currentFile = null;
          _fileContent = null;
          _fileCache.clear();
          _dirCache.clear();
          _loadingDirs.clear();
          _expandedDirs.clear();
          _modifiedFiles.clear();
          _editing = false;
          _editorShowFind = false;
          _disposeAllTabEditors();
          _searchActive = false;
          _searchResults = [];
          _searching = false;
          _searchController.clear();
          _gitStatusMap = {};
        });
        startLoadingTimeout();
        // Request fresh data — fileTreeResult arrival will clear loading.
        final ws = context.read<WebSocketService>();
        if (ws.currentProjectPath.isNotEmpty) {
          ws.fileOps.requestFileTree(depth: 1);
        }
      }
    });

    // Auto-update git status markers when Agent pushes fresh state
    eventBus.on(AppEvents.gitStatusPush, (data) {
      if (!mounted) return;
      final stateData = data['data'];
      if (stateData is Map<String, dynamic>) {
        _parseGitStatus(stateData);
      }
    });
  }

  // ── Search debounce ──

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searching = true;
        _searchResults = []; // Clear old results, prepare for streaming new results
      });
      final ws = context.read<WebSocketService>();
      ws.fileOps.requestFileSearch(
        query,
        searchContent: _searchMode == 'content',
        isRegex: _isRegex,
        caseSensitive: _caseSensitive,
        wholeWord: _wholeWord,
      );
    });
  }

  // ── Close search ──

  void _closeSearch() {
    setState(() {
      _searchActive = false;
      _searchResults = [];
      _searching = false;
      _searchController.clear();
    });
  }

  // ── Git status debounced refresh ──

  void _scheduleGitRefresh() {
    _gitRefreshTimer?.cancel();
    _gitRefreshTimer = Timer(const Duration(seconds: 1), () {
      context.read<GitOperations>().requestGitStatus();
    });
  }

  void _parseGitStatus(Map<String, dynamic> payload) {
    final map = <String, String>{};
    for (final list in ['staged', 'unstaged', 'untracked']) {
      for (final item in (payload[list] as List? ?? [])) {
        if (item is Map<String, dynamic>) {
          final path = item['path'] as String? ?? '';
          final status = item['status'] as String? ?? '?';
          if (path.isNotEmpty) map[path] = status;
        }
      }
    }
    setState(() => _gitStatusMap = map);
  }

  // ── Send to AI ──

  void _sendToAI(String path) {
    SendToAiService.send(
      context,
      SendToAiPayload(
        type: SendToAiType.file,
        content: '',
        filePath: path,
        language: detectLanguage(path),
      ),
    );
  }

  // ── Message handling ──

  void _onMessage(WsMessage msg) {
    if (msg.type == MessageType.fileTreeResult) {
      final p = FileTreeResultPayload.fromJson(msg.payload);
      final data = p.data;
      final reqPath = p.reqPath.isEmpty ? '/' : p.reqPath;
      if (data.isEmpty) return;

      final nodes = data
          .map((d) => FileNode.fromJson(d))
          .toList();
      _log.fine('收到文件树: path=$reqPath, 节点数=${nodes.length}');

      setState(() {
        if (reqPath == '/' || reqPath.isEmpty) {
          _tree = nodes;
          markDataReceived();
        } else {
          _dirCache[reqPath] = nodes;
          _loadingDirs.remove(reqPath);
        }
      });
    }

    if (msg.type == MessageType.fileReadResult) {
      final p = FileReadResultPayload.fromJson(msg.payload);
      final path = p.path;
      final content = p.content;
      final error = p.error;
      if (path.isEmpty) return;
      _log.fine('收到文件内容: path=$path, size=${content?.length ?? 0}');

      // Large file or error: notify user, don't open
      if (error != null) {
        AppToast.show(context, error);
        return;
      }

      setState(() {
        if (content != null) _fileCache[path] = content;

        if (!_openTabs.contains(path)) {
          _openTabs.add(path);
          // Evict oldest unmodified tab when exceeding max to free memory.
          // Keeps modified tabs open so users don't lose unsaved work.
          _evictOldestTabIfNeeded();
        }
        _currentFile = path;
        _fileContent = content ?? _fileCache[path];

        // Create per-tab controller if this file hasn't been opened before.
        // If it already has a controller (tab was open), keep it — preserves
        // scroll position, undo history, and unsaved edits.
        if (!_tabEditors.containsKey(path)) {
          _tabEditors[path] = _TabEditorState.fromContent(_fileContent ?? '');
        }
      });
    }

    // File save result
    if (msg.type == MessageType.fileWriteResult) {
      final p = FileWriteResultPayload.fromJson(msg.payload);
      final path = p.path;
      final success = p.success;
      if (success && path.isNotEmpty && mounted) {
        setState(() {
          // Save succeeded: update cache from the tab's controller, clear modified flag
          final tabState = _tabEditors[path];
          final savedText = tabState?.codeController.text ?? '';
          _fileCache[path] = savedText;
          _modifiedFiles.remove(path);
          if (_currentFile == path) {
            _fileContent = savedText;
          }
        });
        AppToast.show(context, S.of(context).commonSaved, type: AppToastType.success);
      }
    }

    // Search results (streaming)
    if (msg.type == MessageType.fileSearchStream) {
      final p = FileSearchStreamPayload.fromJson(msg.payload);
      setState(() {
        _searchResults.addAll(
          p.results,
        );
        _searching = false;
      });
    }

    // Search complete
    if (msg.type == MessageType.fileSearchResult) {
      final p = FileSearchResultPayload.fromJson(msg.payload);
      setState(() {
        // Use final results if no streaming results arrived
        if (_searchResults.isEmpty) {
          _searchResults = p.results;
        }
        _searching = false;
      });
    }

    // File create result
    if (msg.type == MessageType.fileCreateResult) {
      final p = FileCreateResultPayload.fromJson(msg.payload);
      if (p.success) {
        _log.info('文件创建成功: ${p.path}');
        context.read<FileOperations>().requestFileTree(depth: 1);
        // Refresh affected directory
        final path = p.path ?? '';
        final parentDir =
            path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
        _dirCache.remove(parentDir);
        if (_expandedDirs.contains(parentDir)) {
          context
              .read<FileOperations>()
              .requestFileTree(path: parentDir, depth: 1);
        }
      } else {
        final error = p.error ?? S.of(context).filesCreateFailed;
        AppToast.show(context, error);
      }
    }

    // File rename result
    if (msg.type == MessageType.fileRenameResult) {
      final p = FileRenameResultPayload.fromJson(msg.payload);
      if (p.success) {
        final oldPath = p.oldPath ?? '';
        final newPath = p.newPath ?? '';
        _log.info('文件重命名成功: $oldPath → $newPath');
        context.read<FileOperations>().requestFileTree(depth: 1);
        // Update open tabs
        setState(() {
          final idx = _openTabs.indexOf(oldPath);
          if (idx >= 0) {
            _openTabs[idx] = newPath;
            if (_fileCache.containsKey(oldPath)) {
              _fileCache[newPath] = _fileCache.remove(oldPath)!;
            }
            if (_currentFile == oldPath) {
              _currentFile = newPath;
              _fileContent = _fileCache[newPath];
            }
          }
          // Clear affected directory cache
          final parentDir = oldPath.contains('/')
              ? oldPath.substring(0, oldPath.lastIndexOf('/'))
              : '';
          _dirCache.remove(parentDir);
        });
      } else {
        final error = p.error ?? S.of(context).filesRenameFailed;
        AppToast.show(context, error);
      }
    }

    // File delete result
    if (msg.type == MessageType.fileDeleteResult) {
      final p = FileDeleteResultPayload.fromJson(msg.payload);
      if (p.success) {
        final path = p.path ?? '';
        _log.info('文件删除成功: $path');
        context.read<FileOperations>().requestFileTree(depth: 1);
        setState(() {
          _openTabs.remove(path);
          _fileCache.remove(path);
          _tabEditors[path]?.dispose();
          _tabEditors.remove(path);
          _modifiedFiles.remove(path);
          if (_currentFile == path) {
            _currentFile = _openTabs.isNotEmpty ? _openTabs.last : null;
            _fileContent =
                _currentFile != null ? _fileCache[_currentFile] : null;
          }
          final parentDir = path.contains('/')
              ? path.substring(0, path.lastIndexOf('/'))
              : '';
          _dirCache.remove(parentDir);
        });
      } else {
        final error = p.error ?? S.of(context).filesDeleteFailed;
        AppToast.show(context, error);
      }
    }

    // Git status result
    if (msg.type == MessageType.gitStatusResult) {
      _parseGitStatus(msg.payload);
    }

    // File change notification
    if (msg.type == MessageType.fileChanged) {
      final p = FileChangedPayload.fromJson(msg.payload);
      final changedPath = p.path;
      final changeType = p.change;
      if (changedPath.isEmpty) return;

      // File created or deleted → refresh file tree
      if (changeType == 'created' || changeType == 'deleted') {
        final parentDir = changedPath.contains('/')
            ? changedPath.substring(0, changedPath.lastIndexOf('/'))
            : '';
        _dirCache.remove(parentDir);
        context.read<FileOperations>().requestFileTree(depth: 1);
        if (changeType == 'deleted' && _openTabs.contains(changedPath)) {
          setState(() {
            _openTabs.remove(changedPath);
            _fileCache.remove(changedPath);
            _tabEditors[changedPath]?.dispose();
            _tabEditors.remove(changedPath);
            _modifiedFiles.remove(changedPath);
            if (_currentFile == changedPath) {
              _currentFile = _openTabs.isNotEmpty ? _openTabs.last : null;
              _fileContent =
                  _currentFile != null ? _fileCache[_currentFile] : null;
            }
          });
        }
      }

      // File modified → refresh opened file content
      if (_openTabs.contains(changedPath)) {
        context.read<FileOperations>().requestFileRead(changedPath);
      }

      // Debounced git status refresh
      _scheduleGitRefresh();
    }
  }

  /// Request child directory content
  void _loadDir(String path) {
    if (_dirCache.containsKey(path) || _loadingDirs.contains(path)) return;
    _loadingDirs.add(path);
    // Defer setState to avoid calling during build phase (triggered by ExpansionTile initiallyExpanded)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    final ws = context.read<WebSocketService>();
    ws.fileOps.requestFileTree(path: path, depth: 1);
  }

  // ── File action menu ──

  void _showFileActions(String path, bool isDir) {
    showFileActionsSheet(
      context,
      path: path,
      isDir: isDir,
    );
  }

  /// AppBar create menu (create file/folder at root)
  void _showCreateMenu() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add),
              title: Text(S.of(context).filesNewFile),
              onTap: () {
                Navigator.pop(context);
                _showQuickCreateDialog('file');
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: Text(S.of(context).filesNewFolder),
              onTap: () {
                Navigator.pop(context);
                _showQuickCreateDialog('dir');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickCreateDialog(String type) async {
    final title = type == 'file' ? S.of(context).filesNewFile : S.of(context).filesNewFolder;
    final hint = type == 'file' ? S.of(context).filesNewFileHint : S.of(context).filesNewFolderHint;
    final name = await showAppInputDialog(
      context,
      title: title,
      hintText: hint,
    );
    if (name != null && name.isNotEmpty) {
      context.read<FileOperations>().createFile('', name, type);
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final ws = context.watch<WebSocketService>();

    // No project selected — show empty state with guidance
    if (ws.currentProjectPath.isEmpty) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.surface,
          toolbarHeight: 44,
          title: Text(S.of(context).filesTitle, style: typography.titleMedium),
        ),
        body: WorkbenchStateCard(
          icon: Icons.folder_off_outlined,
          badge: S.of(context).filesTreeNotReady,
          title: S.of(context).filesNoProjectTitle,
          description: S.of(context).filesNoProjectDescription,
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: _searchActive && _currentFile == null
          ? _buildSearchAppBar(colors, typography)
          : _buildNormalAppBar(colors, typography),
      body: Column(
        children: [
          // Tab bar (slides out when searching to save screen space)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _openTabs.isNotEmpty && !_editorShowFind
                ? FileTabBar(
                    openTabs: _openTabs,
                    currentFile: _currentFile,
                    modifiedFiles: _modifiedFiles,
                    onTabTap: _onTabTap,
                    onTabClose: _onTabClose,
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
          // Main content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: _currentFile != null
                  ? Column(
                      key: ValueKey('viewer:$_currentFile'),
                      children: [
                        Expanded(child: _buildFileViewer()),
                        // Smooth slide-in/out for editor extra keys bar
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.bottomCenter,
                          child: _editing && _currentTabEditor != null
                              ? EditorExtraKeys(
                                  controller: _currentTabEditor!.codeController,
                                  onToggleFind: _toggleEditorFind,
                                  commentFormatter: _buildCommentFormatter(),
                                )
                              : const SizedBox(width: double.infinity, height: 0),
                        ),
                      ],
                    )
                  : _searchActive
                      ? FileSearchOverlay(
                          key: const ValueKey('search'),
                          searching: _searching,
                          searchText: _searchController.text,
                          searchMode: _searchMode,
                          results: _searchResults,
                          onCloseSearch: _closeSearch,
                        )
                      : Column(
                          key: const ValueKey('tree'),
                          children: [
                            Expanded(child: _buildFileTree()),
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }

  /// Normal AppBar
  PreferredSizeWidget _buildNormalAppBar(dynamic colors, dynamic typography) {
    return AppBar(
      backgroundColor: colors.surface,
      toolbarHeight: 44,
      title: _currentFile != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_currentFile!.split('/').last,
                    style: typography.titleMedium),
                Text(_currentFile!,
                    style: typography.codeSmall
                        .copyWith(color: colors.onSurfaceMuted),
                    overflow: TextOverflow.ellipsis),
              ],
            )
          : Text(S.of(context).filesTitle, style: typography.titleMedium),
      titleSpacing: 4,
      leading: _currentFile != null
          ? IconButton(
              icon: Icon(Icons.arrow_back, color: colors.onSurfaceVariant),
              onPressed: () async {
                if (_currentFile != null) {
                  final canLeave = await _checkUnsavedChanges(_currentFile!);
                  if (!canLeave) return;
                }
                setState(() {
                  _currentFile = null;
                  _fileContent = null;
                  _editing = false;
                  _editorShowFind = false;
                });
              },
            )
          : null,
      actions: [
        // Edit mode: undo/redo
        if (_currentFile != null && _editing && _currentTabEditor != null) ...[
          IconButton(
            icon: Icon(Icons.undo,
                color: _currentTabEditor!.codeController.canUndo
                    ? colors.onSurfaceVariant
                    : colors.borderSubtle),
            tooltip: S.of(context).filesUndo,
            onPressed: _currentTabEditor!.codeController.canUndo
                ? () {
                    _currentTabEditor!.codeController.undo();
                    setState(() {});
                  }
                : null,
          ),
          IconButton(
            icon: Icon(Icons.redo,
                color: _currentTabEditor!.codeController.canRedo
                    ? colors.onSurfaceVariant
                    : colors.borderSubtle),
            tooltip: S.of(context).filesRedo,
            onPressed: _currentTabEditor!.codeController.canRedo
                ? () {
                    _currentTabEditor!.codeController.redo();
                    setState(() {});
                  }
                : null,
          ),
        ],
        // File view mode: save button (shown only in edit mode with modifications)
        if (_currentFile != null &&
            _editing &&
            _modifiedFiles.contains(_currentFile))
          IconButton(
            icon: Icon(Icons.save, color: colors.success),
            tooltip: S.of(context).filesSave,
            onPressed: _saveCurrentFile,
          ),
        // File view mode: search button
        if (_currentFile != null)
          IconButton(
            icon: Icon(
              Icons.search,
              color: _editorShowFind ? colors.warning : colors.onSurfaceVariant,
            ),
            tooltip: S.of(context).filesSearch,
            onPressed: _toggleEditorFind,
          ),
        // File view mode: edit/view toggle
        if (_currentFile != null)
          IconButton(
            icon: Icon(
              _editing ? Icons.visibility : Icons.edit,
              color: _editing ? colors.warning : colors.onSurfaceVariant,
            ),
            tooltip: _editing ? S.of(context).filesViewMode : S.of(context).filesEditMode,
            onPressed: () => setState(() => _editing = !_editing),
          ),
        // File view mode: send to AI button
        if (_currentFile != null)
          IconButton(
            icon: Icon(Icons.smart_toy, color: colors.onSurfaceVariant),
            tooltip: S.of(context).filesSendToAi,
            onPressed: () => _sendToAI(_currentFile!),
          ),
        // File tree mode: tool buttons
        if (_currentFile == null) ...[
          IconButton(
            icon: Icon(Icons.note_add_outlined,
                color: colors.onSurfaceVariant, size: 22),
            tooltip: S.of(context).filesNew,
            onPressed: () => _showCreateMenu(),
          ),
          IconButton(
            icon: Icon(Icons.unfold_less,
                color: colors.onSurfaceVariant, size: 22),
            tooltip: S.of(context).filesCollapseAll,
            onPressed: () {
              setState(() {
                _expandedDirs.clear();
                _treeRebuildKey++;
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: colors.onSurfaceVariant, size: 22),
            tooltip: S.of(context).filesRefresh,
            onPressed: () {
              setState(() {
                _dirCache.clear();
                resetLoading();
              });
              startLoadingTimeout();
              context.read<FileOperations>().requestFileTree(depth: 1);
              context.read<GitOperations>().requestGitStatus();
            },
          ),
          IconButton(
            icon: Icon(Icons.search, color: colors.onSurfaceVariant),
            tooltip: S.of(context).filesSearch,
            onPressed: () {
              setState(() => _searchActive = true);
              Future.delayed(const Duration(milliseconds: 100), () {
                _searchFocusNode.requestFocus();
              });
            },
          ),
        ],
      ],
    );
  }

  /// Search mode AppBar
  PreferredSizeWidget _buildSearchAppBar(dynamic colors, dynamic typography) {
    return AppBar(
      backgroundColor: colors.surface,
      toolbarHeight: 44,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: colors.onSurfaceVariant, size: 20),
        onPressed: _closeSearch,
      ),
      title: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              // Left: mode toggle + option buttons (inside the field)
              const SizedBox(width: 4),
              _buildModeChip(
                label: S.of(context).filesSearchFileTab,
                active: _searchMode == 'filename',
                onTap: () => _switchSearchMode('filename'),
                colors: colors,
                typography: typography,
                isLeft: true,
              ),
              _buildModeChip(
                label: S.of(context).filesSearchContentTab,
                active: _searchMode == 'content',
                onTap: () => _switchSearchMode('content'),
                colors: colors,
                typography: typography,
                isLeft: false,
              ),
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: colors.borderSubtle,
              ),
              _buildSearchOptionButton(
                label: '.*',
                active: _isRegex,
                tooltip: S.of(context).filesSearchRegex,
                onTap: () {
                  setState(() => _isRegex = !_isRegex);
                  if (_searchController.text.trim().isNotEmpty) {
                    _onSearchChanged(_searchController.text);
                  }
                },
                colors: colors,
              ),
              _buildSearchOptionButton(
                label: 'Aa',
                active: _caseSensitive,
                tooltip: S.of(context).filesSearchCaseSensitive,
                onTap: () {
                  setState(() => _caseSensitive = !_caseSensitive);
                  if (_searchController.text.trim().isNotEmpty) {
                    _onSearchChanged(_searchController.text);
                  }
                },
                colors: colors,
              ),
              _buildSearchOptionButton(
                label: 'ab',
                active: _wholeWord,
                tooltip: S.of(context).filesSearchWholeWord,
                underline: true,
                onTap: () {
                  setState(() => _wholeWord = !_wholeWord);
                  if (_searchController.text.trim().isNotEmpty) {
                    _onSearchChanged(_searchController.text);
                  }
                },
                colors: colors,
              ),
              const SizedBox(width: 4),
              // Thin divider between controls and input
              Container(
                width: 1,
                height: 16,
                color: colors.borderSubtle,
              ),
              // Right: search input (takes remaining space)
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  style: typography.bodyMedium,
                  decoration: InputDecoration(
                    hintText: _searchMode == 'filename'
                        ? S.of(context).filesSearchFilename
                        : S.of(context).filesSearchContent,
                    hintStyle: typography.bodyMedium
                        .copyWith(color: colors.onSurfaceMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Switch search mode and re-trigger search if input is non-empty.
  void _switchSearchMode(String mode) {
    setState(() => _searchMode = mode);
    if (_searchController.text.trim().isNotEmpty) {
      _onSearchChanged(_searchController.text);
    }
  }

  /// Mode chip for the filename/content toggle.
  Widget _buildModeChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
    required dynamic colors,
    required dynamic typography,
    required bool isLeft,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colors.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: typography.labelSmall.copyWith(
            color: active ? colors.primary : colors.onSurfaceMuted,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Toggle button for search options (case, word, regex)
  Widget _buildSearchOptionButton({
    required String label,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
    required dynamic colors,
    bool underline = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          width: 28,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active
                ? colors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? colors.primary : colors.onSurfaceMuted,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: active ? colors.primary : colors.onSurfaceMuted,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  // ── Tab action callbacks ──

  void _onTabTap(String path) {
    setState(() {
      _currentFile = path;
      _fileContent = _fileCache[path];
      _editorShowFind = false;
      _currentTabEditor?.findController.close();
    });
    // Mark as recently accessed for LRU eviction
    _tabEditors[path]?.touch();
    if (_fileCache[path] == null) {
      context.read<FileOperations>().requestFileRead(path);
    }
  }

  Future<void> _onTabClose(int index) async {
    final path = _openTabs[index];
    final canClose = await _checkUnsavedChanges(path);
    if (!canClose) return;
    setState(() {
      _openTabs.removeAt(index);
      // Dispose the closed tab's controllers to free memory
      _tabEditors[path]?.dispose();
      _tabEditors.remove(path);
      _modifiedFiles.remove(path);
      if (_currentFile == path) {
        if (_openTabs.isNotEmpty) {
          final newIndex = index < _openTabs.length ? index : index - 1;
          _currentFile = _openTabs[newIndex];
          _fileContent = _fileCache[_currentFile];
        } else {
          _currentFile = null;
          _fileContent = null;
          _editing = false;
          _editorShowFind = false;
        }
      }
    });
  }

  // ── File tree ──

  Widget _buildFileTree() {
    if (isLoading) {
      return Padding(
        padding: EdgeInsets.all(context.spacing.lg),
        child: const SkeletonLoader(lines: 8, lineHeight: 24),
      );
    }
    if (loadingError.isNotEmpty) {
      return WorkbenchStateCard(
        icon: Icons.error_outline,
        tint: context.colors.error,
        title: S.of(context).filesLoadFailed,
        description: loadingError,
        action: AppButton(
          label: S.of(context).commonRetry,
          icon: Icons.refresh_rounded,
          onTap: () {
            setState(() => resetLoading());
            startLoadingTimeout();
            context.read<FileOperations>().requestFileTree(depth: 1);
          },
        ),
      );
    }
    if (_tree.isEmpty) {
      return Center(
          child: Text(S.of(context).filesNoFiles,
              style: context.typography.bodySmall
                  .copyWith(color: context.colors.onSurfaceMuted)));
    }
    return ListView(
      key: ValueKey(_treeRebuildKey),
      children: _tree.map((node) => _buildTreeNode(node, 0, '')).toList(),
    );
  }

  Widget _buildTreeNode(FileNode node, int depth, String parentPath) {
    final fullPath =
        parentPath.isEmpty ? node.name : '$parentPath/${node.name}';

    if (node.isDir) {
      final cachedChildren = _dirCache[fullPath];
      final isLoading = _loadingDirs.contains(fullPath);
      final folderChanges = countFolderChanges(fullPath, _gitStatusMap);

      return _wrapWithIndentGuides(
        depth: depth,
        child: GestureDetector(
          onLongPress: () => _showFileActions(fullPath, true),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: PageStorageKey<String>('${_treeRebuildKey}_$fullPath'),
              leading: Icon(
                _expandedDirs.contains(fullPath)
                    ? Icons.folder_open
                    : Icons.folder,
                color: context.colors.warning,
                size: 20,
              ),
              title: Row(
                children: [
                  Expanded(
                    child:
                        Text(node.name, style: context.typography.bodyMedium),
                  ),
                  if (folderChanges > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        '($folderChanges)',
                        style: context.typography.labelSmall.copyWith(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              tilePadding: EdgeInsets.only(left: 12.0 + depth * 20),
              initiallyExpanded: _expandedDirs.contains(fullPath),
              onExpansionChanged: (expanded) {
                if (expanded) {
                  _expandedDirs.add(fullPath);
                  _loadDir(fullPath);
                } else {
                  _expandedDirs.remove(fullPath);
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              },
              children: isLoading
                  ? [
                      Padding(
                        padding: EdgeInsets.only(left: 32.0 + depth * 20),
                        child: const SkeletonLoader(lines: 3, lineHeight: 18),
                      ),
                    ]
                  : (cachedChildren ?? node.children ?? [])
                      .map(
                          (child) => _buildTreeNode(child, depth + 1, fullPath))
                      .toList(),
            ),
          ),
        ),
      );
    }

    // File node
    final gitStatus = _gitStatusMap[fullPath];

    return _wrapWithIndentGuides(
      depth: depth,
      child: ListTile(
        contentPadding: EdgeInsets.only(left: 12.0 + depth * 20),
        leading: FileIcon(fileName: node.name, size: 20),
        title: Text(node.name, style: context.typography.bodyMedium),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (gitStatus != null) _buildGitStatusMarker(gitStatus),
            if (node.size != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  formatFileSize(node.size!),
                  style: context.typography.labelSmall.copyWith(
                    color: context.colors.onSurfaceMuted,
                  ),
                ),
              ),
          ],
        ),
        onTap: () {
          HapticFeedback.lightImpact();
          final ws = context.read<WebSocketService>();
          ws.fileOps.requestFileRead(fullPath);
        },
        onLongPress: () => _showFileActions(fullPath, false),
      ),
    );
  }

  /// Draw indent guide lines (vertical lines) to the left of tree nodes
  Widget _wrapWithIndentGuides({required int depth, required Widget child}) {
    if (depth == 0) return child;
    final lineColor = context.colors.onSurfaceMuted.withValues(alpha: 0.3);
    return Stack(
      children: [
        child,
        for (int i = 0; i < depth; i++)
          Positioned(
            left: 22.0 + i * 20,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: lineColor),
          ),
      ],
    );
  }

  // ── Git status marker widget ──

  Widget _buildGitStatusMarker(String status) {
    final (label, color) = switch (status) {
      'M' => ('M', Colors.orange),
      'A' => ('A', Colors.green),
      'D' => ('D', Colors.red),
      '?' => ('?', Colors.grey),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ── Editor operations ──

  /// Toggle the in-editor find/replace bar.
  void _toggleEditorFind() {
    setState(() => _editorShowFind = !_editorShowFind);
    if (_editorShowFind) {
      _currentTabEditor?.findController.findMode();
    } else {
      _currentTabEditor?.findController.close();
    }
  }

  /// Get the current tab's editor state, or null if no file is open.
  _TabEditorState? get _currentTabEditor =>
      _currentFile != null ? _tabEditors[_currentFile] : null;

  /// Build comment formatter for the current file's language.
  CodeCommentFormatter? _buildCommentFormatter() {
    if (_currentFile == null) return null;
    return buildCommentFormatter(detectLanguage(_currentFile!));
  }

  /// Save current file
  void _saveCurrentFile() {
    if (_currentFile == null) return;
    final ws = context.read<WebSocketService>();
    ws.fileOps.writeFile(_currentFile!, _currentTabEditor?.codeController.text ?? '');
  }

  /// Unsaved changes guard: returns true if safe to proceed
  Future<bool> _checkUnsavedChanges(String path) async {
    if (!_modifiedFiles.contains(path)) return true;
    final result = await showAppSaveDialog(
      context,
      title: S.of(context).filesUnsavedTitle,
      message: S.of(context).filesUnsavedMessage(path.split('/').last),
    );
    if (result == 'save') {
      final ws = context.read<WebSocketService>();
      final content = _tabEditors[path]?.codeController.text ?? '';
      ws.fileOps.writeFile(path, content);
      return true;
    }
    if (result == 'discard') {
      setState(() {
        // Re-create the tab's controller from the original server content
        // to discard unsaved edits
        _tabEditors[path]?.dispose();
        _tabEditors[path] = _TabEditorState.fromContent(_fileCache[path] ?? '');
        _modifiedFiles.remove(path);
      });
      return true;
    }
    return false;
  }

  // ── File viewer ──

  Widget _buildFileViewer() {
    if (_fileContent == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Get or create per-tab controller group
    final tabState = _tabEditors.putIfAbsent(
      _currentFile!,
      () => _TabEditorState.fromContent(_fileContent!),
    );

    return CodeEditorView(
      controller: tabState.codeController,
      scrollController: tabState.scrollController,
      findController: tabState.findController,
      showFind: _editorShowFind,
      onFindClose: () => setState(() => _editorShowFind = false),
      filePath: _currentFile ?? '',
      readOnly: !_editing,
      onChanged: (_) {
        if (_currentFile != null && _editing) {
          final currentText = tabState.codeController.text;
          final originalText = _fileCache[_currentFile] ?? '';
          final wasModified = _modifiedFiles.contains(_currentFile);
          final isModified = currentText != originalText;
          if (isModified != wasModified) {
            setState(() {
              if (isModified) {
                _modifiedFiles.add(_currentFile!);
              } else {
                _modifiedFiles.remove(_currentFile!);
              }
            });
          }
        }
      },
    );
  }

  @override
  void dispose() {
    disposeLoading();
    _sub?.cancel();
    _debounceTimer?.cancel();
    _gitRefreshTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _disposeAllTabEditors();
    super.dispose();
  }

  /// Dispose all per-tab editor controllers.
  void _disposeAllTabEditors() {
    for (final state in _tabEditors.values) {
      state.dispose();
    }
    _tabEditors.clear();
  }

  /// Maximum number of open tabs before auto-eviction kicks in.
  static const _maxTabs = 15;

  /// Evict the least recently used unmodified tab when exceeding [_maxTabs].
  ///
  /// LRU algorithm: finds the tab with the oldest [lastAccessed] timestamp
  /// among tabs that are not the current file and have no unsaved edits.
  /// Disposes its controllers and removes it from the tab list.
  void _evictOldestTabIfNeeded() {
    if (_openTabs.length <= _maxTabs) return;

    String? victim;
    DateTime? oldestTime;

    for (final tab in _openTabs) {
      // Don't evict the current file or files with unsaved edits
      if (tab == _currentFile || _modifiedFiles.contains(tab)) continue;
      final state = _tabEditors[tab];
      final accessed = state?.lastAccessed ?? DateTime(2000);
      if (oldestTime == null || accessed.isBefore(oldestTime)) {
        oldestTime = accessed;
        victim = tab;
      }
    }

    if (victim != null) {
      _openTabs.remove(victim);
      _tabEditors[victim]?.dispose();
      _tabEditors.remove(victim);
      _fileCache.remove(victim);
    }
  }
}

/// Per-tab editor controller group.
///
/// Each open file tab maintains its own set of controllers so that
/// switching tabs preserves scroll position, undo/redo history,
/// syntax highlighting cache, and selection state — no re-parsing needed.
class _TabEditorState {
  final CodeLineEditingController codeController;
  final CodeScrollController scrollController;
  final CodeFindController findController;

  /// Last time this tab was accessed (switched to). Used by LRU eviction
  /// to determine which tab to close when exceeding the max tab limit.
  DateTime lastAccessed;

  _TabEditorState._(this.codeController, this.scrollController, this.findController)
      : lastAccessed = DateTime.now();

  /// Create a new tab editor state from file content.
  factory _TabEditorState.fromContent(String content) {
    final code = CodeLineEditingController.fromText(content);
    final scroll = CodeScrollController();
    final find = CodeFindController(code);
    return _TabEditorState._(code, scroll, find);
  }

  /// Mark this tab as recently accessed.
  void touch() {
    lastAccessed = DateTime.now();
  }

  void dispose() {
    codeController.dispose();
    scrollController.dispose();
    findController.dispose();
  }
}
