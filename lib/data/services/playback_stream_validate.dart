/// Lightweight HTTP probe for selected playback URLs before media_kit open.
library;

import 'dart:io';

import '../../core/utils/logger.dart';
import '../models/playback_resolved.dart';

/// Result of probing video/audio/progressive URLs.
class StreamValidationResult {
  /// Creates a validation result.
  const StreamValidationResult({
    required this.ok,
    this.videoStatus,
    this.audioStatus,
    this.progressiveStatus,
    this.detail,
  });

  /// True when required URLs for [PlaybackResolved.mode] look fetchable.
  final bool ok;

  /// HTTP status for video URL when probed.
  final int? videoStatus;

  /// HTTP status for audio URL when probed.
  final int? audioStatus;

  /// HTTP status for progressive URL when probed.
  final int? progressiveStatus;

  /// Short failure reason.
  final String? detail;
}

/// Probe selected stream URLs (Range GET). Does not download the body.
Future<StreamValidationResult> validatePlaybackStreams(
  PlaybackResolved resolved, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final HttpClient client = HttpClient();
  client.connectionTimeout = timeout;
  try {
    switch (resolved.mode) {
      case PlaybackMode.adaptive:
        final int? v = await _probe(
          client,
          resolved.videoUrl,
          resolved.headers,
          timeout,
        );
        final int? a = await _probe(
          client,
          resolved.audioUrl,
          resolved.headers,
          timeout,
        );
        final bool ok = _ok(v) && _ok(a);
        AppLogger.i(
          'stream validate adaptive video=$v audio=$a ok=$ok',
        );
        return StreamValidationResult(
          ok: ok,
          videoStatus: v,
          audioStatus: a,
          detail: ok ? null : 'adaptive video/audio probe failed',
        );
      case PlaybackMode.progressive:
        final int? p = await _probe(
          client,
          resolved.progressiveUrl,
          resolved.headers,
          timeout,
        );
        AppLogger.i('stream validate progressive=$p');
        return StreamValidationResult(
          ok: _ok(p),
          progressiveStatus: p,
          detail: _ok(p) ? null : 'progressive probe failed',
        );
      case PlaybackMode.hls:
        final int? h = await _probe(
          client,
          resolved.hlsUrl,
          resolved.headers,
          timeout,
        );
        AppLogger.i('stream validate hls=$h');
        return StreamValidationResult(
          ok: _ok(h),
          progressiveStatus: h,
          detail: _ok(h) ? null : 'hls probe failed',
        );
    }
  } finally {
    client.close(force: true);
  }
}

bool _ok(int? status) {
  if (status == null) {
    return false;
  }
  return status >= 200 && status < 400;
}

Future<int?> _probe(
  HttpClient client,
  String? url,
  Map<String, String> headers,
  Duration timeout,
) async {
  if (url == null || url.isEmpty || !url.startsWith('http')) {
    return null;
  }
  try {
    final Uri uri = Uri.parse(url);
    final HttpClientRequest req = await client.getUrl(uri).timeout(timeout);
    headers.forEach(req.headers.set);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
    final HttpClientResponse res = await req.close().timeout(timeout);
    // Drain a tiny bit then abort.
    await res.drain<void>().timeout(const Duration(seconds: 2));
    return res.statusCode;
  } on Object catch (e) {
    AppLogger.w('stream probe failed: $e');
    return null;
  }
}
