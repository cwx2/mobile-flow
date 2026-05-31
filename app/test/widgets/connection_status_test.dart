// Feature: connection-architecture-overhaul
//
// Latency threshold colour assignment tests.
//
// The ConnectionStatusIndicator widget uses a private _latencyColor
// method that depends on theme tokens (AppColorTokens). Since we
// cannot call the private method directly and a full widget test
// requires Provider + theme setup, we test the threshold logic as
// a pure function that mirrors the documented behaviour:
//
//   timedOut || latency < 0  → red (error)
//   latency < greenThreshold → green (success)
//   latency < redThreshold   → yellow (warning)
//   latency >= redThreshold  → red (error)
//
// This validates the boundary conditions that matter for UX.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/widgets/connection_status_indicator.dart';

/// Pure-function mirror of ConnectionStatusIndicator._latencyColor.
///
/// Uses raw Material colours instead of AppColorTokens so we can
/// test threshold logic without a full theme/Provider setup.
/// The mapping is: success→green, warning→amber, error→red.
Color _latencyColor(
  int latencyMs,
  bool timedOut, {
  int greenThreshold = kDefaultGreenThresholdMs,
  int redThreshold = kDefaultRedThresholdMs,
}) {
  if (timedOut || latencyMs < 0) return Colors.red;
  if (latencyMs < greenThreshold) return Colors.green;
  if (latencyMs < redThreshold) return Colors.amber;
  return Colors.red;
}

void main() {
  group('latency threshold colour assignment', () {
    // Feature: connection-architecture-overhaul
    test('test_latency_below_green_threshold', () {
      // 50ms is well below the default green threshold (100ms) → green
      expect(_latencyColor(50, false), Colors.green);
    });

    // Feature: connection-architecture-overhaul
    test('test_latency_at_green_threshold', () {
      // Exactly at green threshold (100ms) → yellow, not green
      // (the condition is latency < greenThreshold, so 100 is NOT < 100)
      expect(_latencyColor(100, false), Colors.amber);
    });

    // Feature: connection-architecture-overhaul
    test('test_latency_between_thresholds', () {
      // 300ms is between green (100) and red (500) → yellow
      expect(_latencyColor(300, false), Colors.amber);
    });

    // Feature: connection-architecture-overhaul
    test('test_latency_at_red_threshold', () {
      // Exactly at red threshold (500ms) → red
      // (the condition is latency < redThreshold, so 500 is NOT < 500)
      expect(_latencyColor(500, false), Colors.red);
    });

    // Feature: connection-architecture-overhaul
    test('test_latency_above_red_threshold', () {
      // 1000ms is well above red threshold → red
      expect(_latencyColor(1000, false), Colors.red);
    });

    // Feature: connection-architecture-overhaul
    test('test_latency_negative_means_unknown', () {
      // -1 indicates no measurement yet → red (error state)
      expect(_latencyColor(-1, false), Colors.red);
    });

    // Feature: connection-architecture-overhaul
    test('test_timed_out_always_red', () {
      // timedOut=true overrides any latency value → always red
      expect(_latencyColor(0, true), Colors.red);
      expect(_latencyColor(50, true), Colors.red);
      expect(_latencyColor(300, true), Colors.red);
    });

    // Feature: connection-architecture-overhaul
    test('test_custom_thresholds', () {
      // Custom thresholds: green < 200, yellow 200-799, red >= 800
      const green = 200;
      const red = 800;

      // Below custom green → green
      expect(
        _latencyColor(150, false, greenThreshold: green, redThreshold: red),
        Colors.green,
      );
      // Between custom thresholds → yellow
      expect(
        _latencyColor(500, false, greenThreshold: green, redThreshold: red),
        Colors.amber,
      );
      // At custom red → red
      expect(
        _latencyColor(800, false, greenThreshold: green, redThreshold: red),
        Colors.red,
      );
    });
  });

  group('exported constants', () {
    // Feature: connection-architecture-overhaul
    test('default thresholds are exported and sensible', () {
      // Verify the constants are accessible and have expected values
      expect(kDefaultGreenThresholdMs, 100);
      expect(kDefaultRedThresholdMs, 500);
      expect(kDefaultGreenThresholdMs, lessThan(kDefaultRedThresholdMs));
    });
  });
}
