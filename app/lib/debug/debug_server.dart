/// debug_server.dart — Debug HTTP server for widget tree inspection.
///
/// Provides /elements endpoint returning all Semantics nodes with
/// coordinates in the **adb input tap** coordinate system.
///
/// Coordinate pipeline:
///   SemanticsNode.rect (logical dp, origin = top of Flutter content area)
///   → accumulated transform → globalRect (logical dp)
///   → + viewPadding.top (status bar offset, in logical dp)
///   → × devicePixelRatio → adb physical pixels
///
/// The status bar offset is critical: Flutter's coordinate Y=0 starts
/// below the status bar, but adb's Y=0 starts at the very top of the
/// screen. Without this offset, all Y coordinates are too low by the
/// status bar height.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../utils/logger.dart';
import 'package:flutter/widgets.dart';

const int _kDebugPort = 9601;

final _log = getLogger('DebugServer');

HttpServer? _server;

/// Start the debug HTTP server (debug mode only).
Future<void> startDebugServer() async {
  if (!kDebugMode) return;

  try {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, _kDebugPort);
    _log.info('🔧 Debug server listening on http://0.0.0.0:$_kDebugPort');

    _server!.listen((request) async {
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.contentType = ContentType.json;

      try {
        if (request.uri.path == '/elements') {
          final data = _collectElements();
          request.response.write(jsonEncode(data));
        } else if (request.uri.path == '/ping') {
          final view = WidgetsBinding.instance.renderViews.firstOrNull
              ?.flutterView;
          request.response.write(jsonEncode({
            'status': 'ok',
            'pixelRatio': view?.devicePixelRatio,
            'physicalSize': {
              'width': view?.physicalSize.width,
              'height': view?.physicalSize.height,
            },
            'viewPaddingTop': view != null
                ? view.viewPadding.top / view.devicePixelRatio
                : 0,
          }));
        } else {
          request.response.statusCode = 404;
          request.response.write(jsonEncode({
            'error': 'Not found. Use /elements or /ping',
          }));
        }
      } catch (e) {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': e.toString()}));
      }

      await request.response.close();
    });
  } catch (e) {
    _log.warning('⚠️ Debug server failed to start: $e');
  }
}

/// Stop the debug server.
Future<void> stopDebugServer() async {
  await _server?.close();
  _server = null;
}

/// Collect all Semantics elements with adb-compatible coordinates.
///
/// Returns {"elements": [...], "meta": {...}} where each element has
/// x, y, w, h, centerX, centerY in adb physical pixel coordinates.
Map<String, dynamic> _collectElements() {
  final binding = WidgetsBinding.instance;
  final renderView = binding.renderViews.firstOrNull;
  if (renderView == null) {
    return {'elements': <Map<String, dynamic>>[], 'meta': {}};
  }

  final view = renderView.flutterView;
  final pixelRatio = view.devicePixelRatio;

  // Status bar height in logical dp — Flutter's Y=0 is below the status bar,
  // but adb's Y=0 is at the very top of the screen. We need to add this
  // offset to all Y coordinates.
  final statusBarLogicalDp = view.viewPadding.top / pixelRatio;

  final results = <Map<String, dynamic>>[];
  _visitSemanticsNode(
    binding.pipelineOwner.semanticsOwner?.rootSemanticsNode,
    results,
    pixelRatio,
    statusBarLogicalDp,
    Matrix4.identity(),
  );
  return {
    'elements': results,
    'meta': {
      'pixelRatio': pixelRatio,
      'physicalWidth': view.physicalSize.width,
      'physicalHeight': view.physicalSize.height,
      'statusBarHeight': statusBarLogicalDp * pixelRatio,
    },
  };
}

/// Recursively visit Semantics tree nodes.
void _visitSemanticsNode(
  SemanticsNode? node,
  List<Map<String, dynamic>> results,
  double pixelRatio,
  double statusBarLogicalDp,
  Matrix4 parentTransform,
) {
  if (node == null) return;

  final data = node.getSemanticsData();
  final rect = node.rect;

  // Accumulate transforms: parent × current node
  final nodeTransform = node.transform ?? Matrix4.identity();
  final globalTransform = parentTransform.multiplied(nodeTransform);
  final globalRect = MatrixUtils.transformRect(globalTransform, rect);

  // Convert to adb physical pixels:
  // Return logical dp coordinates directly — the MCP server will
  // handle the conversion to adb coordinates using wm size.
  // DO NOT multiply by pixelRatio here — that produces wrong results
  // because the Semantics transform already accounts for display scaling.
  final physX = globalRect.left.round();
  final physY = globalRect.top.round();
  final physW = globalRect.width.round();
  final physH = globalRect.height.round();
  final centerX = physX + physW ~/ 2;
  final centerY = physY + physH ~/ 2;

  // Filter off-screen elements
  final onScreen = centerY >= 0 && centerY <= 2200; // generous margin

  final label = data.label;
  final tooltip = data.tooltip;
  final isTappable = (data.actions & SemanticsAction.tap.index) != 0;
  final isScrollable =
      (data.actions & SemanticsAction.scrollUp.index) != 0 ||
      (data.actions & SemanticsAction.scrollDown.index) != 0;

  if (onScreen && (label.isNotEmpty || tooltip.isNotEmpty || isTappable)) {
    final actions = <String>[];
    if (isTappable) actions.add('tap');
    if (isScrollable) actions.add('scroll');
    if ((data.actions & SemanticsAction.longPress.index) != 0) {
      actions.add('longPress');
    }

    results.add({
      'label': label,
      if (tooltip.isNotEmpty) 'tooltip': tooltip,
      'x': physX,
      'y': physY,
      'w': physW,
      'h': physH,
      'centerX': centerX,
      'centerY': centerY,
      'actions': actions,
      if (data.value.isNotEmpty) 'value': data.value,
    });
  }

  node.visitChildren((child) {
    _visitSemanticsNode(
        child, results, pixelRatio, statusBarLogicalDp, globalTransform);
    return true;
  });
}
