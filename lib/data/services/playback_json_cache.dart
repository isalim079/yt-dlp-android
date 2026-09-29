/// In-memory yt-dlp `-J` bodies keyed by URL and player client (not quality).
library;

/// Shared cache so quality changes re-parse JSON instead of extracting again.
class PlaybackJsonCache {
  /// Creates an empty cache with optional [ttl] (default 45 minutes).
  PlaybackJsonCache({this.ttl = const Duration(minutes: 45)});

  /// How long a cached body stays valid.
  final Duration ttl;

  final Map<String, _CacheEntry> _bodies = <String, _CacheEntry>{};

  /// How many times a body was loaded because it was missing or stale.
  int missCount = 0;

  /// Cache key: URL plus extractor client, never quality.
  static String key(String url, String playerClient) => '$url|$playerClient';

  /// Cached JSON for [url] and [playerClient], if any and not expired.
  String? read(String url, String playerClient) {
    final _CacheEntry? entry = _bodies[key(url, playerClient)];
    if (entry == null) {
      return null;
    }
    if (DateTime.now().difference(entry.at) > ttl) {
      _bodies.remove(key(url, playerClient));
      return null;
    }
    return entry.body;
  }

  /// Stores [body] for later [read] / [remember] hits.
  void put(String url, String playerClient, String body) {
    _bodies[key(url, playerClient)] = _CacheEntry(
      body: body,
      at: DateTime.now(),
    );
  }

  /// Drops one strategy key (e.g. before 403 re-extract).
  void invalidate(String url, String playerClient) {
    _bodies.remove(key(url, playerClient));
  }

  /// Drops every entry whose key starts with [url]| (all strategies for URL).
  void invalidateUrl(String url) {
    final String prefix = '$url|';
    _bodies.removeWhere((String k, _CacheEntry _) => k.startsWith(prefix));
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

class _CacheEntry {
  const _CacheEntry({required this.body, required this.at});

  final String body;
  final DateTime at;
}
