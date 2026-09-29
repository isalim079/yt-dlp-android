/// Remote download job repository.
library;

import 'yxz_api_client.dart';

/// Server-side download enqueue + status.
class DownloadApiRepository {
  /// Creates the repository.
  DownloadApiRepository(this._client);

  final YxzApiClient _client;

  /// `POST /api/v1/downloads`.
  Future<Map<String, dynamic>> enqueue({
    required String videoId,
    String quality = '1080p',
    String format = 'mp4',
  }) {
    return _client.postJson(
      '/api/v1/downloads',
      body: <String, dynamic>{
        'videoId': videoId,
        'quality': quality,
        'format': format,
      },
    );
  }

  /// `GET /api/v1/downloads/:jobId`.
  Future<Map<String, dynamic>> status(String jobId) {
    return _client.getJson('/api/v1/downloads/$jobId');
  }
}
