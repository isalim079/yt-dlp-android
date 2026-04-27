/// Application entrypoint: pre-warms yt-dlp then mounts the Riverpod tree.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_bootstrap.dart';
import 'core/utils/desktop_window_stub.dart'
if (dart.library.io) 'core/utils/desktop_window_io.dart' as desktop_window;
import 'core/utils/logger.dart';
import 'core/widgets/error_boundary.dart';

Future<void> main() async {
  final WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.e('Flutter error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.e('Dart error', error, stack);
    return true;
  };

  await desktop_window.configureDesktopWindow();

  runApp(
    const ErrorBoundary(
      child: ProviderScope(
        child: YtDownloaderBootstrap(),
      ),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    FlutterNativeSplash.remove();
  });
}
