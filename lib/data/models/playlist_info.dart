/// Flat playlist metadata from yt-dlp `--flat-playlist` JSON.
library;

/// One row in a flat playlist listing.
class PlaylistEntry {
  /// Creates a [PlaylistEntry].
  const PlaylistEntry({
    required this.title,
    required this.url,
    this.id,
    this.thumbnail,
    this.duration,
    this.uploader,
    this.channelUrl,
  });

  /// Entry title when known.
  final String title;

  /// Direct URL for the entry.
  final String url;

  /// YouTube video id when present in flat JSON.
  final String? id;

  /// Thumbnail URL when present.
  final String? thumbnail;

  /// Duration in seconds when present.
  final int? duration;

  /// Uploader / channel display name.
  final String? uploader;

  /// Channel URL when present.
  final String? channelUrl;
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
