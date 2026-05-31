/// json_renderer.dart — JSON syntax highlighting and collapsible tree widget.
///
/// Module: widgets/renderers/
/// Responsibility:
///   Displays JSON data with syntax highlighting, collapsible nodes,
///   and basic search. Used by the API Tester Panel for response display.
///
/// Called by:
///   - screens/test_panel/api_tester_panel.dart
///   - Any screen needing formatted JSON display
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../theme/theme_extensions.dart';

/// A widget that displays JSON with syntax highlighting and collapsible nodes.
///
/// Parses the input JSON string and renders it as a tree with:
/// - Color-coded keys, strings, numbers, booleans, and null values
/// - Collapsible objects and arrays
/// - Indentation for nested structures
class JsonRenderer extends StatefulWidget {
  /// The JSON string to display.
  final String jsonString;

  /// Initial expansion depth (0 = all collapsed, -1 = all expanded).
  final int initialExpandDepth;

  const JsonRenderer({
    super.key,
    required this.jsonString,
    this.initialExpandDepth = 2,
  });

  @override
  State<JsonRenderer> createState() => _JsonRendererState();
}

class _JsonRendererState extends State<JsonRenderer> {
  dynamic _parsedJson;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _parseJson();
  }

  @override
  void didUpdateWidget(JsonRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.jsonString != oldWidget.jsonString) {
      _parseJson();
    }
  }

  void _parseJson() {
    try {
      _parsedJson = json.decode(widget.jsonString);
      _parseError = null;
    } catch (e) {
      _parsedJson = null;
      _parseError = e.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_parseError != null) {
      // Fallback: show raw text if JSON is invalid
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          widget.jsonString,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: colors.onSurface,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: _JsonNode(
        value: _parsedJson,
        depth: 0,
        expandDepth: widget.initialExpandDepth,
      ),
    );
  }
}

/// Internal widget for rendering a single JSON node (recursive).
class _JsonNode extends StatefulWidget {
  final dynamic value;
  final String? keyName;
  final int depth;
  final int expandDepth;
  final bool isLast;

  const _JsonNode({
    required this.value,
    this.keyName,
    required this.depth,
    required this.expandDepth,
    this.isLast = true,
  });

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.expandDepth < 0 || widget.depth < widget.expandDepth;
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;

    if (value is Map) {
      return _buildCollapsible(
        context,
        openBracket: '{',
        closeBracket: '}',
        children: value.entries.toList(),
        isMap: true,
      );
    } else if (value is List) {
      return _buildCollapsible(
        context,
        openBracket: '[',
        closeBracket: ']',
        children: value,
        isMap: false,
      );
    } else {
      return _buildLeaf(context, value);
    }
  }

  Widget _buildCollapsible(
    BuildContext context, {
    required String openBracket,
    required String closeBracket,
    required List children,
    required bool isMap,
  }) {
    final colors = context.colors;
    final indent = widget.depth * 16.0;

    if (!_expanded) {
      // Collapsed view: { ... } or [ ... ]
      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: GestureDetector(
          onTap: () => setState(() => _expanded = true),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.keyName != null) ...[
                Text(
                  '"${widget.keyName}"',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.primary),
                ),
                Text(': ', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface)),
              ],
              Icon(Icons.arrow_right, size: 14, color: colors.onSurfaceMuted),
              Text(
                '$openBracket ${children.length} items $closeBracket',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurfaceMuted),
              ),
              if (!widget.isLast)
                Text(',', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface)),
            ],
          ),
        ),
      );
    }

    // Expanded view
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Opening line: key: { or [
        Padding(
          padding: EdgeInsets.only(left: indent),
          child: GestureDetector(
            onTap: () => setState(() => _expanded = false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.keyName != null) ...[
                  Text(
                    '"${widget.keyName}"',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.primary),
                  ),
                  Text(': ', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface)),
                ],
                Icon(Icons.arrow_drop_down, size: 14, color: colors.onSurfaceMuted),
                Text(openBracket, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface)),
              ],
            ),
          ),
        ),
        // Children
        ...List.generate(children.length, (i) {
          final isLast = i == children.length - 1;
          if (isMap) {
            final entry = children[i] as MapEntry;
            return _JsonNode(
              value: entry.value,
              keyName: entry.key.toString(),
              depth: widget.depth + 1,
              expandDepth: widget.expandDepth,
              isLast: isLast,
            );
          } else {
            return _JsonNode(
              value: children[i],
              depth: widget.depth + 1,
              expandDepth: widget.expandDepth,
              isLast: isLast,
            );
          }
        }),
        // Closing bracket
        Padding(
          padding: EdgeInsets.only(left: indent),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(closeBracket, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface)),
              if (!widget.isLast)
                Text(',', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaf(BuildContext context, dynamic value) {
    final colors = context.colors;
    final indent = widget.depth * 16.0;

    Color valueColor;
    String valueText;

    if (value is String) {
      valueColor = colors.success;
      valueText = '"$value"';
    } else if (value is num) {
      valueColor = colors.warning;
      valueText = value.toString();
    } else if (value is bool) {
      valueColor = colors.primary;
      valueText = value.toString();
    } else {
      valueColor = colors.onSurfaceMuted;
      valueText = 'null';
    }

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.keyName != null) ...[
            Text(
              '"${widget.keyName}"',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.primary),
            ),
            Text(': ', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface)),
          ],
          Flexible(
            child: Text(
              valueText,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: valueColor),
            ),
          ),
          if (!widget.isLast)
            Text(',', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurface)),
        ],
      ),
    );
  }
}
