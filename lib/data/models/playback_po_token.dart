/// Player + GVS Web PO tokens minted by BotGuard (youtube.com mechanism).
library;

/// Pair of content-bound player and session-bound GVS tokens.
class PlaybackPoToken {
  /// Creates a minted token pair.
  const PlaybackPoToken({
    required this.player,
    required this.gvs,
    required this.visitorData,
  });

  /// Bound to the video ID (`serviceIntegrityDimensions.poToken`).
  final String player;

  /// Bound to visitor data (googlevideo `pot=`).
  final String gvs;

  /// Visitor data used as the GVS content binding.
  final String visitorData;

  /// Whether this mint is usable with yt-dlp + `visitor_data`.
  bool get isComplete =>
      player.isNotEmpty && gvs.isNotEmpty && visitorData.isNotEmpty;

  /// Default extractor arg for the web BotGuard mint (`mweb`).
  String get extractorValue => extractorValueFor('mweb');

  /// Client-scoped yt-dlp `po_token` value.
  ///
  /// Web BotGuard tokens must be paired with `mweb` / `web` clients — never
  /// substituted onto an `android` GVS URL after the fact.
  String extractorValueFor(String playerClient) {
    final String client = playerClient.trim().toLowerCase();
    final String scope = switch (client) {
      'android' || 'android_sdkless' => 'android',
      'web' || 'web_safari' || 'web_embedded' => 'web',
      _ => 'mweb',
    };
    return '$scope.player+$player,$scope.gvs+$gvs';
  }
}
