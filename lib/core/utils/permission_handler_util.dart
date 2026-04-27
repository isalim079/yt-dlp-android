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
  /// Requests storage permission on Android &lt; 13.
  ///
  /// On Android 13+ returns `true` (public Downloads path does not require
  /// legacy storage permission for typical yt-dlp output).
  /// On Android 11–12 requests [Permission.manageExternalStorage].
  /// Below Android 11 requests [Permission.storage].
  static Future<bool> requestStoragePermission() async {
    try {
      if (!Platform.isAndroid) {
        return true;
      }
      final AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
      final int sdk = androidInfo.version.sdkInt;

      AppLogger.i('Android SDK: $sdk — requesting storage permission');

      if (sdk >= 33) {
        final PermissionStatus video = await Permission.videos.request();
        final PermissionStatus audio = await Permission.audio.request();
        AppLogger.i(
          'Android 13+ permissions: video=${video.name} audio=${audio.name}',
        );
        return video.isGranted || audio.isGranted;
      } else if (sdk >= 30) {
        final PermissionStatus status =
            await Permission.manageExternalStorage.request();
        AppLogger.i('MANAGE_EXTERNAL_STORAGE: ${status.name}');
        return status.isGranted;
      } else {
        final PermissionStatus status = await Permission.storage.request();
        AppLogger.i('WRITE_EXTERNAL_STORAGE: ${status.name}');
        return status.isGranted;
      }
    } catch (e, st) {
      AppLogger.e('Permission request failed', e, st);
      return false;
    }
  }

  /// Whether storage-related access is already granted for this Android SDK.
  static Future<bool> hasStoragePermission() async {
    try {
      if (!Platform.isAndroid) {
        return true;
      }
      final AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
      final int sdk = androidInfo.version.sdkInt;
      if (sdk >= 33) {
        return Permission.videos.isGranted;
      } else if (sdk >= 30) {
        return Permission.manageExternalStorage.isGranted;
      } else {
        return Permission.storage.isGranted;
      }
    } catch (e, st) {
      AppLogger.e('hasStoragePermission check failed', e, st);
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
  static Future<bool> ensureStoragePermission(BuildContext context) async {
    if (await hasStoragePermission()) {
      return true;
    }
    final bool granted = await requestStoragePermission();
    if (!granted) {
      if (context.mounted) {
        await showPermissionDeniedDialog(context);
      }
      return false;
    }
    return true;
  }
}
