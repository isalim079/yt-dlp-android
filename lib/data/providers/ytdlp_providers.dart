/// Riverpod wiring for yt-dlp metadata and the active URL field.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist_info.dart';
import '../models/video_format.dart';
import '../models/video_info.dart';
import '../services/ytdlp_service.dart';
import 'binary_path_provider.dart';

/// Provides [YtdlpService] with the resolved binary path.
///
/// Depends on [binaryPathProvider] and throws if the binary is not ready.
final Provider<YtdlpService> ytdlpServiceProvider = Provider<YtdlpService>((
  Ref ref,
) {
  final String binaryPath = ref.watch(binaryPathProvider).requireValue;
  return YtdlpService(binaryPath: binaryPath);
});

/// Current URL string typed in the home field (draft, not yet searched).
final StateProvider<String> urlInputProvider = StateProvider<String>(
  (Ref ref) => '',
);

/// URL last submitted via Search; empty until user searches.
///
/// Metadata providers watch this so fetches do not run on every keystroke.
final StateProvider<String> metadataRequestUrlProvider = StateProvider<String>(
  (Ref ref) => '',
);

/// Selected download format from the home dropdown.
final StateProvider<VideoFormat?> selectedFormatProvider =
    StateProvider<VideoFormat?>((Ref ref) => null);

/// Fetches formats for [metadataRequestUrlProvider] when non-empty.
final formatsProvider = FutureProvider.autoDispose<List<VideoFormat>>((
  Ref ref,
) async {
  final String url = ref.watch(metadataRequestUrlProvider);
  if (url.isEmpty) {
    return <VideoFormat>[];
  }
  final YtdlpService service = ref.watch(ytdlpServiceProvider);
  return service.fetchFormats(url);
});

/// Fetches [VideoInfo] for the submitted URL when non-empty.
final videoInfoProvider = FutureProvider.autoDispose<VideoInfo?>((
  Ref ref,
) async {
  final String url = ref.watch(metadataRequestUrlProvider);
  if (url.isEmpty) {
    return null;
  }
  final YtdlpService service = ref.watch(ytdlpServiceProvider);
  return service.fetchVideoInfo(url);
});

/// Loads [PlaylistInfo] when the submitted URL is a playlist.
final playlistInfoProvider = FutureProvider.autoDispose<PlaylistInfo?>((
  Ref ref,
) async {
  final String url = ref.watch(metadataRequestUrlProvider);
  if (url.isEmpty) {
    return null;
  }
  final YtdlpService service = ref.watch(ytdlpServiceProvider);
  final bool isPlaylist = await service.isPlaylistUrl(url);
  if (!isPlaylist) {
    return null;
  }
  return service.fetchPlaylistInfo(url);
});

/// Whether the submitted URL is detected as a playlist.
final isPlaylistProvider = FutureProvider.autoDispose<bool>((Ref ref) async {
  final String url = ref.watch(metadataRequestUrlProvider);
  if (url.isEmpty) {
    return false;
  }
  final YtdlpService service = ref.watch(ytdlpServiceProvider);
  return service.isPlaylistUrl(url);
});
