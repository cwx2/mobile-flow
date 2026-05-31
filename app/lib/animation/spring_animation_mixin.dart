/// spring_animation_mixin.dart — Spring physics animation mixin.
//
// 模块：animation/
// 职责：
//   封装 SpringSimulation，提供物理弹性动画能力。
//   用于按钮弹跳、卡片释放、列表回弹等场景。
//
// 被谁调用：
//   - 自定义图标/按钮弹跳
//   - 滑动操作释放回弹
//
// 设计模式：Mixin Pattern

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 弹簧动画 Mixin
///
/// 使用方式：
/// 1. State 类 with SpringAnimationMixin
/// 2. initState 中调用 initSpring()
/// 3. 需要弹簧效果时调用 animateSpring(from, to)
/// 4. 监听 springValue 获取当前值
mixin SpringAnimationMixin
    on State<StatefulWidget>, SingleTickerProviderStateMixin {
  late AnimationController _springController;

  /// 当前弹簧动画值
  double get springValue => _springController.value;

  /// 弹簧动画对象（可用于 AnimatedBuilder）
  Animation<double> get springAnimation => _springController;

  /// 初始化弹簧控制器
  void initSpring({double initialValue = 0.0}) {
    _springController = AnimationController.unbounded(
      vsync: this,
      value: initialValue,
    );
  }

  /// 执行弹簧动画
  ///
  /// [from] 起始值
  /// [to] 目标值
  /// [spring] 弹簧参数（可选，默认 mass:1, stiffness:300, damping:20）
  void animateSpring({
    required double from,
    required double to,
    SpringDescription? spring,
  }) {
    final desc = spring ??
        const SpringDescription(mass: 1.0, stiffness: 300, damping: 20);
    final simulation = SpringSimulation(desc, from, to, 0);
    _springController.animateWith(simulation);
  }

  /// 释放弹簧控制器
  void disposeSpring() {
    _springController.dispose();
  }
}
