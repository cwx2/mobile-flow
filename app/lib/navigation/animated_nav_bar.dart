/// animated_nav_bar.dart - Custom animated bottom navigation bar.
///
/// 模块：navigation/
/// 职责：
///   替换 Material NavigationBar，使用毛玻璃背景和轻量选中态。
///   在窄屏设备上使用更紧凑的“选中项显示标签”布局，避免底栏过高或拥挤。
///
/// 设计模式：Composite Widget + responsive layout strategy

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_extensions.dart';

const double kAnimatedNavBarBottomSpacing = 10;

enum AnimatedNavBarDensity {
  regular,
  compactLabeled,
  compactIconOnly,
}

class AnimatedNavBarLayout {
  final AnimatedNavBarDensity density;
  final double barHeight;
  final double totalHeight;
  final double outerHorizontalPadding;
  final double itemHorizontalMargin;
  final double itemVerticalMargin;
  final double itemHeight;
  final double itemHorizontalPadding;
  final double selectedHorizontalPadding;
  final double iconSize;
  final double labelGap;
  final TextStyle labelStyle;

  const AnimatedNavBarLayout({
    required this.density,
    required this.barHeight,
    required this.totalHeight,
    required this.outerHorizontalPadding,
    required this.itemHorizontalMargin,
    required this.itemVerticalMargin,
    required this.itemHeight,
    required this.itemHorizontalPadding,
    required this.selectedHorizontalPadding,
    required this.iconSize,
    required this.labelGap,
    required this.labelStyle,
  });

  bool get compactMode => density != AnimatedNavBarDensity.regular;

  bool get showsSelectedLabel =>
      density == AnimatedNavBarDensity.compactLabeled;

  factory AnimatedNavBarLayout.of(
    BuildContext context, {
    required int itemCount,
    required List<String> labels,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final textScale = mediaQuery.textScaler.scale(1);
    final isCompactWidth = mediaQuery.size.width < 380;
    final labelStyle = context.typography.labelSmall.copyWith(height: 1.0);
    final useRegularDensity = mediaQuery.size.width >= 430 && textScale <= 1.1;

    final outerHorizontalPadding =
        useRegularDensity ? 12.0 : (isCompactWidth ? 8.0 : 10.0);
    final itemHorizontalMargin =
        useRegularDensity ? 6.0 : (isCompactWidth ? 2.0 : 4.0);
    final iconSize = useRegularDensity ? 22.0 : (isCompactWidth ? 20.0 : 21.0);
    final itemVerticalMargin = useRegularDensity ? 7.0 : 5.0;
    final itemHorizontalPadding = useRegularDensity ? 8.0 : 10.0;
    final selectedHorizontalPadding =
        useRegularDensity ? 10.0 : (isCompactWidth ? 10.0 : 12.0);
    final labelGap = useRegularDensity ? 4.0 : 6.0;
    final resolvedLabelSize = mediaQuery.textScaler.scale(
      labelStyle.fontSize ?? 11,
    );
    final resolvedLabelHeight = resolvedLabelSize * (labelStyle.height ?? 1.0);

    final availableWidth =
        math.max(0.0, mediaQuery.size.width - (outerHorizontalPadding * 2));
    final slotWidth =
        itemCount > 0 ? availableWidth / itemCount : availableWidth;
    final slotContentWidth =
        math.max(0.0, slotWidth - (itemHorizontalMargin * 2));
    final maxLabelWidth = labels.fold<double>(
      0,
      (currentMax, label) => math.max(
        currentMax,
        _measureLabelWidth(
          text: label,
          style: labelStyle,
          textScaler: mediaQuery.textScaler,
        ),
      ),
    );
    final selectedLabeledWidth =
        (selectedHorizontalPadding * 2) + iconSize + labelGap + maxLabelWidth;

    final density = useRegularDensity
        ? AnimatedNavBarDensity.regular
        : selectedLabeledWidth <= slotContentWidth
            ? AnimatedNavBarDensity.compactLabeled
            : AnimatedNavBarDensity.compactIconOnly;

    final itemHeight = switch (density) {
      AnimatedNavBarDensity.regular => 52.0,
      AnimatedNavBarDensity.compactLabeled => 42.0,
      AnimatedNavBarDensity.compactIconOnly => 38.0,
    };
    final minimumBarHeight = switch (density) {
      AnimatedNavBarDensity.regular => 70.0,
      AnimatedNavBarDensity.compactLabeled => 56.0,
      AnimatedNavBarDensity.compactIconOnly => 52.0,
    };

    final requiredBarHeight = density == AnimatedNavBarDensity.regular
        ? iconSize +
            labelGap +
            resolvedLabelHeight +
            3 +
            4 +
            ((itemVerticalMargin + 8) * 2)
        : itemHeight + (itemVerticalMargin * 2);

    final barHeight = math.max(
      minimumBarHeight,
      requiredBarHeight.ceilToDouble(),
    );

    return AnimatedNavBarLayout(
      density: density,
      barHeight: barHeight,
      totalHeight:
          barHeight + mediaQuery.padding.bottom + kAnimatedNavBarBottomSpacing,
      outerHorizontalPadding: outerHorizontalPadding,
      itemHorizontalMargin: itemHorizontalMargin,
      itemVerticalMargin: itemVerticalMargin,
      itemHeight: itemHeight,
      itemHorizontalPadding: itemHorizontalPadding,
      selectedHorizontalPadding: selectedHorizontalPadding,
      iconSize: iconSize,
      labelGap: labelGap,
      labelStyle: labelStyle,
    );
  }
}

double _measureLabelWidth({
  required String text,
  required TextStyle style,
  required TextScaler textScaler,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}

double animatedNavBarTotalHeight(
  BuildContext context, {
  required int itemCount,
  required List<String> labels,
}) {
  return AnimatedNavBarLayout.of(
    context,
    itemCount: itemCount,
    labels: labels,
  ).totalHeight;
}

/// 导航项数据
class NavBarItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const NavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 自定义动画底部导航栏
class AnimatedNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavBarItem> items;

  const AnimatedNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  State<AnimatedNavBar> createState() => _AnimatedNavBarState();
}

class _AnimatedNavBarState extends State<AnimatedNavBar>
    with TickerProviderStateMixin {
  late List<AnimationController> _bounceControllers;

  @override
  void initState() {
    super.initState();
    _bounceControllers = List.generate(
      widget.items.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void didUpdateWidget(AnimatedNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      for (final controller in _bounceControllers) {
        controller.dispose();
      }
      _bounceControllers = List.generate(
        widget.items.length,
        (_) => AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = AnimatedNavBarLayout.of(
      context,
      itemCount: widget.items.length,
      labels: widget.items.map((item) => item.label).toList(growable: false),
    );
    final colors = context.colors;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: layout.totalHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          layout.outerHorizontalPadding,
          0,
          layout.outerHorizontalPadding,
          kAnimatedNavBarBottomSpacing + bottomPadding,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.surfaceElevated
                        .withValues(alpha: context.isDark ? 0.92 : 0.96),
                    colors.surface
                        .withValues(alpha: context.isDark ? 0.84 : 0.92),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: colors.border
                      .withValues(alpha: context.isDark ? 0.42 : 0.72),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.scrim
                        .withValues(alpha: context.isDark ? 0.18 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(
                  widget.items.length,
                  (index) => Expanded(
                    child: _buildNavItem(
                      index: index,
                      layout: layout,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required AnimatedNavBarLayout layout,
  }) {
    final item = widget.items[index];
    final isSelected = index == widget.currentIndex;
    final colors = context.colors;
    final bounceAnimation = _bounceControllers[index];

    final scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(
      CurvedAnimation(parent: bounceAnimation, curve: Curves.easeOutBack),
    );

    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          bounceAnimation.forward(from: 0).then((_) {
            if (mounted) bounceAnimation.reverse();
          });
          widget.onTap(index);
        },
        child: SizedBox(
          height: layout.barHeight,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: EdgeInsets.symmetric(
                horizontal: layout.itemHorizontalMargin,
                vertical: layout.itemVerticalMargin,
              ),
              constraints: BoxConstraints(minHeight: layout.itemHeight),
              padding: EdgeInsets.symmetric(
                horizontal: isSelected
                    ? layout.selectedHorizontalPadding
                    : layout.itemHorizontalPadding,
              ),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          colors.primary
                              .withValues(alpha: context.isDark ? 0.16 : 0.1),
                          colors.secondary
                              .withValues(alpha: context.isDark ? 0.08 : 0.05),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
                color: isSelected
                    ? null
                    : colors.surfaceVariant.withValues(
                        alpha: context.isDark ? 0.18 : 0.4,
                      ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected
                      ? colors.borderFocused.withValues(alpha: 0.5)
                      : colors.borderSubtle.withValues(
                          alpha: context.isDark ? 0.22 : 0.45,
                        ),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: colors.primary
                              .withValues(alpha: context.isDark ? 0.14 : 0.08),
                          blurRadius: 18,
                          spreadRadius: -8,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : const [],
              ),
              child: switch (layout.density) {
                AnimatedNavBarDensity.regular => _buildRegularItem(
                    item: item,
                    isSelected: isSelected,
                    layout: layout,
                    scaleAnimation: scaleAnimation,
                  ),
                AnimatedNavBarDensity.compactLabeled => _buildCompactItem(
                    item: item,
                    isSelected: isSelected,
                    layout: layout,
                    scaleAnimation: scaleAnimation,
                  ),
                AnimatedNavBarDensity.compactIconOnly => _buildIconOnlyItem(
                    item: item,
                    isSelected: isSelected,
                    layout: layout,
                    scaleAnimation: scaleAnimation,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactItem({
    required NavBarItem item,
    required bool isSelected,
    required AnimatedNavBarLayout layout,
    required Animation<double> scaleAnimation,
  }) {
    final colors = context.colors;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: scaleAnimation,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              isSelected ? item.selectedIcon : item.icon,
              key: ValueKey<bool>(isSelected),
              size: layout.iconSize,
              color: isSelected ? colors.primary : colors.onSurfaceMuted,
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: isSelected
              ? Padding(
                  padding: EdgeInsets.only(left: layout.labelGap),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: layout.labelStyle.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildRegularItem({
    required NavBarItem item,
    required bool isSelected,
    required AnimatedNavBarLayout layout,
    required Animation<double> scaleAnimation,
  }) {
    final colors = context.colors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: scaleAnimation,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              isSelected ? item.selectedIcon : item.icon,
              key: ValueKey<bool>(isSelected),
              size: layout.iconSize,
              color: isSelected ? colors.primary : colors.onSurfaceMuted,
            ),
          ),
        ),
        SizedBox(height: layout.labelGap),
        AnimatedDefaultTextStyle(
          style: layout.labelStyle.copyWith(
            color: isSelected ? colors.onSurface : colors.onSurfaceMuted,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          ),
          duration: const Duration(milliseconds: 150),
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ],
    );
  }

  Widget _buildIconOnlyItem({
    required NavBarItem item,
    required bool isSelected,
    required AnimatedNavBarLayout layout,
    required Animation<double> scaleAnimation,
  }) {
    final colors = context.colors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: scaleAnimation,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              isSelected ? item.selectedIcon : item.icon,
              key: ValueKey<bool>(isSelected),
              size: layout.iconSize,
              color: isSelected ? colors.primary : colors.onSurfaceMuted,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final controller in _bounceControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
