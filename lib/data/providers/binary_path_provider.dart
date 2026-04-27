/// Riverpod access to the extracted yt-dlp binary path.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/binary_manager.dart';

/// Resolves the absolute path to the extracted yt-dlp binary for the process.
///
/// Completes after [BinaryManager.initialize] finishes (may reuse cache).
final FutureProvider<String> binaryPathProvider = FutureProvider<String>((
  Ref ref,
) async {
  return const BinaryManager().initialize();
});

/// Reads and caches the bundled yt-dlp version.
final FutureProvider<String> ytdlpVersionProvider = FutureProvider<String>((
  Ref ref,
) async {
  return const BinaryManager().getYtdlpVersion();
});
