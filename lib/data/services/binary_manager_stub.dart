/// Stub implementation when `dart:io` is unavailable (e.g. web).
library;

import '../../core/utils/logger.dart';

/// No-op [BinaryManager] for platforms without a bundled yt-dlp binary.
class BinaryManager {
  /// Creates a stub manager.
  const BinaryManager();

  /// Throws [UnsupportedError] because no bundled binary exists on web.
  Future<String> initialize() async {
    AppLogger.w('BinaryManager.initialize called on unsupported platform');
    throw UnsupportedError('yt-dlp is not available on this platform');
  }

  /// Clears cached preference keys for a future native initialization.
  Future<void> reset() async {}

  /// Stubbed version lookup for non-IO platforms.
  Future<String> getYtdlpVersion() async {
    return 'Unknown';
  }
}
