/// Startup gate: waits for yt-dlp extraction before showing the main shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/constants/app_strings.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'data/providers/binary_path_provider.dart';

/// Root widget that resolves [binaryPathProvider] then mounts [YtDownloaderApp].
class YtDownloaderBootstrap extends ConsumerWidget {
  /// Creates the bootstrap shell.
  const YtDownloaderBootstrap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<String> state = ref.watch(binaryPathProvider);
    return state.when(
      data: (_) => const YtDownloaderApp(),
      loading: () => const _BootstrapMaterial(
        body: Center(child: Text(AppStrings.binaryInitializing)),
      ),
      error: (Object error, StackTrace stack) {
        AppLogger.e('yt-dlp binary initialization failed', error, stack);
        return _BootstrapMaterial(
          body: _BinaryInitError(
            onRetry: () => ref.invalidate(binaryPathProvider),
          ),
        );
      },
    );
  }
}

class _BootstrapMaterial extends StatelessWidget {
  const _BootstrapMaterial({required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(body: body),
    );
  }
}

class _BinaryInitError extends StatelessWidget {
  const _BinaryInitError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(AppStrings.binaryInitError, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              child: const Text(AppStrings.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}
