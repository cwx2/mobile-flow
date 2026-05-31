/// terminal_screen.dart — Terminal emulator screen.
///
/// Module: screens/
/// Responsibility:
///   Full terminal emulator with state-machine lifecycle management.
///   xterm TerminalView auto-adapts to screen size. macOS-style title bar
///   (tri-color dots), rounded terminal container, onboarding page.
///   Text selection via TerminalController with floating copy toolbar.
///   Uses design system tokens instead of hard-coded colors.
///
/// Called by:
///   - HomeScreen bottom navigation terminal tab
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../components/app_bottom_sheet.dart';
import '../components/app_toast.dart';
import '../components/empty_state.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import '../l10n/app_localizations.dart';
import '../models/protocol.dart';
import '../models/payloads/terminal_payloads.g.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/cli_operations.dart';
import '../theme/theme_extensions.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../widgets/terminal_extra_keys.dart';
import '../utils/logger.dart';

final _log = getLogger('TerminalScreen');

/// Default terminal font size
const double _kDefaultFontSize = 11.0;

/// Minimum allowed font size (readable on small screens)
const double _kMinFontSize = 8.0;

/// Maximum allowed font size (usable on large screens)
const double _kMaxFontSize = 18.0;

/// Font size adjustment step per tap
const double _kFontSizeStep = 1.0;

/// SharedPreferences key for persisted terminal font size.
const String _kFontSizePrefKey = 'terminal_font_size';

/// Monospace character width-to-height ratio
const double _kCharWidthRatio = 0.6;

/// Line height multiplier
const double _kLineHeightRatio = 1.35;

// ── Terminal lifecycle state machine ──

/// Terminal session lifecycle states.
///
/// Named [TerminalLifecycle] to avoid collision with Flutter's
/// built-in [State] and other common names.
///
/// State transitions:
///   idle → starting → rendering → ready
///   ready → idle (restart / CLI switch / dispose)
///   starting → idle (restart before agent responds)
///   rendering → idle (restart during first-frame render)
enum TerminalLifecycle {
  /// No terminal session. Initial state or after restart/stop.
  idle,

  /// LayoutBuilder measured the available space, terminal.start sent
  /// to agent, waiting for terminal.started response.
  starting,

  /// Agent confirmed terminal.started. TerminalView is building and
  /// painting its first frame. Output data is buffered during this
  /// window to prevent xterm CircularBuffer null-access crashes.
  rendering,

  /// TerminalView completed first paint. Output data flows through
  /// the post-frame flush pipeline. This is the normal operating state.
  ready,
}

/// Safety cap for pending output buffer.
///
/// The buffer window is typically 1-2 frames (~16-32ms). At 115200 baud
/// with average 40-byte chunks, ~90 chunks/32ms is the theoretical
/// max. 200 provides 2x headroom for burst scenarios.
const int _kMaxPendingChunks = 200;

/// Full terminal emulator screen with xterm view and macOS-style title bar.
class TerminalScreen extends StatefulWidget {
  /// When true, renders without Scaffold wrapper for embedding in other screens.
  final bool embedded;

  const TerminalScreen({super.key, this.embedded = false});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with SingleTickerProviderStateMixin {
  late Terminal _terminal;
  late TerminalController _terminalController;
  late WebSocketService _ws;
  StreamSubscription? _sub;

  // ── State machine ──

  /// Current lifecycle state. All state queries go through this
  /// single enum instead of multiple booleans.
  TerminalLifecycle _lifecycle = TerminalLifecycle.idle;

  /// Terminal dimensions (set once during sizing, never resized after).
  int _currentCols = 0;
  int _currentRows = 0;

  /// Monotonic key for forcing TerminalView rebuild on restart.
  int _terminalKey = 0;

  /// CLI name bound to the current terminal session.
  String _terminalCli = '';

  /// Guard against duplicate restart triggers from WebSocketService
  /// notifications arriving in the same frame.
  bool _pendingRestart = false;

  // ── Selection state ──

  /// Whether the user has an active text selection in the terminal.
  /// Tracked via TerminalController listener to show/hide copy toolbar.
  bool _hasSelection = false;

  // ── Font size ──

  /// Current terminal font size. Loaded from SharedPreferences on init,
  /// persisted on every change. Defaults to [_kDefaultFontSize].
  double _fontSize = _kDefaultFontSize;

  // ── Search state ──

  /// Whether the search bar is currently visible.
  bool _searchVisible = false;

  /// Current search query text.
  String _searchQuery = '';

  /// Active highlight objects from the current search. Disposed when
  /// the search query changes or the search bar is closed.
  final List<TerminalHighlight> _searchHighlights = [];

  /// Index of the currently focused search match (for ↑/↓ navigation).
  int _searchCurrentIndex = -1;

  /// Total number of search matches.
  int _searchMatchCount = 0;

  /// Line numbers of each search match, parallel to [_searchHighlights].
  /// Used for scrolling to the focused match.
  final List<int> _searchMatchLines = [];

  /// Controller for the search text field.
  final TextEditingController _searchController = TextEditingController();

  /// Debounce timer for search input to avoid searching on every keystroke.
  Timer? _searchDebounce;

  /// ScrollController for the TerminalView, used to scroll to search matches.
  final ScrollController _termScrollController = ScrollController();

  // ── Output buffering ──

  /// Output data buffered during [TerminalLifecycle.rendering].
  ///
  /// Before TerminalView completes its first paint, output is buffered
  /// here to prevent writing to an uninitialized render object.
  /// Once in ready state, data flows directly to [Terminal.write].
  ///
  /// Capped at [_kMaxPendingChunks] to prevent unbounded growth.
  final List<String> _pendingOutput = [];

  /// Startup animation controller (three dots color sequentially).
  late AnimationController _startupAnimController;

  // ── Convenience getters (replace old boolean checks) ──

  /// Whether the terminal session is active (started and potentially ready).
  bool get _isActive => _lifecycle.index >= TerminalLifecycle.rendering.index;

  /// Whether the terminal is fully ready to receive output data.
  bool get _isReady => _lifecycle == TerminalLifecycle.ready;

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _terminalController = TerminalController();
    _terminalController.addListener(_onSelectionChanged);
    _ws = context.read<WebSocketService>();
    _terminal.onOutput = (data) => _ws.terminalOps.sendTerminalInput(data);
    _sub = _ws.messageStream.listen(_onMessage);
    _loadFontSize();

    _startupAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Listen for CLI switch events via WebSocketService.
    // Using addListener instead of detecting in build() avoids the
    // Flutter anti-pattern of triggering side effects during build.
    _ws.addListener(_onWebSocketChanged);
  }

  /// Transition the terminal lifecycle state.
  ///
  /// Logs every transition for debugging.
  void _markLifecycle(TerminalLifecycle next) {
    final prev = _lifecycle;
    _lifecycle = next;
    _log.fine('终端状态变更: $prev → $next');
  }

  // ── Font size ──

  /// Load persisted font size from SharedPreferences.
  ///
  /// Called once in initState. If no value is stored, uses the default.
  /// Does not trigger a restart since the terminal hasn't started yet.
  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_kFontSizePrefKey);
    if (saved != null && saved >= _kMinFontSize && saved <= _kMaxFontSize) {
      if (mounted) setState(() => _fontSize = saved); // Defensive: async callback may fire after dispose
      _log.fine('终端字体大小已加载: $_fontSize');
    }
  }

  /// Persist font size to SharedPreferences.
  Future<void> _saveFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontSizePrefKey, _fontSize);
  }

  /// Increase font size by one step and restart terminal.
  ///
  /// Font size change requires terminal restart because cols/rows
  /// are recalculated from the new character dimensions. Clamped
  /// to [_kMaxFontSize].
  void _increaseFontSize() {
    if (_fontSize >= _kMaxFontSize) return;
    _fontSize = (_fontSize + _kFontSizeStep).clamp(_kMinFontSize, _kMaxFontSize);
    _saveFontSize();
    _log.info('终端字体增大: $_fontSize');
    _restartTerminal();
  }

  /// Decrease font size by one step and restart terminal.
  ///
  /// Clamped to [_kMinFontSize] to keep text readable.
  void _decreaseFontSize() {
    if (_fontSize <= _kMinFontSize) return;
    _fontSize = (_fontSize - _kFontSizeStep).clamp(_kMinFontSize, _kMaxFontSize);
    _saveFontSize();
    _log.info('终端字体缩小: $_fontSize');
    _restartTerminal();
  }

  // ── CLI quick switch ──

  /// Show a bottom sheet with the list of installed CLIs for quick switching.
  ///
  /// Only shown when multiple CLIs are installed. Selecting a different CLI
  /// triggers switchCLI which fires _onWebSocketChanged → terminal restart.
  void _showCliPicker() {
    final ws = context.read<WebSocketService>();
    final clis = ws.installedClis;
    if (clis.length <= 1) return;

    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;

    HapticFeedback.lightImpact();
    AppBottomSheet.show(
      context,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.lg,
            vertical: spacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.of(context).terminalSwitchCli, style: typography.titleMedium),
              SizedBox(height: spacing.md),
              ...clis.map((cli) {
                final isActive = cli == ws.defaultCli;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (!isActive) {
                      context.read<CliOperations>().switchCLI(cli);
                      _log.info('CLI 切换: $cli');
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.sm + 4,
                    ),
                    margin: EdgeInsets.only(bottom: spacing.xs),
                    decoration: BoxDecoration(
                      color: isActive
                          ? colors.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isActive
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: isActive
                              ? colors.primary
                              : colors.onSurfaceMuted,
                        ),
                        SizedBox(width: spacing.sm),
                        Text(
                          ws.cliDisplayName(cli),
                          style: typography.bodyMedium.copyWith(
                            color: isActive
                                ? colors.primary
                                : colors.onSurface,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              SizedBox(height: spacing.sm),
            ],
          ),
        );
      },
    );
  }

  // ── Terminal search ──

  /// Toggle the search bar visibility.
  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _clearSearchHighlights();
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  /// Execute a search across all terminal buffer lines.
  ///
  /// Clears previous highlights, scans every line for case-insensitive
  /// matches of [query], creates TerminalController highlights for each
  /// match, and focuses the last match (closest to current output).
  void _performSearch(String query) {
    _clearSearchHighlights();
    _searchQuery = query;

    if (query.isEmpty) {
      setState(() {
        _searchCurrentIndex = -1;
        _searchMatchCount = 0;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    final buffer = _terminal.buffer;
    final totalLines = buffer.height;
    final colors = context.colors;

    for (int lineIdx = 0; lineIdx < totalLines; lineIdx++) {
      final line = buffer.lines[lineIdx];
      final lineText = line.getText().toLowerCase();
      int searchFrom = 0;

      // Find all occurrences of the query in this line
      while (true) {
        final matchStart = lineText.indexOf(lowerQuery, searchFrom);
        if (matchStart == -1) break;

        final matchEnd = matchStart + query.length;
        try {
          final highlight = _terminalController.highlight(
            p1: buffer.createAnchor(matchStart, lineIdx),
            p2: buffer.createAnchor(matchEnd, lineIdx),
            color: colors.warning.withValues(alpha: 0.35),
          );
          _searchHighlights.add(highlight);
          _searchMatchLines.add(lineIdx);
        } catch (e) {
          // Anchor creation can fail if line index is out of range
          // during rapid buffer updates — skip silently
          _log.fine('搜索高亮创建失败: line=$lineIdx, error=$e');
        }

        searchFrom = matchEnd;
      }
    }

    setState(() {
      _searchMatchCount = _searchHighlights.length;
      // Focus the last match (closest to current terminal output)
      _searchCurrentIndex =
          _searchMatchCount > 0 ? _searchMatchCount - 1 : -1;
    });

    if (_searchCurrentIndex >= 0) {
      _scrollToMatch(_searchCurrentIndex);
    }

    _log.fine('终端搜索: query="$query", matches=$_searchMatchCount');
  }

  /// Navigate to the previous search match.
  void _searchPrev() {
    if (_searchMatchCount == 0) return;
    setState(() {
      _searchCurrentIndex =
          (_searchCurrentIndex - 1 + _searchMatchCount) % _searchMatchCount;
    });
    _scrollToMatch(_searchCurrentIndex);
  }

  /// Navigate to the next search match.
  void _searchNext() {
    if (_searchMatchCount == 0) return;
    setState(() {
      _searchCurrentIndex =
          (_searchCurrentIndex + 1) % _searchMatchCount;
    });
    _scrollToMatch(_searchCurrentIndex);
  }

  /// Scroll the terminal view to make the match at [index] visible.
  ///
  /// Calculates the pixel offset from the match's line number and
  /// the current font metrics, then jumps the scroll controller.
  void _scrollToMatch(int index) {
    if (index < 0 || index >= _searchMatchLines.length) return;
    final lineIdx = _searchMatchLines[index];
    final lineHeight = _fontSize * _kLineHeightRatio;
    final targetOffset = lineIdx * lineHeight;

    // Clamp to valid scroll range
    if (_termScrollController.hasClients) {
      final maxScroll = _termScrollController.position.maxScrollExtent;
      _termScrollController.jumpTo(targetOffset.clamp(0, maxScroll));
    }
  }

  /// Dispose all active search highlights and reset match state.
  void _clearSearchHighlights() {
    for (final h in _searchHighlights) {
      h.dispose();
    }
    _searchHighlights.clear();
    _searchMatchLines.clear();
    _searchCurrentIndex = -1;
    _searchMatchCount = 0;
  }

  // ── Event handlers ──

  /// Track selection state changes from TerminalController.
  ///
  /// Updates [_hasSelection] to show/hide the floating copy toolbar.
  /// Only triggers setState when the boolean actually changes to avoid
  /// unnecessary rebuilds from other controller notifications.
  void _onSelectionChanged() {
    final hasSelection = _terminalController.selection != null;
    if (hasSelection != _hasSelection && mounted) { // Defensive: listener fires while tab is invisible (IndexedStack)
      setState(() => _hasSelection = hasSelection);
    }
  }

  /// Copy selected terminal text to system clipboard.
  ///
  /// Reads the selected range from the terminal buffer, writes it
  /// to the clipboard, shows a toast confirmation, then clears
  /// the selection.
  void _copySelection() {
    final selection = _terminalController.selection;
    if (selection == null) return;

    final text = _terminal.buffer.getText(selection);
    if (text.isEmpty) return;

    Clipboard.setData(ClipboardData(text: text));
    _terminalController.clearSelection();
    HapticFeedback.lightImpact();
    if (mounted) {
      AppToast.show(context, S.of(context).commonCopied);
    }
    _log.fine('终端文本已复制: ${text.length} 字符');
  }

  /// React to WebSocketService changes (CLI switch, project switch).
  ///
  /// Schedules the restart in a post-frame callback to avoid triggering
  /// setState during build. The _pendingRestart flag prevents duplicate
  /// restarts when multiple notifications arrive in the same frame.
  void _onWebSocketChanged() {
    if (_isActive &&
        _ws.defaultCli.isNotEmpty &&
        _ws.defaultCli != _terminalCli &&
        !_pendingRestart) {
      _pendingRestart = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pendingRestart) {
          _pendingRestart = false;
          _restartTerminal();
        }
      });
    }
  }

  void _onMessage(WsMessage msg) {
    if (msg.type == MessageType.terminalStarted) {
      _log.info('终端已启动: $_currentCols×$_currentRows, cli=$_terminalCli');
      _markLifecycle(TerminalLifecycle.rendering);
      if (mounted) setState(() {}); // Defensive: message callback may fire while tab is invisible
      _startupAnimController.stop();
      // Wait for TerminalView to complete its first full render cycle
      // (build → layout → paint) before writing data.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _lifecycle != TerminalLifecycle.rendering) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _lifecycle != TerminalLifecycle.rendering) return;
          _markLifecycle(TerminalLifecycle.ready);
          _flushPendingOutput();
        });
      });
    }
    if (msg.type == MessageType.terminalOutput) {
      final p = TerminalOutputPayload.fromJson(msg.payload);
      final encoded = p.data;
      if (encoded.isNotEmpty) {
        final bytes = base64Decode(encoded);
        final text = utf8.decode(bytes, allowMalformed: true);
        if (_isReady) {
          _terminal.write(text);
        } else {
          // Buffer until TerminalView completes first paint
          if (_pendingOutput.length < _kMaxPendingChunks) {
            _pendingOutput.add(text);
          }
        }
      }
    }
  }

  /// Flush buffered output that arrived during [TerminalLifecycle.rendering].
  ///
  /// Called exactly once per terminal lifecycle, when transitioning
  /// from rendering → ready.
  void _flushPendingOutput() {
    if (_pendingOutput.isEmpty) return;
    _log.fine('刷新缓冲终端数据: ${_pendingOutput.length} 条');
    for (final text in _pendingOutput) {
      _terminal.write(text);
    }
    _pendingOutput.clear();
  }

  void _updateTerminalSize(double width, double height) {
    // Only calculate size once at startup — never resize after that.
    // Resizing during active output causes xterm buffer reflow issues
    // (duplicated text, rendering glitches). The terminal size is fixed
    // at the initial layout dimensions; keyboard show/hide does not
    // affect it because resizeToAvoidBottomInset is false.
    if (_lifecycle != TerminalLifecycle.idle) return;

    // Subtract rounded container padding and title bar height
    final adjustedWidth = width - 16; // 8dp padding each side
    final adjustedHeight = height - 40; // title bar height
    final charWidth = _fontSize * _kCharWidthRatio;
    final lineHeight = _fontSize * _kLineHeightRatio;
    final cols = (adjustedWidth / charWidth).floor();
    final rows = (adjustedHeight / lineHeight).floor();

    if (cols == _currentCols && rows == _currentRows) return;
    if (cols < 10 || rows < 5) return;

    _currentCols = cols;
    _currentRows = rows;
    _terminalCli = _ws.defaultCli;
    _markLifecycle(TerminalLifecycle.starting);
    _log.info('启动终端: $cols×$rows, cli=$_terminalCli');
    _ws.terminalOps.startTerminal(cols: cols, rows: rows);
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    // watch WebSocketService to respond to project/CLI state changes
    final ws = context.watch<WebSocketService>();
    final hasProject = ws.currentProjectPath.isNotEmpty;
    final colors = context.colors;
    final spacing = context.spacing;

    return widget.embedded ? _buildBody(ws, hasProject, colors, spacing) : Scaffold(
      backgroundColor: colors.background,
      // Prevent Flutter from resizing the body when the keyboard appears.
      // The terminal manages its own size via LayoutBuilder + keyboard
      // height detection. Without this, the Scaffold shrinks the body
      // on every animation frame during keyboard show/hide, causing
      // xterm TerminalView to rapidly resize and produce overlapping content.
      resizeToAvoidBottomInset: false,
      body: _buildBody(ws, hasProject, colors, spacing),
    );
  }

  /// Terminal body content, usable both standalone and embedded.
  Widget _buildBody(WebSocketService ws, bool hasProject, AppColorTokens colors, AppSpacingTokens spacing) {
    return !hasProject
          ? _buildNoProjectState()
          : !_hasAnyCli(ws)
              ? _buildNoCliState()
              : SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: spacing.sm,
                      right: spacing.sm,
                      top: spacing.sm,
                    ),
                    child: Column(
                      children: [
                        _buildMacTitleBar(),
                        if (_searchVisible) _buildSearchBar(),
                        Expanded(
                          child: Stack(
                            children: [
                              _buildTerminalContainer(),
                              // Floating copy button when text is selected
                              if (_hasSelection)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: _buildCopyButton(),
                                ),
                            ],
                          ),
                        ),
                        if (_isActive)
                          TerminalExtraKeys(
                            onKey: (data) => _ws.terminalOps.sendTerminalInput(data),
                            onPaste: (text) => _terminal.paste(text),
                          ),
                      ],
                    ),
                  ),
                );
  }

  /// Check if any CLI is installed.
  bool _hasAnyCli(WebSocketService ws) {
    return ws.defaultCli.isNotEmpty;
  }

  /// No project selected prompt.
  Widget _buildNoProjectState() {
    return EmptyState(
      icon: Icons.folder_off_outlined,
      title: S.of(context).terminalNoProjectTitle,
      description: S.of(context).terminalNoProjectDescription,
      useGlassCard: false,
    );
  }

  /// No CLI installed prompt.
  Widget _buildNoCliState() {
    final colors = context.colors;
    final typography = context.typography;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal, size: 64, color: colors.onSurfaceMuted),
          SizedBox(height: context.spacing.lg),
          Text(S.of(context).terminalNoAgent, style: typography.titleMedium),
          SizedBox(height: context.spacing.sm),
          Text(
            S.of(context).terminalNoAgentDescription,
            style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }

  /// macOS-style title bar (tri-color dots + CLI name + terminal size + restart button).
  Widget _buildMacTitleBar() {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;
    final ws = context.read<WebSocketService>();

    final dotColors = [
      const Color(0xFFFF5F57),
      const Color(0xFFFFBD2E),
      const Color(0xFF28C840),
    ];

    return Container(
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: spacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.radii.lg),
        ),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Row(
        children: [
          // Three dots: pulse animation before start, stable colors after start
          ...List.generate(3, (i) {
            if (_isActive) {
              // After start: stable colors
              return Container(
                width: 10,
                height: 10,
                margin: EdgeInsets.only(right: spacing.xs),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColors[i],
                ),
              );
            }
            // Before start: pulse animation
            return _PulseDot(
              index: i,
              controller: _startupAnimController,
              spacing: spacing.xs,
            );
          }),
          SizedBox(width: spacing.sm),
          // CLI name + size (tappable for CLI switch when multiple CLIs installed)
          Expanded(
            child: GestureDetector(
              onTap: () {
                final ws = context.read<WebSocketService>();
                if (ws.installedClis.length > 1) _showCliPicker();
              },
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        [
                          if (ws.defaultCli.isNotEmpty) ws.cliDisplayName(ws.defaultCli),
                          if (_isActive && _currentCols > 0) '$_currentCols×$_currentRows',
                        ].join(' · '),
                        style: typography.codeMedium.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Show dropdown indicator when multiple CLIs available
                    if (ws.installedClis.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Icon(
                          Icons.arrow_drop_down,
                          size: 14,
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Search button (only when terminal is active)
          if (_isActive)
            _TitleBarButton(
              onTap: _toggleSearch,
              child: Icon(
                _searchVisible ? Icons.search_off : Icons.search,
                size: 15,
                color: _searchVisible
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
            ),
          // Restart button
          _TitleBarButton(
            onTap: _restartTerminal,
            child: Icon(Icons.refresh, size: 15, color: colors.onSurfaceVariant),
          ),
          // Font size decrease
          _TitleBarButton(
            onTap: _fontSize > _kMinFontSize ? _decreaseFontSize : null,
            child: Text(
              'A−',
              style: typography.codeMedium.copyWith(
                color: _fontSize <= _kMinFontSize
                    ? colors.onSurfaceMuted.withValues(alpha: 0.3)
                    : colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          // Font size increase
          _TitleBarButton(
            onTap: _fontSize < _kMaxFontSize ? _increaseFontSize : null,
            child: Text(
              'A+',
              style: typography.codeMedium.copyWith(
                color: _fontSize >= _kMaxFontSize
                    ? colors.onSurfaceMuted.withValues(alpha: 0.3)
                    : colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Floating copy button shown when text is selected in the terminal.
  ///
  /// Positioned in the top-right corner of the terminal container.
  /// Uses a pill shape with icon + label for clear affordance.
  Widget _buildCopyButton() {
    final colors = context.colors;
    return GestureDetector(
      onTap: _copySelection,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy, size: 14, color: colors.onPrimary),
            const SizedBox(width: 4),
            Text(
              S.of(context).commonCopy,
              style: TextStyle(
                fontSize: 12,
                color: colors.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Search bar shown between the title bar and terminal container.
  ///
  /// Contains a text field, match count indicator, prev/next navigation
  /// buttons, and a close button. Uses debounced input (300ms) to avoid
  /// searching on every keystroke.
  Widget _buildSearchBar() {
    final colors = context.colors;
    final spacing = context.spacing;

    return Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: spacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(
          left: BorderSide(color: colors.borderSubtle, width: 1),
          right: BorderSide(color: colors.borderSubtle, width: 1),
          bottom: BorderSide(color: colors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Search input
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurface,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: S.of(context).terminalSearchHint,
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: colors.onSurfaceMuted,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (value) {
                // Debounce search to avoid excessive buffer scans
                _searchDebounce?.cancel();
                _searchDebounce = Timer(
                  const Duration(milliseconds: 300),
                  () => _performSearch(value),
                );
              },
              onSubmitted: (_) => _searchNext(),
            ),
          ),
          // Match count indicator
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _searchMatchCount > 0
                    ? '${_searchCurrentIndex + 1}/$_searchMatchCount'
                    : '0',
                style: TextStyle(
                  fontSize: 11,
                  color: _searchMatchCount > 0
                      ? colors.onSurfaceVariant
                      : colors.error,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          // Prev / Next buttons
          GestureDetector(
            onTap: _searchPrev,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.keyboard_arrow_up, size: 18,
                  color: colors.onSurfaceVariant),
            ),
          ),
          GestureDetector(
            onTap: _searchNext,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.keyboard_arrow_down, size: 18,
                  color: colors.onSurfaceVariant),
            ),
          ),
          // Close button
          GestureDetector(
            onTap: _toggleSearch,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close, size: 16,
                  color: colors.onSurfaceMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// Terminal view container (rounded corners + border).
  /// Bottom corners are square when the key bar is visible to avoid
  /// a visual gap between the terminal and the key bar.
  Widget _buildTerminalContainer() {
    final colors = context.colors;
    final bottomRadius = _isActive
        ? Radius.zero
        : Radius.circular(context.radii.lg);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.vertical(bottom: bottomRadius),
        border: Border(
          left: BorderSide(color: colors.borderSubtle, width: 1),
          right: BorderSide(color: colors.borderSubtle, width: 1),
          bottom: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(bottom: bottomRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateTerminalSize(constraints.maxWidth, constraints.maxHeight);
            });

            // TerminalView only renders after agent confirms start
            if (!_isActive) {
              return _buildStartGuide();
            }

            return TerminalView(
              key: ValueKey(_terminalKey),
              _terminal,
              controller: _terminalController,
              scrollController: _termScrollController,
              theme: TerminalTheme(
                cursor: colors.onSurface,
                selection: colors.primary.withValues(alpha: 0.25),
                foreground: colors.onSurface,
                background: colors.surfaceDim,
                black: colors.surfaceVariant,
                red: colors.error,
                green: colors.success,
                yellow: colors.warning,
                blue: const Color(0xFF31748F),
                magenta: colors.primary,
                cyan: colors.secondary,
                white: colors.onSurface,
                brightBlack: colors.onSurfaceMuted,
                brightRed: colors.error,
                brightGreen: colors.success,
                brightYellow: colors.warning,
                brightBlue: const Color(0xFF31748F),
                brightMagenta: colors.primary,
                brightCyan: colors.secondary,
                brightWhite: colors.onSurface,
                searchHitBackground: colors.warning.withValues(alpha: 0.25),
                searchHitBackgroundCurrent:
                    colors.warning.withValues(alpha: 0.5),
                searchHitForeground: colors.background,
              ),
              textStyle: TerminalStyle(
                fontSize: _fontSize,
                fontFamily: 'monospace',
              ),
            );
          },
        ),
      ),
    );
  }

  /// Start guide page (shown when terminal is not yet started).
  Widget _buildStartGuide() {
    final colors = context.colors;
    final typography = context.typography;
    return Container(
      color: colors.surfaceDim,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.terminal, size: 64, color: colors.primary),
            SizedBox(height: context.spacing.lg),
            Text(S.of(context).terminalStarting, style: typography.titleMedium),
            SizedBox(height: context.spacing.sm),
            Text(
              S.of(context).terminalConnectingCli,
              style:
                  typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
            ),
            SizedBox(height: context.spacing.xl),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Terminal control ──

  /// Reset terminal to idle state and start a new session.
  ///
  /// Cancels the message subscription, stops the agent-side PTY,
  /// resets all state to [TerminalLifecycle.idle], and re-subscribes
  /// to messages. The LayoutBuilder will trigger a new sizing cycle.
  void _restartTerminal() {
    _log.info('重启终端');
    HapticFeedback.mediumImpact();
    _sub?.cancel();
    _ws.terminalOps.stopTerminal();
    _startupAnimController.repeat();
    setState(() {
      _terminal = Terminal(maxLines: 10000);
      _terminal.onOutput = (data) => _ws.terminalOps.sendTerminalInput(data);
      _terminalController.removeListener(_onSelectionChanged);
      _clearSearchHighlights();
      _terminalController.dispose();
      _terminalController = TerminalController();
      _terminalController.addListener(_onSelectionChanged);
      _hasSelection = false;
      _searchVisible = false;
      _searchQuery = '';
      _searchController.clear();
      _markLifecycle(TerminalLifecycle.idle);
      _pendingOutput.clear();
      _terminalKey++;
      _currentCols = 0;
      _currentRows = 0;
    });
    _sub = _ws.messageStream.listen(_onMessage);
  }

  @override
  void dispose() {
    _ws.removeListener(_onWebSocketChanged);
    _sub?.cancel();
    _searchDebounce?.cancel();
    _clearSearchHighlights();
    _searchController.dispose();
    _termScrollController.dispose();
    _terminalController.removeListener(_onSelectionChanged);
    _terminalController.dispose();
    _startupAnimController.dispose();
    _ws.terminalOps.stopTerminal();
    super.dispose();
  }
}


/// Pulse dot (sequential blinking loading animation before terminal starts).
class _PulseDot extends StatelessWidget {
  final int index;
  final AnimationController controller;
  final double spacing;

  const _PulseDot({
    required this.index,
    required this.controller,
    required this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    // Each dot is delayed by 0.2 to create a wave effect
    final delay = index * 0.2;
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Calculate current dot brightness (pulsing between 0.2 and 1.0)
        final t = (controller.value - delay) % 1.0;
        final opacity = t < 0.5 ? 0.2 + 0.8 * (t * 2) : 1.0 - 0.8 * ((t - 0.5) * 2);
        return Container(
          width: 10,
          height: 10,
          margin: EdgeInsets.only(right: spacing),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.onSurfaceMuted.withValues(alpha: opacity.clamp(0.2, 1.0)),
          ),
        );
      },
    );
  }
}

/// Uniform title bar button with consistent sizing and touch target.
///
/// All title bar actions (search, restart, font size) use this wrapper
/// to ensure equal spacing, vertical centering, and adequate touch area.
/// When [onTap] is null, the button is visually present but non-interactive.
class _TitleBarButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _TitleBarButton({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 32,
        height: 36,
        child: Center(child: child),
      ),
    );
  }
}
