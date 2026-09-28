/// Runtime permission helpers for Android storage (and rationale UI).
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/app_strings.dart';
import 'logger.dart';

/// Handles runtime permission requests for storage and notifications.
abstract final class PermissionHandlerUtil {
  /// Whether [path] is shared/public storage (e.g. `/storage/emulated/0/Download`).
  static bool isPublicStoragePath(String path) {
    final String normalized = path.replaceAll('\\', '/').toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.contains('/android/data/') ||
        normalized.contains('/android/obb/') ||
        normalized.startsWith('/data/data/') ||
        normalized.startsWith('/data/user/')) {
      return false;
    }
    return true;
  }

  /// Requests write access needed to create a new download file.
  ///
  /// Android 13+ does not need READ_MEDIA_* to save a new file.
  /// Android 11–12 requests [Permission.manageExternalStorage] only for public paths.
  /// Below Android 11 requests [Permission.storage].
  static Future<bool> requestStoragePermission({String? outputPath}) async {
    try {
      if (!Platform.isAndroid) {
        return true;
      }
      final AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
      final int sdk = androidInfo.version.sdkInt;

      AppLogger.i('Android SDK: $sdk — checking download write permission');

      if (sdk >= 33) {
        return true;
      }
      if (sdk >= 30) {
        if (outputPath != null && !isPublicStoragePath(outputPath)) {
          return true;
        }
        final PermissionStatus status =
            await Permission.manageExternalStorage.request();
        AppLogger.i('MANAGE_EXTERNAL_STORAGE: ${status.name}');
        return status.isGranted;
      }
      final PermissionStatus status = await Permission.storage.request();
      AppLogger.i('WRITE_EXTERNAL_STORAGE: ${status.name}');
      return status.isGranted;
    } catch (e, st) {
      AppLogger.e('Permission request failed', e, st);
      return false;
    }
  }

  /// Whether storage-related write access is already granted for this Android SDK.
  static Future<bool> hasStoragePermission({String? outputPath}) async {
    try {
      if (!Platform.isAndroid) {
        return true;
      }
      final AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
      final int sdk = androidInfo.version.sdkInt;
      if (sdk >= 33) {
        return true;
      }
      if (sdk >= 30) {
        if (outputPath != null && !isPublicStoragePath(outputPath)) {
          return true;
        }
        return await Permission.manageExternalStorage.isGranted;
      }
      return await Permission.storage.isGranted;
    } catch (e, st) {
      AppLogger.e('hasStoragePermission check failed', e, st);
      return false;
    }
  }

  /// Requests media-library read access so a public Downloads folder can be listed.
  static Future<bool> requestMediaReadPermission() async {
    try {
      if (!Platform.isAndroid) {
        return true;
      }
      final AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
      final int sdk = androidInfo.version.sdkInt;
      if (sdk >= 33) {
        final PermissionStatus video = await Permission.videos.request();
        final PermissionStatus audio = await Permission.audio.request();
        AppLogger.i(
          'Media read permissions: video=${video.name} audio=${audio.name}',
        );
        return video.isGranted || audio.isGranted;
      }
      return await requestStoragePermission();
    } catch (e, st) {
      AppLogger.e('Media read permission request failed', e, st);
      return false;
    }
  }

  /// Explains why storage is needed and optionally opens system settings.
  static Future<void> showPermissionDeniedDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(AppStrings.permissionDeniedTitle),
          content: const Text(AppStrings.permissionDeniedBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(AppStrings.permissionNotNow),
            ),
            ElevatedButton(
              onPressed: () async {
                await openAppSettings();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text(AppStrings.openAppSettings),
            ),
          ],
        );
      },
    );
  }

  /// Ensures storage permission before writing downloads on Android.
  ///
  /// Returns `true` when it is safe to proceed, `false` when the flow should
  /// abort after handling denial UI.
  static Future<bool> ensureStoragePermission(
    BuildContext context, {
    String? outputPath,
  }) async {
    if (await hasStoragePermission(outputPath: outputPath)) {
      return true;
    }
    final bool granted = await requestStoragePermission(outputPath: outputPath);
    if (!granted) {
      if (context.mounted) {
        await showPermissionDeniedDialog(context);
      }
      return false;
    }
    return true;
  }
}
