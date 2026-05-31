/// file_viewer_screen.dart — Standalone file viewer screen.
// Navigated to from chat tool-call cards or file-edit cards.
// Fetches file content via WebSocket and renders with CodeEditor (syntax highlighting + editable).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../editor/editor.dart';

import '../models/protocol.dart';
import '../services/websocket_service.dart';
import '../services/ws_operations/file_operations.dart';
import '../theme/code_theme.dart';
import '../components/app_toast.dart';
import '../l10n/app_localizations.dart';
import '../widgets/code_editor_view.dart';
import '../widgets/editor_extra_keys.dart';
import '../utils/comment_styles.dart';
import '../utils/language_detect.dart';
import '../models/payloads/file_payloads.g.dart';
import '../utils/logger.dart';

final _log = getLogger('FileViewerScreen');


/// Standalone file viewer screen navigated to from chat tool-call cards.
class FileViewerScreen extends StatefulWidget {
  final String filePath;
  final int? line;

  const FileViewerScreen({super.key, required this.filePath, this.line});

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  bool _loading = true;
  String? _error;
  bool _editing = false;
  bool _modified = false;
  bool _showFind = false;
  CodeLineEditingController? _codeController;
  CodeScrollController? _scrollController;
  CodeFindController? _findController;
  String? _savedContent;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    _sub = ws.messageStream.listen(_onMessage);
    context.read<FileOperations>().requestFileRead(widget.filePath);
  }

  void _onMessage(WsMessage msg) {
    if (msg.type == MessageType.fileReadResult) {
      final p = FileReadResultPayload.fromJson(msg.payload);
      if (p.path != widget.filePath) return;
      final content = p.content;
      final error = p.error;
      setState(() {
        _loading = false;
        if (error != null) {
          _log.warning('文件读取失败: path=${widget.filePath}, error=$error');
          _error = error;
          return;
        }
        _savedContent = content ?? '';
        _codeController?.dispose();
        _scrollController?.dispose();
        _findController?.dispose();
        _codeController = CodeLineEditingController.fromText(_savedContent!);
        _scrollController = CodeScrollController();
        _findController = CodeFindController(_codeController!);
      });
      _log.fine('文件加载完成: path=${widget.filePath}, size=${content?.length ?? 0}');

      // Jump to line after content loads (if specified)
      if (widget.line != null && _scrollController != null && _codeController != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpToLine(widget.line!);
        });
      }
    }

    if (msg.type == MessageType.fileWriteResult) {
      final p = FileWriteResultPayload.fromJson(msg.payload);
      if (p.path != widget.filePath) return;
      if (p.success && mounted) {
        setState(() {
          _savedContent = _codeController?.text ?? '';
          _modified = false;
        });
        AppToast.show(context, S.of(context).commonSaved, type: AppToastType.success);
      }
    }
  }

  /// Jump to a specific line number (1-based) and highlight it.
  void _jumpToLine(int line) {
    final ctrl = _codeController;
    final scroll = _scrollController;
    if (ctrl == null || scroll == null) return;

    // Clamp to valid range (line is 1-based, controller is 0-based)
    final index = (line - 1).clamp(0, ctrl.codeLines.length - 1);
    final position = CodeLinePosition(index: index, offset: 0);
    ctrl.selection = CodeLineSelection.collapsed(index: index, offset: 0);
    scroll.makeCenterIfInvisible(position);
  }

  void _saveFile() {
    context.read<FileOperations>().writeFile(widget.filePath, _codeController?.text ?? '');
  }

  void _toggleFind() {
    setState(() => _showFind = !_showFind);
    if (_showFind) {
      // Activate find mode so the controller starts accepting search input
      _findController?.findMode();
    } else {
      _findController?.close();
    }
  }

  /// Build comment formatter for the current file's language.
  CodeCommentFormatter? _buildCommentFormatter() {
    return buildCommentFormatter(detectLanguage(widget.filePath));
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.filePath.split('/').last;
    final codeTheme = context.watch<CodeThemeNotifier>();

    return Scaffold(
      backgroundColor: codeTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: codeTheme.backgroundColor,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fileName,
                style: TextStyle(fontSize: 15, color: codeTheme.foregroundColor)),
            Text(
              widget.filePath,
              style: TextStyle(fontSize: 10, color: codeTheme.foregroundColor.withValues(alpha: 0.5)),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        iconTheme: IconThemeData(color: codeTheme.foregroundColor),
        actions: [
          // Search toggle
          IconButton(
            icon: Icon(
              Icons.search,
              color: _showFind ? Colors.orange : null,
            ),
            tooltip: S.of(context).fileViewerSearch,
            onPressed: _toggleFind,
          ),
          if (_editing && _codeController != null) ...[
            IconButton(
              icon: Icon(Icons.undo,
                  color: _codeController!.canUndo ? null : Colors.grey[700]),
              tooltip: S.of(context).fileViewerUndo,
              onPressed: _codeController!.canUndo ? () { _codeController!.undo(); setState(() {}); } : null,
            ),
            IconButton(
              icon: Icon(Icons.redo,
                  color: _codeController!.canRedo ? null : Colors.grey[700]),
              tooltip: S.of(context).fileViewerRedo,
              onPressed: _codeController!.canRedo ? () { _codeController!.redo(); setState(() {}); } : null,
            ),
          ],
          if (_editing && _modified)
            IconButton(
              icon: Icon(Icons.save, color: context.read<CodeThemeNotifier>().foregroundColor),
              onPressed: _saveFile,
              tooltip: S.of(context).fileViewerSave,
            ),
          IconButton(
            icon: Icon(
              _editing ? Icons.visibility : Icons.edit,
              color: _editing ? Colors.orange : null,
            ),
            onPressed: () => setState(() => _editing = !_editing),
            tooltip: _editing ? S.of(context).fileViewerViewMode : S.of(context).fileViewerEditMode,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Expanded(child: _buildCodeEditor(codeTheme)),
                    // Extra keys bar in edit mode
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                      child: _editing && _codeController != null
                          ? EditorExtraKeys(
                              controller: _codeController!,
                              onToggleFind: _toggleFind,
                              commentFormatter: _buildCommentFormatter(),
                            )
                          : const SizedBox(width: double.infinity, height: 0),
                    ),
                  ],
                ),
    );
  }

  Widget _buildCodeEditor(CodeThemeNotifier codeTheme) {
    if (_codeController == null) {
      return Center(child: Text(S.of(context).fileViewerEmptyContent));
    }

    return CodeEditorView(
      controller: _codeController!,
      scrollController: _scrollController,
      findController: _findController,
      showFind: _showFind,
      onFindClose: () => setState(() => _showFind = false),
      filePath: widget.filePath,
      readOnly: !_editing,
      onChanged: (_) {
        final isModified = (_codeController?.text ?? '') != (_savedContent ?? '');
        if (isModified != _modified) {
          setState(() => _modified = isModified);
        }
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _codeController?.dispose();
    _scrollController?.dispose();
    _findController?.dispose();
    super.dispose();
  }
}
