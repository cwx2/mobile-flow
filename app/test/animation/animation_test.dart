// Animation Orchestrator 测试
//
// 覆盖：PressableAnimator、ShakeAnimation、PageTransition、ShimmerPainter

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobileflow/animation/pressable_animator.dart';
import 'package:mobileflow/animation/shake_animation.dart';
import 'package:mobileflow/animation/page_transition_builder.dart';
import 'package:mobileflow/animation/shimmer_painter.dart';

Widget wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('PressableAnimator', () {
    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(wrap(
        const PressableAnimator(child: Text('Press me')),
      ));
      expect(find.text('Press me'), findsOneWidget);
    });

    testWidgets('onTap fires on tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(
        PressableAnimator(
          onTap: () => tapped = true,
          child: const Text('Tap'),
        ),
      ));
      await tester.tap(find.text('Tap'));
      await tester.pumpAndSettle();
      expect(tapped, true);
    });

    testWidgets('no crash when onTap is null', (tester) async {
      await tester.pumpWidget(wrap(
        const PressableAnimator(child: Text('No tap')),
      ));
      await tester.tap(find.text('No tap'));
      await tester.pumpAndSettle();
      // Should not crash
    });

    testWidgets('scale animation plays on press', (tester) async {
      await tester.pumpWidget(wrap(
        PressableAnimator(
          onTap: () {},
          child: const SizedBox(width: 100, height: 50, child: Text('Scale')),
        ),
      ));

      // Press down
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Scale')),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Find Transform.scale in tree (there may be multiple Transforms)
      expect(find.byType(Transform), findsWidgets);

      // Release
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('enableHaptic=false skips haptic', (tester) async {
      // Just verify it doesn't crash
      var tapped = false;
      await tester.pumpWidget(wrap(
        PressableAnimator(
          onTap: () => tapped = true,
          enableHaptic: false,
          child: const Text('No haptic'),
        ),
      ));
      await tester.tap(find.text('No haptic'));
      await tester.pumpAndSettle();
      expect(tapped, true);
    });

    testWidgets('custom pressScale works', (tester) async {
      await tester.pumpWidget(wrap(
        PressableAnimator(
          onTap: () {},
          pressScale: 0.9,
          child: const Text('Custom scale'),
        ),
      ));
      expect(find.text('Custom scale'), findsOneWidget);
    });
  });

  group('ShakeAnimation', () {
    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(wrap(
        const ShakeAnimation(child: Text('Shake me')),
      ));
      expect(find.text('Shake me'), findsOneWidget);
    });

    testWidgets('shake() triggers animation', (tester) async {
      final key = GlobalKey<ShakeAnimationState>();
      await tester.pumpWidget(wrap(
        ShakeAnimation(key: key, child: const Text('Shaking')),
      ));

      key.currentState!.shake();
      await tester.pump(const Duration(milliseconds: 50));
      // Animation should be in progress (Transform widgets exist in tree)
      expect(find.byType(Transform), findsWidgets);

      await tester.pumpAndSettle();
    });

    testWidgets('custom offset and count work', (tester) async {
      await tester.pumpWidget(wrap(
        const ShakeAnimation(
          offset: 12,
          count: 5,
          duration: Duration(milliseconds: 500),
          child: Text('Custom shake'),
        ),
      ));
      expect(find.text('Custom shake'), findsOneWidget);
    });
  });

  group('AppPageRoute', () {
    testWidgets('fade transition works', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              AppPageRoute(
                type: PageTransitionType.fade,
                page: const Scaffold(body: Text('Faded in')),
              ),
            ),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.text('Faded in'), findsOneWidget);
    });

    testWidgets('slideUp transition works', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              AppPageRoute(
                type: PageTransitionType.slideUp,
                page: const Scaffold(body: Text('Slid up')),
              ),
            ),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.text('Slid up'), findsOneWidget);
    });

    testWidgets('scale transition works', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              AppPageRoute(
                type: PageTransitionType.scale,
                page: const Scaffold(body: Text('Scaled in')),
              ),
            ),
            child: const Text('Go'),
          );
        }),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.text('Scaled in'), findsOneWidget);
    });
  });

  group('ShimmerPainter', () {
    test('shouldRepaint returns true when progress changes', () {
      final a = ShimmerPainter(
        progress: 0.0,
        baseColor: Colors.grey,
        highlightColor: Colors.white,
      );
      final b = ShimmerPainter(
        progress: 0.5,
        baseColor: Colors.grey,
        highlightColor: Colors.white,
      );
      expect(a.shouldRepaint(b), true);
    });

    test('shouldRepaint returns false when progress is same', () {
      final a = ShimmerPainter(
        progress: 0.5,
        baseColor: Colors.grey,
        highlightColor: Colors.white,
      );
      final b = ShimmerPainter(
        progress: 0.5,
        baseColor: Colors.grey,
        highlightColor: Colors.white,
      );
      expect(a.shouldRepaint(b), false);
    });
  });
}
