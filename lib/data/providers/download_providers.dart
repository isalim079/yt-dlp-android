/// Riverpod access to [DownloadManager] and derived queue views.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_item.dart';
import '../services/download_manager.dart';

/// Singleton download coordinator for the app lifetime.
final NotifierProvider<DownloadManager, List<DownloadItem>>
downloadManagerProvider = NotifierProvider<DownloadManager, List<DownloadItem>>(
  DownloadManager.new,
);

/// Full FIFO queue including all statuses.
final Provider<List<DownloadItem>> downloadQueueProvider =
    Provider<List<DownloadItem>>((Ref ref) {
      return ref.watch(downloadManagerProvider);
    });

/// Individual item provider to prevent full list rebuilds
final itemProvider = Provider.family
    .autoDispose<DownloadItem?, String>((Ref ref, String id) {
  return ref.watch(downloadManagerProvider)
      .cast<DownloadItem?>()
      .firstWhere((DownloadItem? i) => i?.id == id, orElse: () => null);
});

/// Jobs currently downloading bytes.
final Provider<List<DownloadItem>> activeDownloadsProvider =
    Provider<List<DownloadItem>>((Ref ref) {
      return ref.watch(downloadManagerProvider.notifier).activeDownloads;
    });

/// Successfully finished jobs.
final Provider<List<DownloadItem>> completedDownloadsProvider =
    Provider<List<DownloadItem>>((Ref ref) {
      return ref.watch(downloadManagerProvider.notifier).completedDownloads;
    });

/// Failed or cancelled jobs.
final Provider<List<DownloadItem>> failedDownloadsProvider =
    Provider<List<DownloadItem>>((Ref ref) {
      return ref.watch(downloadManagerProvider.notifier).failedDownloads;
    });

/// Count of in-flight transfers for navigation badges.
final Provider<int> activeDownloadCountProvider = Provider<int>((Ref ref) {
  return ref.watch(downloadManagerProvider.notifier).activeDownloads.length;
});
