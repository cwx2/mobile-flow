/// image_viewer.dart — Full-screen image viewer with pinch-to-zoom.
//
// Wraps photo_view for viewing images from AI tool results.
// Tap image in chat -> opens full screen with zoom/pan support.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// Open a full-screen zoomable image viewer
void showImageViewer(BuildContext context, Uint8List bytes) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) => _ImageViewerPage(bytes: bytes),
      transitionsBuilder: (_, anim, __, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    ),
  );
}

class _ImageViewerPage extends StatelessWidget {
  final Uint8List bytes;
  const _ImageViewerPage({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: PhotoView(
          imageProvider: MemoryImage(bytes),
          backgroundDecoration: const BoxDecoration(color: Colors.transparent),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        ),
      ),
    );
  }
}
