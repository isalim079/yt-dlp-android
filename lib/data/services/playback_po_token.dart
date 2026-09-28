/// Dart bridge to the on-device BotGuard WebView minter.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';
import '../models/playback_po_token.dart';

/// Mints YouTube web PO tokens via Chromium BotGuard (not DroidGuard).
abstract final class PlaybackPoTokenService {
  static const MethodChannel _channel = MethodChannel(
    'com.ytdownloader.app/ytdlp',
  );

  /// Test hook: skip the native minter.
  @visibleForTesting
  static Future<void> Function()? debugEnsure;

  /// Test hook: return minted tokens without WebView.
  @visibleForTesting
  static Future<PlaybackPoToken?> Function(String videoId)? debugMint;

  /// Loads the BotGuard VM and integrity token (hours of TTL).
  static Future<void> ensureMinter({bool rethrowOnError = true}) async {
    final Future<void> Function()? hook = debugEnsure;
    if (hook != null) {
      await hook();
      return;
    }
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('ensurePoMinter');
    } on Object catch (error, stack) {
      AppLogger.w('BotGuard ensureMinter failed: $error\n$stack');
      if (rethrowOnError) {
        rethrow;
      }
    }
  }

  /// Mints player (video ID) and GVS (visitor) tokens. Null if minting fails.
  static Future<PlaybackPoToken?> mint(String videoId) async {
    final Future<PlaybackPoToken?> Function(String videoId)? hook = debugMint;
    if (hook != null) {
      return hook(videoId);
    }
    if (!Platform.isAndroid || videoId.isEmpty) {
      return null;
    }
    try {
      await ensureMinter();
      final Object? raw = await _channel.invokeMethod<Object>(
        'mintPoTokens',
        <String, dynamic>{'videoId': videoId},
      );
      if (raw is! Map) {
        AppLogger.w('BotGuard mint returned no map');
        return null;
      }
      final String player = raw['player']?.toString() ?? '';
      final String gvs = raw['gvs']?.toString() ?? '';
      final String visitorData = raw['visitorData']?.toString() ?? '';
      if (player.isEmpty || gvs.isEmpty) {
        AppLogger.w('BotGuard mint missing player or gvs token');
        return null;
      }
      AppLogger.i('BotGuard minted player+GVS PO tokens for $videoId');
      return PlaybackPoToken(
        player: player,
        gvs: gvs,
        visitorData: visitorData,
      );
    } on Object catch (error, stack) {
      AppLogger.w('BotGuard mint failed: $error\n$stack');
      return null;
    }
  }
}
