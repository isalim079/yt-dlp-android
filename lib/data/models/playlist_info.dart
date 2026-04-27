/// Flat playlist metadata from yt-dlp `--flat-playlist` JSON.
library;

/// One row in a flat playlist listing.
class PlaylistEntry {
  /// Creates a [PlaylistEntry].
  const PlaylistEntry({required this.title, required this.url});

  /// Entry title when known.
  final String title;

  /// Direct URL for the entry.
  final String url;
}

/// Summary of a playlist and a preview of its entries.
class PlaylistInfo {
  /// Creates [PlaylistInfo].
  const PlaylistInfo({
    required this.title,
    required this.count,
    required this.entries,
    required this.url,
  });

  /// Playlist title from the extractor.
  final String title;

  /// Number of videos reported in the playlist.
  final int count;

  /// First page of entries (as returned by yt-dlp).
  final List<PlaylistEntry> entries;

  /// Web URL for the playlist.
  final String url;
}
