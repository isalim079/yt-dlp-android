/// A lightweight video row used by Home, Search, History, and Playlists.
library;

import '../../core/constants/app_strings.dart';
import '../../core/utils/youtube_urls.dart';
import 'playlist_info.dart';
import 'video_info.dart';

/// Catalog item that can be played or downloaded without a full `-J` fetch.
class BrowseVideo {
  /// Creates a browse row.
  const BrowseVideo({
    required this.id,
    required this.title,
    required this.url,
    this.thumbnail,
    this.uploader,
    this.duration,
    this.channelUrl,
    this.isShort = false,
  });

  /// YouTube video id when known.
  final String id;

  /// Display title.
  final String title;

  /// Watch URL.
  final String url;

  /// Thumbnail URL.
  final String? thumbnail;

  /// Channel or uploader name.
  final String? uploader;

  /// Duration in seconds.
  final int? duration;

  /// Channel videos URL when known.
  final String? channelUrl;

  /// True when NewPipe / duration marks this as a Short.
  final bool isShort;

  /// Compact `MM:SS` / `HH:MM:SS` duration.
  String get formattedDuration {
    if (duration == null) {
      return AppStrings.notAvailable;
    }
    final int total = duration!;
    final int hours = total ~/ 3600;
    final int minutes = (total % 3600) ~/ 60;
    final int seconds = total % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${two(hours)}:${two(minutes)}:${two(seconds)}';
    }
    return '${two(minutes)}:${two(seconds)}';
  }

  /// Builds a row from a flat playlist entry.
  factory BrowseVideo.fromPlaylistEntry(PlaylistEntry entry) {
    final String id =
        entry.id ?? YoutubeUrls.videoId(entry.url) ?? entry.url;
    final String watch = YoutubeUrls.watchUrl(entry.url.isEmpty ? id : entry.url);
    final int? dur = entry.duration;
    return BrowseVideo(
      id: id,
      title: entry.title,
      url: watch,
      thumbnail: entry.thumbnail ??
          (YoutubeUrls.videoId(watch) != null
              ? YoutubeUrls.thumbnailFor(YoutubeUrls.videoId(watch)!)
              : null),
      uploader: entry.uploader,
      duration: dur,
      channelUrl: entry.channelUrl,
      isShort: dur != null && dur > 0 && dur <= 60,
    );
  }

  /// Builds a row from resolved [VideoInfo].
  factory BrowseVideo.fromVideoInfo(VideoInfo info) {
    final String id = YoutubeUrls.videoId(info.url) ?? info.url;
    final int? dur = info.duration;
    return BrowseVideo(
      id: id,
      title: info.title,
      url: info.url,
      thumbnail: info.thumbnail,
      uploader: info.uploader,
      duration: dur,
      channelUrl: info.channelUrl,
      isShort: dur != null && dur > 0 && dur <= 60,
    );
  }

  /// Parses one feed JSON item from NewPipe / platform channel.
  static BrowseVideo? tryFromFeedJson(Map<String, dynamic> json) {
    final String id = json['id']?.toString() ?? '';
    final String title = json['title']?.toString() ?? '';
    String url = json['url']?.toString() ?? '';
    if (id.isEmpty && url.isEmpty) {
      return null;
    }
    final String resolvedId = id.isNotEmpty ? id : (YoutubeUrls.videoId(url) ?? '');
    if (resolvedId.isEmpty) {
      return null;
    }
    if (url.isEmpty) {
      url = YoutubeUrls.watchUrl(resolvedId);
    } else {
      url = YoutubeUrls.watchUrl(url);
    }
    final int? duration = json['duration'] is num
        ? (json['duration'] as num).toInt()
        : int.tryParse(json['duration']?.toString() ?? '');
    final bool flagged = json['isShort'] == true;
    return BrowseVideo(
      id: resolvedId,
      title: title.isEmpty ? resolvedId : title,
      url: url,
      thumbnail: json['thumbnail']?.toString() ??
          YoutubeUrls.thumbnailFor(resolvedId),
      uploader: json['uploader']?.toString(),
      duration: duration,
      channelUrl: json['channelUrl']?.toString(),
      isShort: flagged || (duration != null && duration > 0 && duration <= 60),
    );
  }

  /// Feed JSON for tests / round-trip.
  Map<String, dynamic> toFeedJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'url': url,
        'thumbnail': thumbnail,
        'uploader': uploader,
        'duration': duration,
        'channelUrl': channelUrl,
        'isShort': isShort,
      };
}
