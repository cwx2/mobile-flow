/// format_utils.dart — Formatting utility functions.
///
/// General-purpose formatting helpers shared across multiple screens.

/// Format a byte count into a human-readable size string.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Format a [Duration] into a compact human-readable uptime string.
///
/// Returns '--' for null. Examples: '42s', '3m 12s', '1h 5m 30s'.
String formatUptime(Duration? uptime) {
  if (uptime == null) return '--';
  final h = uptime.inHours;
  final m = uptime.inMinutes.remainder(60);
  final s = uptime.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
