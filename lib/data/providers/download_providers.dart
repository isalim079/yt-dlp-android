/// Riverpod access to [DownloadManager] and derived queue views.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_item.dart';
import '../services/download_manager.dart';

/// Interactive filter tabs on the Downloads screen.
enum DownloadFilterTab {
  /// Show all downloads in the queue.
  all,

  /// Show active/downloading and queued items.
  active,

  /// Show items paused by user.
  paused,

  /// Show finished items.
  done,

  /// Show failed or cancelled items.
  failed,

  /// Show files downloaded by this app.
  downloaded,
}

/// Selected filter tab on the Downloads screen.
final StateProvider<DownloadFilterTab> downloadFilterTabProvider =
    StateProvider<DownloadFilterTab>((Ref ref) => DownloadFilterTab.all);

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

/// Individual item provider to prevent full list rebuilds.
final AutoDisposeProviderFamily<DownloadItem?, String> itemProvider =
    Provider.family.autoDispose<DownloadItem?, String>((Ref ref, String id) {
      return ref
          .watch(downloadManagerProvider)
          .cast<DownloadItem?>()
          .firstWhere((DownloadItem? i) => i?.id == id, orElse: () => null);
    });

/// Jobs currently downloading bytes or queued.
final Provider<List<DownloadItem>> activeDownloadsProvider =
    Provider<List<DownloadItem>>((Ref ref) {
      final List<DownloadItem> queue = ref.watch(downloadQueueProvider);
      return queue
          .where(
            (DownloadItem i) =>
                i.status == DownloadStatus.downloading ||
                i.status == DownloadStatus.queued,
          )
          .toList(growable: false);
    });

/// Jobs paused by user.
final Provider<List<DownloadItem>> pausedDownloadsProvider =
    Provider<List<DownloadItem>>((Ref ref) {
      final List<DownloadItem> queue = ref.watch(downloadQueueProvider);
      return queue
          .where((DownloadItem i) => i.status == DownloadStatus.paused)
          .toList(growable: false);
    });

/// Successfully finished jobs.
final Provider<List<DownloadItem>> completedDownloadsProvider =
    Provider<List<DownloadItem>>((Ref ref) {
      final List<DownloadItem> queue = ref.watch(downloadQueueProvider);
      return queue
          .where((DownloadItem i) => i.status == DownloadStatus.completed)
          .toList(growable: false);
    });

/// Failed or cancelled jobs.
final Provider<List<DownloadItem>> failedDownloadsProvider =
    Provider<List<DownloadItem>>((Ref ref) {
      final List<DownloadItem> queue = ref.watch(downloadQueueProvider);
      return queue
          .where((DownloadItem i) => i.status == DownloadStatus.failed)
          .toList(growable: false);
    });

/// Count of in-flight transfers for navigation badges.
final Provider<int> activeDownloadCountProvider = Provider<int>((Ref ref) {
  return ref.watch(activeDownloadsProvider).length;
});
