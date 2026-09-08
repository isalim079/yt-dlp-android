library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/logger.dart';
import '../models/app_download_record.dart';
import '../models/download_item.dart';

/// Manages a persistent registry of all media files downloaded via this app.
class AppDownloadRegistry extends Notifier<List<AppDownloadRecord>> {
  static const String _registryKey = 'app_download_registry_v1';

  @override
  List<AppDownloadRecord> build() {
    unawaited(_loadRecords());
    return <AppDownloadRecord>[];
  }

  Future<void> _loadRecords() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_registryKey);
      if (raw == null || raw.isEmpty) {
        state = <AppDownloadRecord>[];
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        state = <AppDownloadRecord>[];
        return;
      }

      final List<AppDownloadRecord> validRecords = <AppDownloadRecord>[];
      for (final dynamic item in decoded) {
        if (item is! Map<dynamic, dynamic>) {
          continue;
        }
        final AppDownloadRecord record = AppDownloadRecord.fromMap(
          Map<String, dynamic>.from(item),
        );
        if (record.filePath.isNotEmpty && File(record.filePath).existsSync()) {
          validRecords.add(record);
        }
      }

      validRecords.sort(
        (AppDownloadRecord a, AppDownloadRecord b) =>
            b.completedAt.compareTo(a.completedAt),
      );
      state = List<AppDownloadRecord>.unmodifiable(validRecords);
      unawaited(_saveRecords(validRecords));
    } catch (e, st) {
      AppLogger.w('Failed to load AppDownloadRegistry: $e\n$st');
    }
  }

  Future<void> _saveRecords(List<AppDownloadRecord> records) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String jsonStr = jsonEncode(
        records.map((AppDownloadRecord r) => r.toMap()).toList(growable: false),
      );
      await prefs.setString(_registryKey, jsonStr);
    } catch (e, st) {
      AppLogger.w('Failed to save AppDownloadRegistry: $e\n$st');
    }
  }

  /// Registers a newly completed download in the app registry.
  Future<void> registerCompleted(
    DownloadItem item, {
    String? resolvedFilePath,
  }) async {
    String targetPath = resolvedFilePath ?? '';
    int fileSizeBytes = 0;

    if (targetPath.isEmpty && item.outputPath.isNotEmpty) {
      try {
        final Directory dir = Directory(item.outputPath);
        if (await dir.exists()) {
          final String titleLower = item.title.trim().toLowerCase();
          final int matchLen = titleLower.length > 20 ? 20 : titleLower.length;
          final String prefix = matchLen > 0 ? titleLower.substring(0, matchLen) : '';
          await for (final FileSystemEntity entity in dir.list()) {
            if (entity is File) {
              final String name = p.basename(entity.path).toLowerCase();
              if (!name.endsWith('.part') &&
                  !name.endsWith('.ytdl') &&
                  prefix.isNotEmpty &&
                  name.contains(prefix)) {
                targetPath = entity.path;
                break;
              }
            }
          }
        }
      } catch (_) {}
    }

    if (targetPath.isNotEmpty && File(targetPath).existsSync()) {
      try {
        fileSizeBytes = File(targetPath).lengthSync();
      } catch (_) {}
    }

    final String fileName = targetPath.isNotEmpty
        ? p.basename(targetPath)
        : '${item.title}.${item.selectedFormat.extension}';

    final String ext = item.selectedFormat.extension.toLowerCase();
    final bool isAudio = ext == 'mp3' ||
        ext == 'm4a' ||
        ext == 'opus' ||
        ext == 'wav' ||
        ext == 'flac' ||
        ext == 'ogg';

    final AppDownloadRecord record = AppDownloadRecord(
      id: item.id,
      title: item.title,
      filePath: targetPath,
      fileName: fileName,
      url: item.url,
      fileSizeBytes: fileSizeBytes,
      completedAt: DateTime.now(),
      formatLabel: item.selectedFormat.displayLabel,
      thumbnailUrl: item.thumbnailUrl,
      isAudio: isAudio,
      isAppDownload: true,
    );

    final List<AppDownloadRecord> current = state
        .where(
          (AppDownloadRecord r) =>
              r.id != item.id &&
              (targetPath.isEmpty || r.filePath != targetPath),
        )
        .toList();
    current.insert(0, record);
    state = List<AppDownloadRecord>.unmodifiable(current);
    await _saveRecords(current);
    AppLogger.i('AppDownloadRegistry: registered "${item.title}" at $targetPath');
  }

  /// Removes a download record from the registry and optionally deletes physical file.
  Future<bool> deleteRecord(String id, {bool deleteFileFromDisk = true}) async {
    AppDownloadRecord? target;
    final List<AppDownloadRecord> updated = <AppDownloadRecord>[];
    for (final AppDownloadRecord r in state) {
      if (r.id == id) {
        target = r;
      } else {
        updated.add(r);
      }
    }

    if (target == null) {
      return false;
    }

    bool fileDeleted = false;
    if (deleteFileFromDisk && target.filePath.isNotEmpty) {
      try {
        final File file = File(target.filePath);
        if (await file.exists()) {
          await file.delete();
          fileDeleted = true;
          AppLogger.i('AppDownloadRegistry: deleted file ${target.filePath}');
        }
      } catch (e, st) {
        AppLogger.w('AppDownloadRegistry: error deleting file: $e\n$st');
      }
    }

    state = List<AppDownloadRecord>.unmodifiable(updated);
    await _saveRecords(updated);
    return fileDeleted;
  }

  /// Force refreshes registry against the filesystem.
  Future<void> refresh() async {
    await _loadRecords();
  }
}

/// Provider for [AppDownloadRegistry].
final NotifierProvider<AppDownloadRegistry, List<AppDownloadRecord>>
appDownloadRegistryProvider =
    NotifierProvider<AppDownloadRegistry, List<AppDownloadRecord>>(
      AppDownloadRegistry.new,
    );
