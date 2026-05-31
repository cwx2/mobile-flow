/// page_transition_builder.dart — Page transition animation builder.
///
/// Module: animation/
/// Responsibility:
///   Provides 3 page transition animations: fade, slideUp, scale.
///   Used for Navigator.push and Tab switching.
///
/// Used by:
///   - SplashScreen → ConnectScreen/HomeScreen transition
///   - File list → file viewer transition
library;

import 'package:flutter/material.dart';

/// Page transition animation type.
enum PageTransitionType { fade, slideUp, scale }

/// Page transition animation route.
///
/// Usage:
/// ```dart
/// Navigator.push(context, AppPageRoute(
///   type: PageTransitionType.slideUp,
///   page: TargetScreen(),
/// ));
/// ```
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final PageTransitionType type;

  AppPageRoute({
    required this.page,
    this.type = PageTransitionType.fade,
  }) : super(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: _duration(type),
          reverseTransitionDuration: _duration(type),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return _buildTransition(type, animation, child);
          },
        );

  static Duration _duration(PageTransitionType type) {
    switch (type) {
      case PageTransitionType.fade:
        return const Duration(milliseconds: 150);
      case PageTransitionType.slideUp:
        return const Duration(milliseconds: 250);
      case PageTransitionType.scale:
        return const Duration(milliseconds: 200);
    }
  }

  static Widget _buildTransition(
    PageTransitionType type,
    Animation<double> animation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    switch (type) {
      case PageTransitionType.fade:
        return FadeTransition(opacity: curved, child: child);

      case PageTransitionType.slideUp:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );

      case PageTransitionType.scale:
        return ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
    }
  }
}
