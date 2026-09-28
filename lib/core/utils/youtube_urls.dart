/// Helpers for YouTube watch URLs, video IDs, and browse sources.
library;

/// Parses and normalizes YouTube identifiers and listing sources.
abstract final class YoutubeUrls {
  static final RegExp _videoIdPattern = RegExp(
    r'(?:v=|/shorts/|/embed/|youtu\.be/)([A-Za-z0-9_-]{11})',
  );
  static final RegExp _bareId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final RegExp _channelId = RegExp(r'/channel/([A-Za-z0-9_-]+)');
  static final RegExp _handle = RegExp(r'youtube\.com/@([^/?]+)');

  /// Extracts an 11-character video id from a URL or bare id.
  static String? videoId(String input) {
    final String trimmed = input.trim();
    if (_bareId.hasMatch(trimmed)) {
      return trimmed;
    }
    return _videoIdPattern.firstMatch(trimmed)?.group(1);
  }

  /// Canonical `watch?v=` URL for [idOrUrl].
  static String watchUrl(String idOrUrl) {
    final String? id = videoId(idOrUrl);
    if (id != null) {
      return 'https://www.youtube.com/watch?v=$id';
    }
    if (idOrUrl.startsWith('http://') || idOrUrl.startsWith('https://')) {
      return idOrUrl;
    }
    return 'https://www.youtube.com/watch?v=$idOrUrl';
  }

  /// Default thumbnail for a video id.
  static String thumbnailFor(String id) {
    return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  }

  /// Ordered Home "Popular" sources for yt-dlp `--flat-playlist`.
  ///
  /// YouTube's `/feed/trending` now redirects logged-out clients to the
  /// homepage, which the `youtube:tab` extractor rejects. Search prefixes
  /// still work with the same listing path as the Search tab.
  static const List<String> popularSources = <String>[
    'ytsearchdate25:music',
    'ytsearchdate25:gaming',
    'ytsearch25:music',
  ];

  /// yt-dlp search prefix for [query].
  static String searchSource(String query, {int count = 20}) {
    return 'ytsearch$count:${query.trim()}';
  }

  /// Whether [source] is a yt-dlp search prefix rather than an HTTP URL.
  static bool isSearchSource(String source) {
    return source.startsWith('ytsearch');
  }

  /// Channel videos listing URL when a channel id or handle can be parsed.
  static String? channelVideosUrl(String input) {
    final String trimmed = input.trim();
    final Match? idMatch = _channelId.firstMatch(trimmed);
    if (idMatch != null) {
      return 'https://www.youtube.com/channel/${idMatch.group(1)}/videos';
    }
    final Match? handleMatch = _handle.firstMatch(trimmed);
    if (handleMatch != null) {
      return 'https://www.youtube.com/@${handleMatch.group(1)}/videos';
    }
    if (trimmed.contains('youtube.com/') &&
        (trimmed.contains('/videos') ||
            trimmed.contains('/@') ||
            trimmed.contains('/channel/'))) {
      return trimmed;
    }
    return null;
  }

  /// Best-effort channel id from a URL.
  static String? channelId(String input) {
    return _channelId.firstMatch(input)?.group(1) ??
        _handle.firstMatch(input)?.group(1);
  }
}
