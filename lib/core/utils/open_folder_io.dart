/// Opens a directory in the host file manager (IO platforms).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'logger.dart';
import 'platform_utils.dart';

/// Opens [path] in the system file manager when possible.
Future<void> openSystemFolder(
  String path, {
  BuildContext? snackbarContext,
}) async {
  if (path.isEmpty) {
    return;
  }
  if (PlatformUtils.isAndroid) {
    if (snackbarContext != null && snackbarContext.mounted) {
      ScaffoldMessenger.of(
        snackbarContext,
      ).showSnackBar(SnackBar(content: Text(path)));
    }
    return;
  }
  if (PlatformUtils.isDesktop) {
    final Uri uri = Uri.directory(path);
    try {
      if (await canLaunchUrl(uri)) {
        final bool ok = await launchUrl(uri);
        if (ok) {
          return;
        }
      }
    } on Object catch (e, st) {
      AppLogger.w('launchUrl folder failed: $e\n$st');
    }
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', <String>[path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>[path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', <String>[path]);
      }
    } on Object catch (e, st) {
      AppLogger.w('openFolder fallback failed: $e\n$st');
    }
  }
}
