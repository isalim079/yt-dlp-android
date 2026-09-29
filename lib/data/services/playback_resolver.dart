/// Picks playable adaptive / progressive / HLS URLs from yt-dlp `-J` JSON.
///
/// Internally builds a [PlaybackManifest] (architecture §5) then selects
/// streams — Flutter callers still receive [PlaybackResolved] for media_kit.
library;

import '../models/playback_manifest.dart';
import '../models/playback_resolved.dart';
import 'playback_manifest_builder.dart';
import 'playback_manifest_selector.dart';

/// Pure parser: JSON in, [PlaybackResolved] out. Never runs yt-dlp.
abstract final class PlaybackResolver {
  /// Resolves streams for [quality] from a full yt-dlp `-J` body.
  static PlaybackResolved fromJson(
    String jsonString, {
    PlaybackQuality quality = PlaybackQuality.auto,
  }) {
    final PlaybackManifest manifest =
        PlaybackManifestBuilder.fromYtDlpJson(jsonString);
    return PlaybackManifestSelector.select(manifest, quality: quality);
  }

  /// Builds the normalized app manifest without selecting a quality.
  static PlaybackManifest manifestFromJson(String jsonString) {
    return PlaybackManifestBuilder.fromYtDlpJson(jsonString);
  }
}
