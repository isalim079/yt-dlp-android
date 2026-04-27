/// Desktop window sizing (IO platforms only).
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_strings.dart';

/// Initializes window manager and shows a fixed-size desktop window.
Future<void> configureDesktopWindow() async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return;
  }
  await windowManager.ensureInitialized();
  const WindowOptions windowOptions = WindowOptions(
    size: Size(420, 780),
    minimumSize: Size(380, 600),
    maximumSize: Size(600, 1000),
    center: true,
    title: AppStrings.appName,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
