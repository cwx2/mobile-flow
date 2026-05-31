/// ui_config.dart — UI behaviour constants.
///
/// Centralises all UI-related thresholds and timing parameters
/// so they are easy to tune without hunting through widget code.
/// Companion to [connection_config.dart] which holds network constants.
library;

/// Scroll offset threshold (in pixels) to enter immersive reading mode.
///
/// In a reverse ListView, offset 0 = bottom (newest message).
/// When the user scrolls up past this threshold, the AppBar, InputBar,
/// and TabBar hide to maximise reading space.
///
/// 80px ≈ roughly 2 message bubbles of scroll — enough to confirm
/// intentional browsing rather than accidental touch.
const kImmersiveScrollThreshold = 80.0;
