/// Remote playback repository.
library;

import '../../models/playback_manifest.dart';
import '../../models/playback_resolved.dart';
import 'yxz_api_client.dart';

/// Fetches [PlaybackManifest] from the production API.
class PlaybackApiRepository {
  /// Creates the repository.
  PlaybackApiRepository(this._client);

  final YxzApiClient _client;

  /// `GET /api/v1/videos/:id/playback`.
  Future<PlaybackManifest> fetchPlayback({
    required String videoId,
    PlaybackQuality quality = PlaybackQuality.auto,
    bool forceRefresh = false,
  }) async {
    final Map<String, String> query = <String, String>{
      'quality': _qualityParam(quality),
      'codec': 'auto',
      'audioLanguage': 'auto',
      'hdr': 'auto',
      if (forceRefresh) 'forceRefresh': 'true',
    };
    final Map<String, dynamic> json = await _client.getJson(
      '/api/v1/videos/$videoId/playback',
      query: query,
    );
    return PlaybackManifest.fromJson(json);
  }

  static String _qualityParam(PlaybackQuality q) {
    return switch (q) {
      PlaybackQuality.auto => 'auto',
      PlaybackQuality.p360 => '360p',
      PlaybackQuality.p480 => '480p',
      PlaybackQuality.p720 => '720p',
      PlaybackQuality.p1080 => '1080p',
      PlaybackQuality.p1440 => '1440p',
      PlaybackQuality.p2160 => '2160p',
    };
  }
}
