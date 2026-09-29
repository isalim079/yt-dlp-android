/// Multi-strategy YouTube format catalog for downloads (Seal/YTDLnis-style).
library;

import 'dart:convert';

import '../../core/constants/app_strings.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/youtube_urls.dart';
import '../models/playback_po_token.dart';
import '../models/video_format.dart';
import 'playback_hd_fallback.dart';
import 'ytdlp_service.dart';

/// Strategies used for download format listing (no dead `android_vr`).
List<ExtractionStrategy> downloadListingStrategies({required bool hasPo}) {
  return <ExtractionStrategy>[
    ExtractionStrategy.defaultClients,
    ExtractionStrategy.android,
    if (hasPo) ExtractionStrategy.mwebWithPot,
    ExtractionStrategy.webSafariHls,
  ];
}

/// One strategy's parsed catalog rows (for merge / tests).
class DownloadStrategyExtract {
  /// Creates an extract result for [client].
  const DownloadStrategyExtract({
    required this.client,
    required this.formats,
  });

  /// yt-dlp `player_client` value (or `default`).
  final String client;

  /// Formats produced by this strategy.
  final List<VideoFormat> formats;
}

/// Builds a merged download format ladder across capability-based clients.
abstract final class DownloadFormatCatalog {
  /// Extracts and merges formats for [url].
  ///
  /// Prefers richer ladders (HD adaptive from mweb+PO over progressive-only).
  static Future<List<VideoFormat>> build({
    required YtdlpService ytdlp,
    required String url,
    Future<PlaybackPoToken?> Function(String videoId)? mintPoTokens,
    Duration mintTimeout = kPlaybackMintTimeout,
    String? settingsClientOverride,
  }) async {
    PlaybackPoToken? tokens;
    final String? videoId = YoutubeUrls.videoId(url);
    if (mintPoTokens != null && videoId != null) {
      try {
        tokens = await mintPoTokens(videoId).timeout(mintTimeout);
        if (tokens != null && !tokens.isComplete) {
          tokens = null;
        }
      } on Object catch (error, stack) {
        AppLogger.w('download catalog mint failed: $error\n$stack');
        tokens = null;
      }
    }

    final List<ExtractionStrategy> strategies = downloadListingStrategies(
      hasPo: tokens != null,
    );

    final List<DownloadStrategyExtract> extracts = <DownloadStrategyExtract>[];
    final String? override = settingsClientOverride?.trim();
    if (override != null &&
        override.isNotEmpty &&
        override != 'android,web' &&
        override.toLowerCase() != 'default') {
      final DownloadStrategyExtract? forced = await _extractOne(
        ytdlp: ytdlp,
        url: url,
        client: override,
        poToken: null,
        visitorData: null,
      );
      if (forced != null) {
        extracts.add(forced);
      }
    }

    for (final ExtractionStrategy strategy in strategies) {
      if (extractionRequiresPo(strategy) && tokens == null) {
        continue;
      }
      final bool usePo = extractionRequiresPo(strategy);
      final DownloadStrategyExtract? one = await _extractOne(
        ytdlp: ytdlp,
        url: url,
        client: extractionPlayerClient(strategy),
        poToken: usePo ? tokens!.extractorValue : null,
        visitorData: usePo ? tokens!.visitorData : null,
      );
      if (one != null) {
        AppLogger.i(
          'download catalog strategy=${strategy.name} '
          'client=${one.client} formats=${one.formats.length} '
          'maxH=${_maxVideoHeight(one.formats)} hasPo=$usePo',
        );
        extracts.add(one);
      }
    }

    if (extracts.isEmpty) {
      return <VideoFormat>[];
    }

    final List<VideoFormat> merged = mergeExtracts(extracts);
    final List<int> heights = merged
        .where((VideoFormat f) => !f.isAudioOnly)
        .map((VideoFormat f) => f.height)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    AppLogger.i(
      'download catalog merged=${merged.length} heights=$heights',
    );
    return merged;
  }

  /// Pure merge for unit tests — dedupe by height/kind, keep richer rows.
  static List<VideoFormat> mergeExtracts(List<DownloadStrategyExtract> extracts) {
    final Map<String, VideoFormat> byKey = <String, VideoFormat>{};

    for (final DownloadStrategyExtract extract in extracts) {
      for (final VideoFormat f in extract.formats) {
        final String key = f.isAudioOnly
            ? 'a|${f.extension}|${(f.audioBitrate ?? 0).round()}'
            : 'v|${f.height ?? 0}';
        final VideoFormat? existing = byKey[key];
        if (existing == null || _prefer(f, existing)) {
          byKey[key] = f;
        }
      }
    }

    return _sortCatalog(byKey.values.toList());
  }

  /// Builds picker rows from one yt-dlp `-J` body (pairs video-only + audio).
  static List<VideoFormat> entriesFromJson(
    String jsonString, {
    required String sourceClient,
    String? poToken,
    String? visitorData,
    DateTime? extractedAt,
  }) {
    final DateTime at = extractedAt ?? DateTime.now();
    late final Map<String, dynamic> root;
    try {
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        return <VideoFormat>[];
      }
      root = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return <VideoFormat>[];
    }

    final List<dynamic>? raw = root['formats'] as List<dynamic>?;
    if (raw == null) {
      return <VideoFormat>[];
    }

    final List<_RawFmt> progressive = <_RawFmt>[];
    final List<_RawFmt> videoOnly = <_RawFmt>[];
    final List<_RawFmt> audioOnly = <_RawFmt>[];

    for (final dynamic row in raw) {
      if (row is! Map) {
        continue;
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(row);
      final String? url = map['url']?.toString();
      if (url == null || !url.startsWith('http')) {
        continue;
      }
      final String ext = (map['ext']?.toString() ?? '').toLowerCase();
      if (ext == 'mhtml') {
        continue;
      }
      final String note = (map['format_note']?.toString() ?? '').toLowerCase();
      if (note.contains('storyboard')) {
        continue;
      }
      final String vcodec = (map['vcodec']?.toString() ?? '').toLowerCase();
      final String acodec = (map['acodec']?.toString() ?? '').toLowerCase();
      final String id = map['format_id']?.toString() ?? '';
      if (id.isEmpty) {
        continue;
      }
      final int height =
          map['height'] is num ? (map['height'] as num).toInt() : 0;
      final int? size = () {
        final dynamic s = map['filesize'] ?? map['filesize_approx'];
        return s is num ? s.toInt() : null;
      }();
      final double abr = map['abr'] is num ? (map['abr'] as num).toDouble() : 0;
      final _RawFmt fmt = _RawFmt(
        id: id,
        ext: ext,
        height: height,
        size: size,
        abr: abr,
        vcodec: vcodec,
        acodec: acodec,
      );

      final bool hasV = vcodec.isNotEmpty && vcodec != 'none';
      final bool hasA = acodec.isNotEmpty && acodec != 'none';
      if (hasV && hasA) {
        progressive.add(fmt);
      } else if (hasV && !hasA) {
        videoOnly.add(fmt);
      } else if (!hasV && hasA) {
        audioOnly.add(fmt);
      }
    }

    final List<VideoFormat> out = <VideoFormat>[];

    for (final _RawFmt p in progressive) {
      if (p.height <= 0) {
        continue;
      }
      out.add(
        VideoFormat(
          formatId: p.id,
          extension: p.ext.isEmpty ? 'mp4' : p.ext,
          displayLabel: _videoLabel(p.height, p.ext, p.size),
          resolution: '${p.height}${AppStrings.formatVideoSuffix}',
          fileSize: p.size,
          sourceClient: sourceClient,
          poToken: poToken,
          visitorData: visitorData,
          extractedAt: at,
        ),
      );
    }

    _RawFmt? bestAudio;
    for (final _RawFmt a in audioOnly) {
      if (bestAudio == null || _preferAudio(a, bestAudio)) {
        bestAudio = a;
      }
    }

    if (bestAudio != null) {
      final Map<int, _RawFmt> bestByHeight = <int, _RawFmt>{};
      for (final _RawFmt v in videoOnly) {
        if (v.height <= 0) {
          continue;
        }
        final _RawFmt? prev = bestByHeight[v.height];
        if (prev == null || _preferVideo(v, prev)) {
          bestByHeight[v.height] = v;
        }
      }
      for (final MapEntry<int, _RawFmt> e in bestByHeight.entries) {
        final _RawFmt v = e.value;
        out.add(
          VideoFormat(
            formatId: '${v.id}+${bestAudio.id}',
            extension: 'mp4',
            displayLabel: _videoLabel(v.height, 'mp4', v.size),
            resolution: '${v.height}${AppStrings.formatVideoSuffix}',
            fileSize: v.size,
            sourceClient: sourceClient,
            poToken: poToken,
            visitorData: visitorData,
            extractedAt: at,
            needsAudioMerge: true,
          ),
        );
      }

      out.add(
        VideoFormat(
          formatId: bestAudio.id,
          extension: bestAudio.ext.isEmpty ? 'm4a' : bestAudio.ext,
          displayLabel:
              '${AppStrings.formatAudioOnlyLabel} ${bestAudio.ext.toUpperCase()}'
              '${AppStrings.formatLabelSeparator}'
              '${bestAudio.abr > 0 ? '${bestAudio.abr.round()}kbps' : AppStrings.formatSizeUnknown}',
          fileSize: bestAudio.size,
          isAudioOnly: true,
          audioBitrate: bestAudio.abr > 0 ? bestAudio.abr : null,
          sourceClient: sourceClient,
          poToken: poToken,
          visitorData: visitorData,
          extractedAt: at,
        ),
      );
    }

    return _sortCatalog(out);
  }

  /// Closest catalog entry for a convenience height chip (or audio / best).
  static VideoFormat? closest({
    required List<VideoFormat> catalog,
    int? targetHeight,
    bool audioOnly = false,
  }) {
    if (catalog.isEmpty) {
      return null;
    }
    if (audioOnly) {
      for (final VideoFormat f in catalog) {
        if (f.isAudioOnly) {
          return f;
        }
      }
      return null;
    }
    final List<VideoFormat> video = catalog
        .where((VideoFormat f) => !f.isAudioOnly)
        .toList();
    if (video.isEmpty) {
      return null;
    }
    if (targetHeight == null) {
      return video.first;
    }
    VideoFormat best = video.first;
    int bestDelta = 1 << 30;
    for (final VideoFormat f in video) {
      final int h = f.height ?? 0;
      final int delta = (h - targetHeight).abs();
      if (delta < bestDelta ||
          (delta == bestDelta && (f.height ?? 0) > (best.height ?? 0))) {
        bestDelta = delta;
        best = f;
      }
    }
    return best;
  }

  static Future<DownloadStrategyExtract?> _extractOne({
    required YtdlpService ytdlp,
    required String url,
    required String client,
    String? poToken,
    String? visitorData,
  }) async {
    try {
      final String json = await ytdlp.fetchFormatsJson(
        url,
        playerClient: client,
        poToken: poToken,
        visitorData: visitorData,
      );
      final List<VideoFormat> formats = entriesFromJson(
        json,
        sourceClient: client,
        poToken: poToken,
        visitorData: visitorData,
      );
      if (formats.isEmpty) {
        return null;
      }
      return DownloadStrategyExtract(client: client, formats: formats);
    } on Object catch (error, stack) {
      AppLogger.w('download catalog extract $client failed: $error\n$stack');
      return null;
    }
  }

  static List<VideoFormat> _sortCatalog(List<VideoFormat> list) {
    final List<VideoFormat> copy = List<VideoFormat>.from(list);
    copy.sort((VideoFormat a, VideoFormat b) {
      if (a.isAudioOnly != b.isAudioOnly) {
        return a.isAudioOnly ? 1 : -1;
      }
      final int ah = a.height ?? 0;
      final int bh = b.height ?? 0;
      if (ah != bh) {
        return bh.compareTo(ah);
      }
      return (b.fileSize ?? 0).compareTo(a.fileSize ?? 0);
    });
    return copy;
  }

  static String _videoLabel(int height, String ext, int? size) {
    final String extLabel = ext.isEmpty ? 'MP4' : ext.toUpperCase();
    final String sizePart = size != null
        ? '${AppStrings.formatApproximatePrefix}${_shortBytes(size)}'
        : AppStrings.formatSizeUnknown;
    return '$height${AppStrings.formatVideoSuffix} $extLabel'
        '${AppStrings.formatLabelSeparator}$sizePart';
  }

  static String _shortBytes(int bytes) {
    const int k = 1024;
    if (bytes < k) {
      return '$bytes${AppStrings.fileSizeUnitBytes}';
    }
    final double kb = bytes / k;
    if (kb < k) {
      return '${kb.toStringAsFixed(0)}${AppStrings.fileSizeUnitKb}';
    }
    final double mb = kb / k;
    if (mb < k) {
      return '${mb.toStringAsFixed(1)}${AppStrings.fileSizeUnitMb}';
    }
    return '${(mb / k).toStringAsFixed(1)}${AppStrings.fileSizeUnitGb}';
  }

  static bool _prefer(VideoFormat a, VideoFormat b) {
    final int as = a.fileSize ?? 0;
    final int bs = b.fileSize ?? 0;
    if (as != bs) {
      return as > bs;
    }
    if (a.extension == 'mp4' && b.extension != 'mp4') {
      return true;
    }
    if (!a.needsAudioMerge && b.needsAudioMerge) {
      return true;
    }
    return false;
  }

  static bool _preferVideo(_RawFmt a, _RawFmt b) {
    final int as = a.size ?? 0;
    final int bs = b.size ?? 0;
    if (as != bs) {
      return as > bs;
    }
    if (a.ext == 'mp4' && b.ext != 'mp4') {
      return true;
    }
    if (a.vcodec.contains('avc') && !b.vcodec.contains('avc')) {
      return true;
    }
    return false;
  }

  static bool _preferAudio(_RawFmt a, _RawFmt b) {
    if (a.ext == 'm4a' && b.ext != 'm4a') {
      return true;
    }
    return a.abr > b.abr;
  }

  static int _maxVideoHeight(List<VideoFormat> formats) {
    int max = 0;
    for (final VideoFormat f in formats) {
      if (f.isAudioOnly) {
        continue;
      }
      final int h = f.height ?? 0;
      if (h > max) {
        max = h;
      }
    }
    return max;
  }
}

class _RawFmt {
  const _RawFmt({
    required this.id,
    required this.ext,
    required this.height,
    required this.size,
    required this.abr,
    required this.vcodec,
    required this.acodec,
  });

  final String id;
  final String ext;
  final int height;
  final int? size;
  final double abr;
  final String vcodec;
  final String acodec;
}
