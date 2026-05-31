/// app_config.dart — App-side configuration constants.
///
/// Module: utils/
/// Responsibility:
///   Centralizes all configurable values for the Flutter app.
///   Avoids magic numbers scattered across widgets.
///   If a value needs to become user-configurable in the future,
///   move it to a settings provider — the call sites won't change.
library;

/// Camera capture settings for photo attachments.
class CameraConfig {
  CameraConfig._();

  /// JPEG compression quality (0-100). 85 balances quality and file size.
  static const int imageQuality = 85;

  /// Maximum image width in pixels. Larger images are downscaled.
  static const double maxWidth = 1920;
}

/// Chat attachment display settings.
class AttachmentDisplayConfig {
  AttachmentDisplayConfig._();

  /// Thumbnail size in the attachment preview strip (dp).
  static const double previewThumbSize = 76;

  /// Thumbnail size in the chat bubble (dp).
  static const double bubbleThumbSize = 120;

  /// Border radius for thumbnails (dp).
  static const double thumbRadius = 12;

  /// Border radius for bubble thumbnails (dp).
  static const double bubbleThumbRadius = 10;
}

/// Chat history pagination settings.
///
/// Controls how many messages are rendered initially and loaded per
/// batch when the user scrolls up. Keeps the initial render fast
/// while allowing access to the full history on demand.
class HistoryPaginationConfig {
  HistoryPaginationConfig._();

  /// Number of messages to render on initial history load.
  /// Remaining messages are buffered and loaded on scroll-up.
  static const int initialPageSize = 30;

  /// Number of messages to load per scroll-up batch.
  static const int pageSize = 30;

  /// Scroll offset threshold (dp) from the top to trigger loading more.
  /// When the user scrolls within this distance from the top edge,
  /// the next batch is loaded automatically.
  static const double loadMoreThreshold = 100;
}
