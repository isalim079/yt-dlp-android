/// Desktop window sizing (IO platforms only).
library;

import 'dart:io';

/// Initializes window manager and shows a fixed-size desktop window.
Future<void> configureDesktopWindow() async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return;
  }
  // window_manager removed for size optimization
}
