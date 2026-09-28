/// In-memory yt-dlp `-J` bodies keyed by URL and player client (not quality).
library;

/// Shared cache so quality changes re-parse JSON instead of extracting again.
class PlaybackJsonCache {
  /// Creates an empty cache.
  PlaybackJsonCache();

  final Map<String, String> _bodies = <String, String>{};

  /// How many times a body was loaded because it was missing.
  int missCount = 0;

  /// Cache key: URL plus extractor client, never quality.
  static String key(String url, String playerClient) => '$url|$playerClient';

  /// Cached JSON for [url] and [playerClient], if any.
  String? read(String url, String playerClient) {
    return _bodies[key(url, playerClient)];
  }

  /// Stores [body] for later [read] / [remember] hits.
  void put(String url, String playerClient, String body) {
    _bodies[key(url, playerClient)] = body;
  }

  /// Returns cached JSON or loads it once and stores the result.
  Future<String> remember({
    required String url,
    required String playerClient,
    required Future<String> Function() load,
  }) async {
    final String? cached = read(url, playerClient);
    if (cached != null) {
      return cached;
    }
    missCount += 1;
    final String body = await load();
    put(url, playerClient, body);
    return body;
  }

  /// Drops all entries (tests / hard refresh).
  void clear() {
    _bodies.clear();
    missCount = 0;
  }
}
