/// Platform bridge for NewPipe / InnerTube paginated feeds (Android).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/feed_page.dart';

/// Flutter side of Home / Shorts feed MethodChannel.
class FeedPlatformChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.ytdownloader.app/feed',
  );

  /// Whether native NewPipe feeds are available.
  static bool get isSupported => Platform.isAndroid;

  /// First or continued Home (trending kiosk) page.
  static Future<FeedPage> fetchHomeFeed({String? continuation}) async {
    if (!isSupported) {
      return FeedPage.empty;
    }
    final Object? raw = await _channel.invokeMethod<Object>(
      'fetchHomeFeed',
      <String, dynamic>{
        if (continuation != null && continuation.isNotEmpty)
          'continuation': continuation,
      },
    );
    return _parse(raw);
  }

  /// First or continued Shorts page.
  static Future<FeedPage> fetchShortsFeed({String? continuation}) async {
    if (!isSupported) {
      return FeedPage.empty;
    }
    final Object? raw = await _channel.invokeMethod<Object>(
      'fetchShortsFeed',
      <String, dynamic>{
        if (continuation != null && continuation.isNotEmpty)
          'continuation': continuation,
      },
    );
    return _parse(raw);
  }

  static FeedPage _parse(Object? raw) {
    if (raw == null) {
      return FeedPage.empty;
    }
    if (raw is String) {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return FeedPage.fromJson(Map<String, dynamic>.from(decoded));
      }
      return FeedPage.empty;
    }
    if (raw is Map) {
      return FeedPage.fromJson(Map<String, dynamic>.from(raw));
    }
    return FeedPage.empty;
  }
}
