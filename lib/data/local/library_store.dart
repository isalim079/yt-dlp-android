/// Local SQLite store for watch history, playlists, and followed channels.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/utils/youtube_urls.dart';
import '../models/browse_video.dart';

/// One watch-history row.
class WatchHistoryEntry {
  /// Creates a history row.
  const WatchHistoryEntry({
    required this.video,
    required this.lastPositionMs,
    required this.watchedAt,
  });

  /// Video metadata.
  final BrowseVideo video;

  /// Resume position in milliseconds.
  final int lastPositionMs;

  /// Last watch timestamp.
  final DateTime watchedAt;
}

/// A user-created (or imported) playlist.
class LocalPlaylist {
  /// Creates a playlist.
  const LocalPlaylist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.items = const <BrowseVideo>[],
  });

  /// Stable id.
  final String id;

  /// Display name.
  final String name;

  /// Creation time.
  final DateTime createdAt;

  /// Ordered videos.
  final List<BrowseVideo> items;
}

/// A followed channel.
class FollowedChannel {
  /// Creates a followed channel.
  const FollowedChannel({
    required this.id,
    required this.title,
    required this.url,
    this.thumbnail,
    required this.followedAt,
  });

  /// Channel id or handle.
  final String id;

  /// Display title.
  final String title;

  /// Channel videos URL.
  final String url;

  /// Optional avatar/thumb.
  final String? thumbnail;

  /// Follow time.
  final DateTime followedAt;
}

/// SQLite-backed library.
class LibraryStore {
  LibraryStore._();

  static LibraryStore? _instance;

  /// Process-wide singleton.
  static LibraryStore get instance => _instance ??= LibraryStore._();

  Database? _db;

  Future<Database> get _database async {
    final Database? existing = _db;
    if (existing != null) {
      return existing;
    }
    try {
      final String dir = await getDatabasesPath();
      final String path = p.join(dir, 'yt_library.db');
      final Database db = await openDatabase(
      path,
      version: 2,
      onCreate: (Database database, int version) async {
        await _createV1Tables(database);
        await _createSearchHistoryTable(database);
      },
      onUpgrade: (Database database, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await _createSearchHistoryTable(database);
        }
      },
    );
      _db = db;
      return db;
    } on Object {
      rethrow;
    }
  }

  /// Upserts history and resume position.
  Future<void> upsertHistory({
    required BrowseVideo video,
    required int lastPositionMs,
  }) async {
    final Database db = await _database;
    await db.insert('watch_history', <String, Object?>{
      'video_id': video.id,
      'title': video.title,
      'url': video.url,
      'thumbnail': video.thumbnail,
      'uploader': video.uploader,
      'duration': video.duration,
      'channel_url': video.channelUrl,
      'last_position_ms': lastPositionMs,
      'watched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Recent history, newest first.
  Future<List<WatchHistoryEntry>> history({int limit = 50}) async {
    final Database db = await _database;
    final List<Map<String, Object?>> rows = await db.query(
      'watch_history',
      orderBy: 'watched_at DESC',
      limit: limit,
    );
    return rows.map(_historyFromRow).toList();
  }

  /// Incomplete watches for Continue watching.
  Future<List<WatchHistoryEntry>> continueWatching({int limit = 12}) async {
    final Database db = await _database;
    final List<Map<String, Object?>> rows = await db.query(
      'watch_history',
      where: 'last_position_ms > 5000',
      orderBy: 'watched_at DESC',
      limit: limit,
    );
    return rows.map(_historyFromRow).where((WatchHistoryEntry e) {
      final int? dur = e.video.duration;
      if (dur == null || dur <= 0) {
        return true;
      }
      return e.lastPositionMs < (dur * 1000) - 8000;
    }).toList();
  }

  /// Resume position for [videoId], or 0.
  Future<int> positionFor(String videoId) async {
    final Database db = await _database;
    final List<Map<String, Object?>> rows = await db.query(
      'watch_history',
      columns: <String>['last_position_ms'],
      where: 'video_id = ?',
      whereArgs: <Object>[videoId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['last_position_ms'] as int?) ?? 0;
  }

  /// Deletes all watch history.
  Future<void> clearHistory() async {
    final Database db = await _database;
    await db.delete('watch_history');
  }

  /// Deletes one watch-history row. Does not delete downloaded files.
  Future<void> deleteHistory(String videoId) async {
    final Database db = await _database;
    await db.delete(
      'watch_history',
      where: 'video_id = ?',
      whereArgs: <Object>[videoId],
    );
  }

  /// Creates a playlist and returns its id.
  Future<String> createPlaylist(String name) async {
    final Database db = await _database;
    final String id = DateTime.now().microsecondsSinceEpoch.toString();
    await db.insert('local_playlists', <String, Object?>{
      'id': id,
      'name': name.trim().isEmpty ? 'Playlist' : name.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  /// All playlists with items.
  Future<List<LocalPlaylist>> playlists() async {
    final Database db = await _database;
    final List<Map<String, Object?>> rows = await db.query(
      'local_playlists',
      orderBy: 'created_at DESC',
    );
    final List<LocalPlaylist> out = <LocalPlaylist>[];
    for (final Map<String, Object?> row in rows) {
      final String id = row['id']!.toString();
      out.add(
        LocalPlaylist(
          id: id,
          name: row['name']!.toString(),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            (row['created_at'] as int?) ?? 0,
          ),
          items: await playlistItems(id),
        ),
      );
    }
    return out;
  }

  /// Items in playlist [playlistId] in order.
  Future<List<BrowseVideo>> playlistItems(String playlistId) async {
    final Database db = await _database;
    final List<Map<String, Object?>> rows = await db.query(
      'playlist_items',
      where: 'playlist_id = ?',
      whereArgs: <Object>[playlistId],
      orderBy: 'sort_index ASC',
    );
    return rows.map(_videoFromPlaylistRow).toList();
  }

  /// Appends [video] to a playlist.
  Future<void> addToPlaylist(String playlistId, BrowseVideo video) async {
    final Database db = await _database;
    final List<Map<String, Object?>> countRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM playlist_items WHERE playlist_id = ?',
      <Object>[playlistId],
    );
    final int index = (countRows.first['c'] as int?) ?? 0;
    await db.insert('playlist_items', <String, Object?>{
      'playlist_id': playlistId,
      'video_id': video.id,
      'title': video.title,
      'url': video.url,
      'thumbnail': video.thumbnail,
      'uploader': video.uploader,
      'duration': video.duration,
      'channel_url': video.channelUrl,
      'sort_index': index,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Removes a video from a playlist.
  Future<void> removeFromPlaylist(String playlistId, String videoId) async {
    final Database db = await _database;
    await db.delete(
      'playlist_items',
      where: 'playlist_id = ? AND video_id = ?',
      whereArgs: <Object>[playlistId, videoId],
    );
  }

  /// Deletes a playlist and its items.
  Future<void> deletePlaylist(String playlistId) async {
    final Database db = await _database;
    await db.delete(
      'playlist_items',
      where: 'playlist_id = ?',
      whereArgs: <Object>[playlistId],
    );
    await db.delete(
      'local_playlists',
      where: 'id = ?',
      whereArgs: <Object>[playlistId],
    );
  }

  /// Follows a channel.
  Future<void> followChannel(FollowedChannel channel) async {
    final Database db = await _database;
    await db.insert('followed_channels', <String, Object?>{
      'channel_id': channel.id,
      'title': channel.title,
      'url': channel.url,
      'thumbnail': channel.thumbnail,
      'followed_at': channel.followedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Unfollows a channel.
  Future<void> unfollowChannel(String channelId) async {
    final Database db = await _database;
    await db.delete(
      'followed_channels',
      where: 'channel_id = ?',
      whereArgs: <Object>[channelId],
    );
  }

  /// All followed channels.
  Future<List<FollowedChannel>> channels() async {
    final Database db = await _database;
    final List<Map<String, Object?>> rows = await db.query(
      'followed_channels',
      orderBy: 'followed_at DESC',
    );
    return rows
        .map(
          (Map<String, Object?> row) => FollowedChannel(
            id: row['channel_id']!.toString(),
            title: row['title']!.toString(),
            url: row['url']!.toString(),
            thumbnail: row['thumbnail']?.toString(),
            followedAt: DateTime.fromMillisecondsSinceEpoch(
              (row['followed_at'] as int?) ?? 0,
            ),
          ),
        )
        .toList();
  }

  /// Saves [query] to recent searches, moving it to the top if it already exists.
  Future<void> addSearch(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final Database db = await _database;
    await db.insert('search_history', <String, Object?>{
      'query': trimmed,
      'searched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Recent search keywords, newest first.
  Future<List<String>> recentSearches({int limit = 20}) async {
    final Database db = await _database;
    final List<Map<String, Object?>> rows = await db.query(
      'search_history',
      columns: <String>['query'],
      orderBy: 'searched_at DESC',
      limit: limit,
    );
    return rows
        .map((Map<String, Object?> row) => row['query']?.toString() ?? '')
        .where((String q) => q.isNotEmpty)
        .toList();
  }

  /// Removes one saved search keyword.
  Future<void> deleteSearch(String query) async {
    final Database db = await _database;
    await db.delete(
      'search_history',
      where: 'query = ?',
      whereArgs: <Object>[query],
    );
  }

  /// Deletes all saved search keywords.
  Future<void> clearSearches() async {
    final Database db = await _database;
    await db.delete('search_history');
  }

  static Future<void> _createV1Tables(Database database) async {
    await database.execute('''
CREATE TABLE watch_history (
  video_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  thumbnail TEXT,
  uploader TEXT,
  duration INTEGER,
  channel_url TEXT,
  last_position_ms INTEGER NOT NULL DEFAULT 0,
  watched_at INTEGER NOT NULL
)
''');
    await database.execute('''
CREATE TABLE local_playlists (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''');
    await database.execute('''
CREATE TABLE playlist_items (
  playlist_id TEXT NOT NULL,
  video_id TEXT NOT NULL,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  thumbnail TEXT,
  uploader TEXT,
  duration INTEGER,
  channel_url TEXT,
  sort_index INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, video_id)
)
''');
    await database.execute('''
CREATE TABLE followed_channels (
  channel_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  thumbnail TEXT,
  followed_at INTEGER NOT NULL
)
''');
  }

  static Future<void> _createSearchHistoryTable(Database database) async {
    await database.execute('''
CREATE TABLE search_history (
  query TEXT PRIMARY KEY,
  searched_at INTEGER NOT NULL
)
''');
  }

  WatchHistoryEntry _historyFromRow(Map<String, Object?> row) {
    return WatchHistoryEntry(
      video: BrowseVideo(
        id: row['video_id']!.toString(),
        title: row['title']!.toString(),
        url: row['url']?.toString() ??
            YoutubeUrls.watchUrl(row['video_id']!.toString()),
        thumbnail: row['thumbnail']?.toString(),
        uploader: row['uploader']?.toString(),
        duration: row['duration'] as int?,
        channelUrl: row['channel_url']?.toString(),
      ),
      lastPositionMs: (row['last_position_ms'] as int?) ?? 0,
      watchedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['watched_at'] as int?) ?? 0,
      ),
    );
  }

  BrowseVideo _videoFromPlaylistRow(Map<String, Object?> row) {
    return BrowseVideo(
      id: row['video_id']!.toString(),
      title: row['title']!.toString(),
      url: row['url']!.toString(),
      thumbnail: row['thumbnail']?.toString(),
      uploader: row['uploader']?.toString(),
      duration: row['duration'] as int?,
      channelUrl: row['channel_url']?.toString(),
    );
  }
}
