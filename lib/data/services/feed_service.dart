/// Home / Shorts feed facade: NewPipe on Android, yt-dlp fallback elsewhere.
library;

import '../../core/utils/logger.dart';
import '../../core/utils/youtube_urls.dart';
import '../models/browse_video.dart';
import '../models/feed_page.dart';
import '../models/playlist_info.dart';
import 'browse_service.dart';
import 'feed_platform_channel.dart';
import 'ytdlp_service.dart';

/// Loads paginated browse feeds.
class FeedService {
  /// Creates a feed service.
  const FeedService({required this.ytdlp});

  /// yt-dlp for desktop fallback and enrichment.
  final YtdlpService ytdlp;

  /// Home feed page (trending kiosk + optional continuation).
  Future<FeedPage> homeFeed({String? continuation}) async {
    if (FeedPlatformChannel.isSupported) {
      try {
        final FeedPage page = await FeedPlatformChannel.fetchHomeFeed(
          continuation: continuation,
        );
        AppLogger.i(
          'feed=home items=${page.items.length} '
          'hasMore=${page.hasMore} via=newpipe',
        );
        if (page.items.isNotEmpty || continuation != null) {
          return page;
        }
      } on Object catch (error, stack) {
        AppLogger.w('NewPipe home feed failed: $error\n$stack');
      }
    }
    return _ytdlpHomeFallback(continuation: continuation);
  }

  /// Shorts feed page.
  Future<FeedPage> shortsFeed({String? continuation}) async {
    if (FeedPlatformChannel.isSupported) {
      try {
        final FeedPage page = await FeedPlatformChannel.fetchShortsFeed(
          continuation: continuation,
        );
        AppLogger.i(
          'feed=shorts items=${page.items.length} '
          'hasMore=${page.hasMore} via=newpipe',
        );
        if (page.items.isNotEmpty || continuation != null) {
          return page;
        }
      } on Object catch (error, stack) {
        AppLogger.w('NewPipe shorts feed failed: $error\n$stack');
      }
    }
    return _ytdlpShortsFallback(continuation: continuation);
  }

  /// Desktop / failure path: paged popular ytsearch windows.
  Future<FeedPage> _ytdlpHomeFallback({String? continuation}) async {
    final int pageIndex = int.tryParse(continuation ?? '0') ?? 0;
    final int start = pageIndex * 20 + 1;
    final int end = start + 19;
    try {
      final String source = YoutubeUrls.popularSources[
          pageIndex % YoutubeUrls.popularSources.length];
      final PlaylistInfo info = await ytdlp.fetchFlatListing(source);
      final List<BrowseVideo> all =
          info.entries.map(BrowseVideo.fromPlaylistEntry).toList();
      // yt-dlp already capped; slice by synthetic page for "more" UX.
      final List<BrowseVideo> slice = all.length >= start
          ? all.sublist(
              (start - 1).clamp(0, all.length),
              end.clamp(0, all.length),
            )
          : all;
      final bool more = all.length > end || pageIndex < 2;
      AppLogger.i(
        'feed=home items=${slice.length} hasMore=$more via=ytdlp page=$pageIndex',
      );
      return FeedPage(
        items: slice,
        continuation: more ? '${pageIndex + 1}' : null,
      );
    } on Object catch (error, stack) {
      AppLogger.w('yt-dlp home fallback failed: $error\n$stack');
      return FeedPage.empty;
    }
  }

  Future<FeedPage> _ytdlpShortsFallback({String? continuation}) async {
    // One-shot search only — never re-serve the same ytsearch set as "page 2".
    if (continuation != null && continuation.isNotEmpty) {
      AppLogger.i('feed=shorts items=0 hasMore=false via=ytdlp exhausted');
      return FeedPage.empty;
    }
    try {
      final BrowseService browse = BrowseService(ytdlp: ytdlp);
      final List<BrowseVideo> raw = await browse.search(
        'shorts',
        count: 25,
      );
      final List<BrowseVideo> shorts = raw
          .where(
            (BrowseVideo v) =>
                v.isShort ||
                v.duration == null ||
                v.duration! <= 0 ||
                v.duration! <= 60,
          )
          .toList();
      final List<BrowseVideo> use =
          shorts.isNotEmpty ? shorts : raw.take(20).toList();
      AppLogger.i(
        'feed=shorts items=${use.length} hasMore=false via=ytdlp',
      );
      return FeedPage(items: use);
    } on Object catch (error, stack) {
      AppLogger.w('yt-dlp shorts fallback failed: $error\n$stack');
      return FeedPage.empty;
    }
  }
}
