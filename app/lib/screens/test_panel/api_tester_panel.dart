/// api_tester_panel.dart — API Tester panel for the Test Panel.
///
/// Module: screens/test_panel/
/// Responsibility:
///   Postman-like HTTP request builder and response viewer.
///   Sends requests via TestPanelOperations and displays responses
///   with status code, headers, body, and duration.
///
/// Called by:
///   - TestPanelScreen (Phase 6, Task 11.1) as one of the sub-panels
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/protocol.dart';
import '../../l10n/app_localizations.dart';
import '../../services/websocket_service.dart';
import '../../services/ws_operations/test_panel_operations.dart';
import '../../theme/theme_extensions.dart';
import '../../utils/logger.dart';

final _log = getLogger('ApiTester');

/// HTTP methods available in the dropdown.
const _httpMethods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'];

/// Methods that typically have a request body.
const _bodyMethods = {'POST', 'PUT', 'PATCH'};

/// A saved API request preset (in-memory).
class _ApiPreset {
  final String name;
  final String url;
  final String method;
  final List<MapEntry<String, String>> headers;
  final String? body;

  const _ApiPreset({
    required this.name,
    required this.url,
    required this.method,
    required this.headers,
    this.body,
  });
}

/// API Tester Panel — request builder + response viewer.
///
/// Provides a Postman-like interface for testing HTTP endpoints
/// through the Agent's HTTP proxy.
class ApiTesterPanel extends StatefulWidget {
  const ApiTesterPanel({super.key});

  @override
  State<ApiTesterPanel> createState() => _ApiTesterPanelState();
}

class _ApiTesterPanelState extends State<ApiTesterPanel> {
  final _urlController = TextEditingController();
  final _bodyController = TextEditingController();

  /// Selected HTTP method.
  String _method = 'GET';

  /// Request headers (key-value pairs).
  final List<_HeaderEntry> _headers = [];

  /// Whether a request is currently in flight.
  bool _isLoading = false;

  /// Response data (null if no response yet).
  _ApiResponseData? _response;

  /// Error message (null if no error).
  String? _errorMessage;

  /// Saved presets (in-memory).
  final List<_ApiPreset> _presets = [];

  /// Subscription to messageStream for api.* messages.
  StreamSubscription<WsMessage>? _messageSub;

  /// Current request ID for correlating responses.
  String? _currentRequestId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeToMessages();
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _urlController.dispose();
    _bodyController.dispose();
    for (final h in _headers) {
      h.dispose();
    }
    super.dispose();
  }

  void _subscribeToMessages() {
    final ws = context.read<WebSocketService>();
    _messageSub = ws.messageStream
        .where((msg) =>
            msg.type == MessageType.apiResponse ||
            msg.type == MessageType.apiError)
        .listen(_handleMessage);
  }

  void _handleMessage(WsMessage msg) {
    if (msg.type == MessageType.apiResponse) {
      _onApiResponse(msg.payload);
    } else if (msg.type == MessageType.apiError) {
      _onApiError(msg.payload);
    }
  }

  void _onApiResponse(Map<String, dynamic> payload) {
    final requestId = payload['request_id'] as String?;
    if (requestId != _currentRequestId) return;

    _log.info('API 响应: status=${payload['status_code']}, duration=${payload['duration_ms']}ms');
    setState(() {
      _isLoading = false;
      _errorMessage = null;
      _response = _ApiResponseData(
        statusCode: payload['status_code'] as int? ?? 0,
        headers: Map<String, String>.from(payload['headers'] as Map? ?? {}),
        body: payload['body'] as String? ?? '',
        durationMs: payload['duration_ms'] as int? ?? 0,
      );
    });
  }

  void _onApiError(Map<String, dynamic> payload) {
    final requestId = payload['request_id'] as String?;
    if (requestId != _currentRequestId) return;

    final errorType = payload['error_type'] as String? ?? 'unknown';
    final message = payload['message'] as String? ?? 'Unknown error';
    _log.warning('API 错误: type=$errorType, msg=$message');
    setState(() {
      _isLoading = false;
      _response = null;
      _errorMessage = '[$errorType] $message';
    });
  }

  void _sendRequest() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Generate unique request ID
    final requestId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    _currentRequestId = requestId;

    // Build headers map
    final headersMap = <String, String>{};
    for (final h in _headers) {
      final key = h.keyController.text.trim();
      final value = h.valueController.text.trim();
      if (key.isNotEmpty) {
        headersMap[key] = value;
      }
    }

    _log.info('发送 API 请求: $_method $url');
    setState(() {
      _isLoading = true;
      _response = null;
      _errorMessage = null;
    });

    context.read<TestPanelOperations>().sendApiRequest(
      url: url,
      method: _method,
      headers: headersMap,
      body: _bodyMethods.contains(_method) ? _bodyController.text : null,
      requestId: requestId,
    );
  }

  void _addHeader() {
    setState(() {
      _headers.add(_HeaderEntry());
    });
  }

  void _removeHeader(int index) {
    setState(() {
      _headers[index].dispose();
      _headers.removeAt(index);
    });
  }

  void _copyResponse() {
    if (_response == null) return;
    Clipboard.setData(ClipboardData(text: _response!.body));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.of(context).apiResponseCopied), duration: const Duration(seconds: 1)),
    );
  }

  void _savePreset() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final l = S.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        final nameController = TextEditingController();
        return AlertDialog(
          title: Text(l.apiSavePresetTitle),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(hintText: l.apiPresetNameHint),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    _presets.add(_ApiPreset(
                      name: name,
                      url: url,
                      method: _method,
                      headers: _headers
                          .map((h) => MapEntry(
                                h.keyController.text,
                                h.valueController.text,
                              ))
                          .toList(),
                      body: _bodyController.text,
                    ));
                  });
                }
                Navigator.pop(ctx);
              },
              child: Text(l.commonSaved),
            ),
          ],
        );
      },
    );
  }

  void _loadPreset(_ApiPreset preset) {
    setState(() {
      _urlController.text = preset.url;
      _method = preset.method;
      _bodyController.text = preset.body ?? '';
      // Clear existing headers and load preset headers
      for (final h in _headers) {
        h.dispose();
      }
      _headers.clear();
      for (final entry in preset.headers) {
        final h = _HeaderEntry();
        h.keyController.text = entry.key;
        h.valueController.text = entry.value;
        _headers.add(h);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Request builder area (scrollable)
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(context.spacing.md),
            children: [
              // Presets row
              if (_presets.isNotEmpty) _buildPresetsRow(context),
              // URL + Method row
              _buildUrlRow(context),
              SizedBox(height: context.spacing.sm),
              // Headers section
              _buildHeadersSection(context),
              // Body section (for POST/PUT/PATCH)
              if (_bodyMethods.contains(_method)) ...[
                SizedBox(height: context.spacing.sm),
                _buildBodySection(context),
              ],
              SizedBox(height: context.spacing.md),
              // Send + Save buttons
              _buildActionButtons(context),
              SizedBox(height: context.spacing.md),
              // Response / Error display
              if (_isLoading) _buildLoadingIndicator(context),
              if (_errorMessage != null) _buildErrorDisplay(context),
              if (_response != null) _buildResponseDisplay(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsRow(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _presets.length,
          separatorBuilder: (_, __) => SizedBox(width: spacing.xs),
          itemBuilder: (_, index) {
            final preset = _presets[index];
            return ActionChip(
              label: Text(preset.name, style: TextStyle(fontSize: 12, color: colors.onSurface)),
              onPressed: () => _loadPreset(preset),
              visualDensity: VisualDensity.compact,
            );
          },
        ),
      ),
    );
  }

  Widget _buildUrlRow(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Row(
      children: [
        // Method dropdown
        Container(
          padding: EdgeInsets.symmetric(horizontal: spacing.sm),
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _method,
              items: _httpMethods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m, style: TextStyle(fontSize: 13, color: colors.onSurface))))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _method = v);
              },
              isDense: true,
            ),
          ),
        ),
        SizedBox(width: spacing.sm),
        // URL input
        Expanded(
          child: TextField(
            controller: _urlController,
            style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: colors.onSurface),
            decoration: InputDecoration(
              hintText: 'https://api.example.com/endpoint',
              hintStyle: TextStyle(color: colors.onSurfaceMuted, fontSize: 13),
              filled: true,
              fillColor: colors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: spacing.md, vertical: spacing.sm),
              isDense: true,
            ),
            onSubmitted: (_) => _sendRequest(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeadersSection(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l.apiHeadersLabel, style: TextStyle(fontSize: 12, color: colors.onSurfaceMuted, fontWeight: FontWeight.w600)),
            const Spacer(),
            InkWell(
              onTap: _addHeader,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.add_circle_outline, size: 18, color: colors.primary),
              ),
            ),
          ],
        ),
        ...List.generate(_headers.length, (i) {
          final h = _headers[i];
          return Padding(
            padding: EdgeInsets.only(top: spacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: h.keyController,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface),
                    decoration: InputDecoration(
                      hintText: l.apiHeaderKeyHint,
                      hintStyle: TextStyle(color: colors.onSurfaceMuted, fontSize: 12),
                      filled: true,
                      fillColor: colors.surfaceVariant,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      contentPadding: EdgeInsets.symmetric(horizontal: spacing.sm, vertical: spacing.xs),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: TextField(
                    controller: h.valueController,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface),
                    decoration: InputDecoration(
                      hintText: l.apiHeaderValueHint,
                      hintStyle: TextStyle(color: colors.onSurfaceMuted, fontSize: 12),
                      filled: true,
                      fillColor: colors.surfaceVariant,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      contentPadding: EdgeInsets.symmetric(horizontal: spacing.sm, vertical: spacing.xs),
                      isDense: true,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _removeHeader(i),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.remove_circle_outline, size: 16, color: colors.error),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBodySection(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.of(context).apiBodyLabel, style: TextStyle(fontSize: 12, color: colors.onSurfaceMuted, fontWeight: FontWeight.w600)),
        SizedBox(height: spacing.xs),
        TextField(
          controller: _bodyController,
          maxLines: 5,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface),
          decoration: InputDecoration(
            hintText: '{"key": "value"}',
            hintStyle: TextStyle(color: colors.onSurfaceMuted, fontSize: 12),
            filled: true,
            fillColor: colors.surfaceVariant,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: EdgeInsets.all(spacing.sm),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _isLoading ? null : _sendRequest,
            icon: const Icon(Icons.send, size: 16),
            label: Text(l.apiSendButton),
          ),
        ),
        SizedBox(width: spacing.sm),
        IconButton(
          onPressed: _savePreset,
          icon: Icon(Icons.bookmark_add_outlined, color: colors.onSurfaceMuted),
          tooltip: l.apiSavePresetTooltip,
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.lg),
        child: CircularProgressIndicator(color: colors.primary),
      ),
    );
  }

  Widget _buildErrorDisplay(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.error, size: 18),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: colors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseDisplay(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l = S.of(context);
    final resp = _response!;

    // Status code color
    final statusColor = resp.statusCode < 300
        ? colors.success
        : resp.statusCode < 400
            ? colors.warning
            : colors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status + Duration row
        Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: spacing.sm, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${resp.statusCode}',
                style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(width: spacing.sm),
            Text(
              '${resp.durationMs}ms',
              style: TextStyle(color: colors.onSurfaceMuted, fontSize: 12),
            ),
            const Spacer(),
            IconButton(
              onPressed: _copyResponse,
              icon: Icon(Icons.copy, size: 18, color: colors.onSurfaceMuted),
              tooltip: l.apiCopyResponseTooltip,
            ),
          ],
        ),
        SizedBox(height: spacing.sm),
        // Response body
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 300),
          padding: EdgeInsets.all(spacing.sm),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border.withValues(alpha: 0.3)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              resp.body.length > 1024 * 1024
                  ? '${resp.body.substring(0, 1024 * 1024)}\n\n${l.apiResponseTruncated}'
                  : resp.body,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: colors.onSurface),
            ),
          ),
        ),
      ],
    );
  }
}

/// Internal response data holder.
class _ApiResponseData {
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final int durationMs;

  const _ApiResponseData({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.durationMs,
  });
}

/// Internal header entry with controllers.
class _HeaderEntry {
  final keyController = TextEditingController();
  final valueController = TextEditingController();

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}
