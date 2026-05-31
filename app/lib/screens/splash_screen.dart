/// splash_screen.dart — Splash screen with launch animation.
//
// Module: screens/
// Responsibility:
//   Brand animation on app launch: icon pop-in + halo expansion + text fade-in.
//   Total duration 1.2s, animation runs in parallel with initialization.
//   Transitions to the main screen via FadeTransition + ScaleTransition.
//
// Called by:
//   - main.dart AppRouter (initial route)

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme_extensions.dart';

/// Splash screen with brand launch animation.
class SplashScreen extends StatefulWidget {
  /// Callback when animation completes
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Icon scale animation (0.5 → 1.0, spring bounce)
  late AnimationController _iconController;
  late Animation<double> _iconScale;

  /// Glow expansion animation (0 → 120dp)
  late AnimationController _glowController;
  late Animation<double> _glowRadius;
  late Animation<double> _glowOpacity;

  /// Text fade-in + slide-up animation
  late AnimationController _textController;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();

    // Icon pop-in (0-500ms)
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _iconScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _iconController, curve: Curves.easeOutBack),
    );

    // Glow expansion (100-700ms)
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _glowRadius = Tween<double>(begin: 0, end: 120).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeOutCubic),
    );
    _glowOpacity = Tween<double>(begin: 0, end: 0.3).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeOut),
    );

    // Text fade-in (500-800ms)
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _textOpacity = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOut,
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOutCubic,
    ));

    // Orchestrate animation sequence
    _startAnimationSequence();
  }

  Future<void> _startAnimationSequence() async {
    // Icon pop-in
    _iconController.forward();

    // Glow starts after 100ms
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    _glowController.forward();

    // Text fades in after 500ms
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _textController.forward();

    // Notify completion after 1200ms
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glow + icon
            AnimatedBuilder(
              animation: Listenable.merge([_iconController, _glowController]),
              builder: (_, __) {
                return Container(
                  width: 200,
                  height: 200,
                  alignment: Alignment.center,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow
                      Container(
                        width: _glowRadius.value * 2,
                        height: _glowRadius.value * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              colors.primary
                                  .withValues(alpha: _glowOpacity.value),
                              colors.primary.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                      // Icon
                      Transform.scale(
                        scale: _iconScale.value,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.code,
                            size: 36,
                            color: colors.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            // App name
            SlideTransition(
              position: _textSlide,
              child: FadeTransition(
                opacity: _textOpacity,
                child: Text(
                  'MobileFlow',
                  style: context.typography.displayLarge.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Subtitle
            SlideTransition(
              position: _textSlide,
              child: FadeTransition(
                opacity: _textOpacity,
                child: Text(
                  S.of(context).appSubtitle,
                  style: context.typography.bodyMedium.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _iconController.dispose();
    _glowController.dispose();
    _textController.dispose();
    super.dispose();
  }
}
