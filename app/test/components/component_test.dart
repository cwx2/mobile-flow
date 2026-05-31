// Component Layer 综合测试
//
// 覆盖：GlassCard、AppButton、StatusDot、EmptyState、
//       SectionHeader、SkeletonLoader、AppTextField

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobileflow/components/glass_card.dart';
import 'package:mobileflow/components/app_button.dart';
import 'package:mobileflow/components/status_dot.dart';
import 'package:mobileflow/components/empty_state.dart';
import 'package:mobileflow/components/section_header.dart';
import 'package:mobileflow/components/skeleton_loader.dart';
import 'package:mobileflow/components/app_text_field.dart';
import 'package:mobileflow/animation/counter_animator.dart';
import 'package:mobileflow/theme/app_theme.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.buildDark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('GlassCard', () {
    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(wrap(
        const GlassCard(child: Text('Hello')),
      ));
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('onTap callback fires', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(
        GlassCard(onTap: () => tapped = true, child: const Text('Tap me')),
      ));
      await tester.tap(find.text('Tap me'));
      await tester.pumpAndSettle();
      expect(tapped, true);
    });

    testWidgets('enableBlur=false renders without BackdropFilter',
        (tester) async {
      await tester.pumpWidget(wrap(
        const GlassCard(enableBlur: false, child: Text('No blur')),
      ));
      expect(find.text('No blur'), findsOneWidget);
      // No BackdropFilter in tree
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('enableBlur=true renders with BackdropFilter', (tester) async {
      await tester.pumpWidget(wrap(
        const GlassCard(enableBlur: true, child: Text('Blur')),
      ));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('AppButton', () {
    testWidgets('primary variant renders', (tester) async {
      await tester.pumpWidget(wrap(
        const AppButton(label: 'Submit', variant: AppButtonVariant.primary),
      ));
      expect(find.text('Submit'), findsOneWidget);
    });

    testWidgets('secondary variant renders', (tester) async {
      await tester.pumpWidget(wrap(
        const AppButton(label: 'Cancel', variant: AppButtonVariant.secondary),
      ));
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('ghost variant renders', (tester) async {
      await tester.pumpWidget(wrap(
        const AppButton(label: 'Skip', variant: AppButtonVariant.ghost),
      ));
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('danger variant renders', (tester) async {
      await tester.pumpWidget(wrap(
        const AppButton(label: 'Delete', variant: AppButtonVariant.danger),
      ));
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('loading state shows spinner', (tester) async {
      await tester.pumpWidget(wrap(
        const AppButton(label: 'Loading', loading: true),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('disabled state prevents tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(
        AppButton(
            label: 'Disabled', disabled: true, onTap: () => tapped = true),
      ));
      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(tapped, false);
    });

    testWidgets('icon renders when provided', (tester) async {
      await tester.pumpWidget(wrap(
        const AppButton(label: 'Add', icon: Icons.add),
      ));
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('StatusDot', () {
    for (final state in StatusDotState.values) {
      testWidgets('renders $state state', (tester) async {
        await tester.pumpWidget(wrap(StatusDot(state: state)));
        expect(find.byType(StatusDot), findsOneWidget);
      });
    }

    testWidgets('custom size works', (tester) async {
      await tester.pumpWidget(wrap(
        const StatusDot(state: StatusDotState.connected, size: 16),
      ));
      expect(find.byType(StatusDot), findsOneWidget);
    });

    testWidgets('state change triggers animation reconfigure', (tester) async {
      await tester.pumpWidget(wrap(
        const StatusDot(state: StatusDotState.connected),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      // Change state
      await tester.pumpWidget(wrap(
        const StatusDot(state: StatusDotState.disconnected),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(StatusDot), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('renders icon and title', (tester) async {
      await tester.pumpWidget(wrap(
        const EmptyState(icon: Icons.check, title: 'All done'),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('All done'), findsOneWidget);
    });

    testWidgets('renders description when provided', (tester) async {
      await tester.pumpWidget(wrap(
        const EmptyState(
          icon: Icons.check,
          title: 'Done',
          description: 'No more items',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No more items'), findsOneWidget);
    });

    testWidgets('renders action button when provided', (tester) async {
      await tester.pumpWidget(wrap(
        EmptyState(
          icon: Icons.add,
          title: 'Empty',
          action: ElevatedButton(onPressed: () {}, child: const Text('Add')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('useGlassCard=false skips GlassCard', (tester) async {
      await tester.pumpWidget(wrap(
        const EmptyState(
          icon: Icons.check,
          title: 'Plain',
          useGlassCard: false,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(GlassCard), findsNothing);
    });
  });

  group('SectionHeader', () {
    testWidgets('renders icon and title', (tester) async {
      await tester.pumpWidget(wrap(
        const SectionHeader(
          icon: Icons.folder,
          iconColor: Colors.amber,
          title: 'Projects',
        ),
      ));
      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);
    });

    testWidgets('renders trailing widget', (tester) async {
      await tester.pumpWidget(wrap(
        const SectionHeader(
          icon: Icons.settings,
          iconColor: Colors.blue,
          title: 'Settings',
          trailing: Icon(Icons.chevron_right),
        ),
      ));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });

  group('SkeletonLoader', () {
    testWidgets('renders correct number of lines', (tester) async {
      await tester.pumpWidget(wrap(
        const SkeletonLoader(lines: 5),
      ));
      // Each line is a FractionallySizedBox
      expect(find.byType(FractionallySizedBox), findsNWidgets(5));
    });

    testWidgets('default is 3 lines', (tester) async {
      await tester.pumpWidget(wrap(const SkeletonLoader()));
      expect(find.byType(FractionallySizedBox), findsNWidgets(3));
    });
  });

  group('AppTextField', () {
    testWidgets('renders with hint text', (tester) async {
      await tester.pumpWidget(wrap(
        const AppTextField(hintText: 'Enter text'),
      ));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows error text', (tester) async {
      await tester.pumpWidget(wrap(
        const AppTextField(hintText: 'Email', errorText: 'Invalid email'),
      ));
      expect(find.text('Invalid email'), findsOneWidget);
    });

    testWidgets('prefix icon renders', (tester) async {
      await tester.pumpWidget(wrap(
        const AppTextField(prefixIcon: Icons.email),
      ));
      expect(find.byIcon(Icons.email), findsOneWidget);
    });
  });

  group('AnimatedCounter', () {
    testWidgets('renders initial value', (tester) async {
      await tester.pumpWidget(wrap(
        const AnimatedCounter(value: 42),
      ));
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('animates on value change', (tester) async {
      await tester.pumpWidget(wrap(const AnimatedCounter(value: 1)));
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(wrap(const AnimatedCounter(value: 2)));
      await tester.pump(const Duration(milliseconds: 150));
      // During animation, both old and new might be visible
      // After settle, only new value
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
    });
  });
}
