/// No-op desktop window setup for platforms without `dart:io`.
library;

/// No-op on web and other non-desktop targets.
Future<void> configureDesktopWindow() async {}
