/// Riverpod wiring for the production Playback API.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../providers/settings_providers.dart';
import '../providers/ytdlp_providers.dart';
import '../services/api/download_api_repository.dart';
import '../services/api/installation_auth.dart';
import '../services/api/playback_api_repository.dart';
import '../services/api/yxz_api_client.dart';
import '../services/playback_source_router.dart';

/// Installation JWT auth (base URL from settings).
final Provider<InstallationAuthService> installationAuthProvider =
    Provider<InstallationAuthService>((Ref ref) {
  final AppSettings settings =
      ref.watch(settingsProvider).valueOrNull ?? AppSettings.defaults;
  return InstallationAuthService(baseUrl: settings.apiBaseUrl);
});

/// Authenticated HTTP client.
final Provider<YxzApiClient> yxzApiClientProvider =
    Provider<YxzApiClient>((Ref ref) {
  return YxzApiClient(auth: ref.watch(installationAuthProvider));
});

/// Remote playback repository.
final Provider<PlaybackApiRepository> playbackApiRepositoryProvider =
    Provider<PlaybackApiRepository>((Ref ref) {
  return PlaybackApiRepository(ref.watch(yxzApiClientProvider));
});

/// Remote download repository.
final Provider<DownloadApiRepository> downloadApiRepositoryProvider =
    Provider<DownloadApiRepository>((Ref ref) {
  return DownloadApiRepository(ref.watch(yxzApiClientProvider));
});

/// Server-primary / local-fallback router.
final Provider<PlaybackSourceRouter> playbackSourceRouterProvider =
    Provider<PlaybackSourceRouter>((Ref ref) {
  final AppSettings settings =
      ref.watch(settingsProvider).valueOrNull ?? AppSettings.defaults;
  return PlaybackSourceRouter(
    ytdlp: ref.watch(ytdlpServiceProvider),
    preferServer: settings.preferServerPlayback,
    apiBaseUrl: settings.apiBaseUrl,
    apiRepository: settings.apiBaseUrl.trim().isEmpty
        ? null
        : ref.watch(playbackApiRepositoryProvider),
  );
});
