/// IO implementation: extracts bundled yt-dlp from assets to app support dir.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/logger.dart';
import '../../core/utils/platform_utils.dart';
import '../../core/utils/ytdlp_launch_command.dart';
import 'ytdlp_platform_channel.dart';

/// Copies the platform-matching yt-dlp asset into app support storage.
class BinaryManager {
  /// Creates a manager instance.
  const BinaryManager();

  static const String _prefsPathKey = 'ytdlp_binary_path';
  static const String _prefsBundleVersionKey = 'ytdlp_bundle_version';
  static String? _cachedVersion;

  /// Call this once at app startup before any yt-dlp commands.
  ///
  /// Returns the absolute path to an executable yt-dlp binary, extracting
  /// from Flutter assets on first run or after an app upgrade.
  Future<String> initialize() async {
    if (Platform.isAndroid) {
      await YtdlpPlatformChannel.initialize();
      final String version = await YtdlpPlatformChannel.getVersion();
      AppLogger.i('youtubedl-android initialized, yt-dlp: $version');
      return 'android-platform-channel';
    }

    await PlatformUtils.primeAndroidBinaryForCurrentDevice();

    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String bundleVersion =
        '${packageInfo.version}+${packageInfo.buildNumber}';
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? cachedPath = prefs.getString(_prefsPathKey);
    final String? cachedBundleVersion = prefs.getString(_prefsBundleVersionKey);
    final String targetPath = await _getTargetPath();

    if (cachedPath != null &&
        cachedPath == targetPath &&
        cachedBundleVersion == bundleVersion) {
      final bool isValid = await _isBinaryValid(cachedPath);
      if (isValid) {
        try {
          await _verifyBinaryWorks(cachedPath);
          AppLogger.i('yt-dlp ready at $cachedPath');
          return cachedPath;
        } catch (_) {
          AppLogger.w('Cached binary not executable, re-applying chmod');
          await _setExecutablePermission(cachedPath);
          try {
            await _verifyBinaryWorks(cachedPath);
            AppLogger.i('yt-dlp ready at $cachedPath');
            return cachedPath;
          } catch (_) {
            AppLogger.w('chmod failed, forcing full re-extraction');
            await prefs.remove(_prefsPathKey);
            await prefs.remove(_prefsBundleVersionKey);
          }
        }
      }
    }

    final String assetPath = PlatformUtils.binaryAssetPath;
    await _extractBinary(assetPath, targetPath);
    await _verifyBinaryWorks(targetPath);

    await prefs.setString(_prefsPathKey, targetPath);
    await prefs.setString(_prefsBundleVersionKey, bundleVersion);
    AppLogger.i('yt-dlp ready at $targetPath');
    return targetPath;
  }

  /// Copies binary bytes from the asset bundle to [targetPath].
  Future<void> _extractBinary(String assetPath, String targetPath) async {
    try {
      AppLogger.i('Extracting yt-dlp asset to $targetPath');

      // Load asset bytes
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      // Ensure parent directory exists
      final File targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      // Write bytes and explicitly flush
      final RandomAccessFile raf = await targetFile.open(
        mode: FileMode.writeOnly,
      );
      await raf.writeFrom(bytes);
      await raf.flush();
      await raf.close();

      // Verify file was written correctly
      final int writtenSize = await targetFile.length();
      if (writtenSize == 0) {
        throw Exception('Binary file was written but is empty');
      }

      AppLogger.i('Binary written: $writtenSize bytes');

      // NOW set executable permission after file is fully closed
      await _setExecutablePermission(targetPath);
    } catch (e, st) {
      AppLogger.e('_extractBinary failed', e, st);
      rethrow;
    }
  }

  Future<void> _setExecutablePermission(String binaryPath) async {
    if (Platform.isWindows) {
      return;
    }
    try {
      // Ensure file is fully flushed before chmod
      final File file = File(binaryPath);
      if (!await file.exists()) {
        throw Exception('Binary file not found at $binaryPath');
      }

      // 555: read+execute only (no owner write) — required for W^X on Android.
      // Method 1: dart:io chmod via Process.run
      final ProcessResult result = await Process.run('chmod', <String>[
        '555',
        binaryPath,
      ], runInShell: false);

      if (result.exitCode != 0) {
        AppLogger.w('chmod via Process.run failed: ${result.stderr}');
        // Method 2: fallback using shell
        final ProcessResult shellResult = await Process.run(
          '/system/bin/chmod',
          <String>['555', binaryPath],
          runInShell: false,
        );
        if (shellResult.exitCode != 0) {
          AppLogger.w(
            'chmod via /system/bin/chmod also failed: ${shellResult.stderr}',
          );
          // Method 3: fallback using sh -c
          await Process.run('/system/bin/sh', <String>[
            '-c',
            'chmod 555 $binaryPath',
          ]);
        }
      }

      AppLogger.i('chmod 555 applied to $binaryPath');
    } catch (e, st) {
      AppLogger.e('_setExecutablePermission failed', e, st);
      rethrow;
    }
  }

  Future<void> _verifyBinaryWorks(String binaryPath) async {
    final YtdlpLaunchCommand cmd = YtdlpLaunchCommand.from(binaryPath, <String>[
      '--version',
    ]);
    try {
      final ProcessResult result = await Process.run(
        cmd.executable,
        cmd.arguments,
        runInShell: false,
      ).timeout(const Duration(seconds: 10));

      if (result.exitCode == 0) {
        AppLogger.i('Binary verified: ${result.stdout.toString().trim()}');
      } else {
        throw Exception(
          'Binary test run failed with exit code ${result.exitCode}: '
          '${result.stderr}',
        );
      }
    } on ProcessException catch (e, st) {
      AppLogger.e('Binary not executable', e, st);
      // Try chmod one more time and retry
      await _setExecutablePermission(binaryPath);
      final ProcessResult retry = await Process.run(
        cmd.executable,
        cmd.arguments,
        runInShell: false,
      ).timeout(const Duration(seconds: 10));
      if (retry.exitCode != 0) {
        throw Exception('Binary still not executable after retry chmod');
      }
      AppLogger.i('Binary verified after retry chmod');
    }
  }

  /// Returns whether [path] points to a non-empty file on disk.
  Future<bool> _isBinaryValid(String path) async {
    try {
      final File f = File(path);
      if (!await f.exists()) {
        return false;
      }
      return await f.length() > 0;
    } on Object catch (e, st) {
      AppLogger.w('Binary validity check failed: $e\n$st');
      return false;
    }
  }

  /// Resolves the destination path for the extracted yt-dlp binary.
  Future<String> _getTargetPath() async {
    final Directory support = await getApplicationSupportDirectory();
    final String name = PlatformUtils.binaryFileName;
    return p.join(support.path, 'bin', name);
  }

  /// Clears cached path/version so the next [initialize] re-extracts.
  Future<void> reset() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsPathKey);
    await prefs.remove(_prefsBundleVersionKey);
    AppLogger.i('Cleared yt-dlp binary cache keys');
  }

  /// Runs `yt-dlp --version` and returns the version string.
  ///
  /// Returns `'Unknown'` on failure and caches successful reads.
  Future<String> getYtdlpVersion() async {
    if (Platform.isAndroid) {
      return YtdlpPlatformChannel.getVersion();
    }
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }
    try {
      final String binaryPath = await initialize();
      final YtdlpLaunchCommand cmd = YtdlpLaunchCommand.from(
        binaryPath,
        <String>['--version'],
      );
      final ProcessResult result = await Process.run(
        cmd.executable,
        cmd.arguments,
        runInShell: false,
      );
      if (result.exitCode != 0) {
        return 'Unknown';
      }
      final String value = result.stdout?.toString().trim() ?? '';
      if (value.isEmpty) {
        return 'Unknown';
      }
      _cachedVersion = value;
      return value;
    } on Object catch (error, stackTrace) {
      AppLogger.w('Unable to read yt-dlp version: $error\n$stackTrace');
      return 'Unknown';
    }
  }
}
