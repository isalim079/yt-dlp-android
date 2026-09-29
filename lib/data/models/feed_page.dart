/// One page of a paginated browse feed (Home / Shorts).
library;

import 'browse_video.dart';

/// Items plus an opaque InnerTube / NewPipe continuation token.
class FeedPage {
  /// Creates a feed page.
  const FeedPage({
    required this.items,
    this.continuation,
  });

  /// Videos on this page.
  final List<BrowseVideo> items;

  /// Opaque token for the next page; `null` / empty means no more.
  final String? continuation;

  /// Whether another page can be requested.
  bool get hasMore {
    final String? token = continuation;
    return token != null && token.isNotEmpty;
  }

  /// Empty exhausted page.
  static const FeedPage empty = FeedPage(items: <BrowseVideo>[]);

  /// Parses platform-channel / JSON map.
  factory FeedPage.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    final List<BrowseVideo> items = <BrowseVideo>[];
    if (rawItems is List<dynamic>) {
      for (final dynamic row in rawItems) {
        if (row is Map) {
          final BrowseVideo? video = BrowseVideo.tryFromFeedJson(
            Map<String, dynamic>.from(row),
          );
          if (video != null) {
            items.add(video);
          }
        }
      }
    }
    final String? continuation = json['continuation']?.toString();
    return FeedPage(
      items: items,
      continuation: (continuation == null || continuation.isEmpty)
          ? null
          : continuation,
    );
  }

  /// JSON map for tests / logging (no secrets beyond opaque token).
  Map<String, dynamic> toJson() => <String, dynamic>{
        'items': items.map((BrowseVideo v) => v.toFeedJson()).toList(),
        'continuation': continuation,
      };
}
