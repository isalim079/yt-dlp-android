/// Handles URLs shared from other apps into this app (Android SEND intent).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../data/providers/app_navigation_providers.dart';
import '../../data/providers/home_feedback_providers.dart';
import '../../data/providers/ytdlp_providers.dart';
import '../utils/logger.dart';

/// Handles URLs shared from other apps (e.g. YouTube → Share → YT Downloader).
abstract final class ShareIntentHandler {
  static StreamSubscription<List<SharedMediaFile>>? _mediaSub;

  /// Subscribes to share intents and seeds [urlInputProvider] when applicable.
  static void initialize(WidgetRef ref) {
    _mediaSub?.cancel();
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> media) {
      final String? text = _firstYoutubeSharedText(media);
      if (text != null) {
        ref.read(urlInputProvider.notifier).state = text;
        ref.read(shareIntentCounterProvider.notifier).state =
            ref.read(shareIntentCounterProvider) + 1;
        AppLogger.i('Share intent (initial): URL applied');
      }
      ReceiveSharingIntent.instance.reset();
    }, onError: (Object e, StackTrace st) {
      AppLogger.w('getInitialMedia failed: $e\n$st');
    });

    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> media) {
        final String? text = _firstYoutubeSharedText(media);
        if (text != null) {
          ref.read(urlInputProvider.notifier).state = text;
          ref.read(tabIndexProvider.notifier).state = 0;
          ref.read(shareIntentCounterProvider.notifier).state =
              ref.read(shareIntentCounterProvider) + 1;
          AppLogger.i('Share intent (stream): URL applied');
        }
      },
      onError: (Object e, StackTrace st) {
        AppLogger.w('getMediaStream error: $e\n$st');
      },
    );
  }

  /// Cancels the live share stream subscription.
  static void dispose() {
    _mediaSub?.cancel();
    _mediaSub = null;
  }

  static String? _firstYoutubeSharedText(List<SharedMediaFile> media) {
    for (final SharedMediaFile m in media) {
      if (m.type != SharedMediaType.text && m.type != SharedMediaType.url) {
        continue;
      }
      final String path = m.path.trim();
      if (_isYoutubeUrl(path)) {
        return path;
      }
    }
    return null;
  }

  static bool _isYoutubeUrl(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }
}
