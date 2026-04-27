/// Cross-platform helpers for capabilities and environment checks.
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'logger.dart';

/// Runtime platform checks and bundled yt-dlp asset resolution.
class PlatformUtils {
  /// Creates utility helpers (reserved for future instance state).
  const PlatformUtils();

  static String _androidBinaryFileName = 'yt-dlp_android_arm64';

  /// Loads the primary Android ABI and updates [binaryFileName] for Android.
  ///
  /// Safe to call on any platform; no-ops when not on Android. Should be
  /// invoked before reading [binaryAssetPath] / [binaryFileName] on Android
  /// (e.g. at the start of [BinaryManager.initialize]).
  static Future<void> primeAndroidBinaryForCurrentDevice() async {
    if (!isAndroid) {
      return;
    }
    final String? abi = await getAndroidAbi();
    _androidBinaryFileName = getBinaryFileNameForAbi(abi ?? 'arm64-v8a');
  }

  /// Asset key (Flutter bundle) for the yt-dlp binary on this platform.
  static String get binaryAssetPath => 'assets/bin/$binaryFileName';

  /// File name of the bundled yt-dlp binary for the active platform / ABI.
  ///
  /// On Android, reflects the result of the last [primeAndroidBinaryForCurrentDevice]
  /// call (defaults to `yt-dlp_android_arm64` until primed).
  static String get binaryFileName {
    if (kIsWeb) {
      throw UnsupportedError('yt-dlp assets are not used on web');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidBinaryFileName;
      case TargetPlatform.windows:
        return 'yt-dlp.exe';
      case TargetPlatform.linux:
        return 'yt-dlp';
      case TargetPlatform.macOS:
        return 'yt-dlp_macos';
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Bundled yt-dlp is only configured for Android and desktop targets',
        );
    }
  }

  /// Whether the embedder is running on Android.
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the embedder is a desktop OS (Windows, macOS, or Linux).
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Whether the app is running on the web.
  static bool get isWeb => kIsWeb;

  /// Returns the first supported ABI reported by the system, if any.
  ///
  /// On non-Android platforms this always returns `null`.
  static Future<String?> getAndroidAbi() async {
    if (!isAndroid) {
      return null;
    }
    try {
      final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
      if (info.supportedAbis.isNotEmpty) {
        return info.supportedAbis.first;
      }
      return null;
    } on Object catch (e, st) {
      AppLogger.w('PlatformUtils.getAndroidAbi failed: $e\n$st');
      return null;
    }
  }

  /// Maps an Android ABI string to the bundled asset file name.
  ///
  /// Supports `arm64-v8a`, `x86`, and `x86_64`. Unknown values default to
  /// the ARM64 asset, which matches most production devices.
  static String getBinaryFileNameForAbi(String abi) {
    switch (abi) {
      case 'arm64-v8a':
        return 'yt-dlp_android_arm64';
      case 'x86':
        return 'yt-dlp_android_x86';
      case 'x86_64':
        return 'yt-dlp_android_x86';
      default:
        return 'yt-dlp_android_arm64';
    }
  }
}
