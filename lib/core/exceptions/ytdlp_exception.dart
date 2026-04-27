/// Represents any error that originates from the yt-dlp binary or service.
library;

/// Error type for failed yt-dlp invocations, timeouts, or invalid responses.
class YtdlpException implements Exception {
  /// Creates an exception with a user-facing [message].
  const YtdlpException(this.message, {this.originalError});

  /// Human-readable description (use centralized copy from the app layer).
  final String message;

  /// Original throwable when this exception wraps a lower-level failure.
  final Object? originalError;

  @override
  String toString() => 'YtdlpException: $message';
}
