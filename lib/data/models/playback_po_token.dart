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

  /// yt-dlp `po_token` extractor arg value for `mweb`.
  String get extractorValue => 'mweb.player+$player,mweb.gvs+$gvs';
}
