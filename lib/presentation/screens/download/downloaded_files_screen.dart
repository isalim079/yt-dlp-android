library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/permission_handler_util.dart';
import '../../../data/providers/settings_providers.dart';

class DownloadedFilesScreen extends ConsumerStatefulWidget {
  const DownloadedFilesScreen({super.key});

  @override
  ConsumerState<DownloadedFilesScreen> createState() =>
      _DownloadedFilesScreenState();
}

class _DownloadedFilesScreenState extends ConsumerState<DownloadedFilesScreen> {
  static const MethodChannel _channel = MethodChannel(
    'com.ytdownloader.app/ytdlp',
  );

  late Future<List<FileSystemEntity>> _filesFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = _loadFiles();
  }

  Future<List<FileSystemEntity>> _loadFiles() async {
    final String outputPath = ref.read(outputPathProvider);
    if (outputPath.isEmpty) {
      return <FileSystemEntity>[];
    }
    final Directory dir = Directory(outputPath);
    if (!await dir.exists()) {
      return <FileSystemEntity>[];
    }
    final List<FileSystemEntity> files = <FileSystemEntity>[];
    await for (final FileSystemEntity entity in dir.list()) {
      if (entity is! File) {
        continue;
      }
      final String lower = entity.path.toLowerCase();
      if (_isPlayable(lower)) {
        files.add(entity);
      }
    }
    files.sort((FileSystemEntity a, FileSystemEntity b) {
      try {
        final DateTime aTime = (a as File).statSync().modified;
        final DateTime bTime = (b as File).statSync().modified;
        return bTime.compareTo(aTime);
      } on Object {
        return 0;
      }
    });
    return files;
  }

  bool _isPlayable(String pathLower) {
    const List<String> exts = <String>[
      '.mp4',
      '.mkv',
      '.webm',
      '.mov',
      '.m4a',
      '.mp3',
    ];
    return exts.any((String ext) => pathLower.endsWith(ext));
  }

  Future<void> _refresh() async {
    setState(() {
      _filesFuture = _loadFiles();
    });
    await _filesFuture;
  }

  Future<void> _playWithDefaultPlayer(String path) async {
    try {
      await _channel.invokeMethod<void>('openFile', <String, dynamic>{
        'path': path,
      });
    } on Object catch (error, stackTrace) {
      AppLogger.e('Failed to open local file', error, stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.openFailed)),
      );
    }
  }

  Future<void> _confirmAndDelete(File file) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(AppStrings.deleteFileTitle),
          content: const Text(AppStrings.deleteFileBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.buttonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStrings.deleteFileConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final bool hasPermission =
        await PermissionHandlerUtil.ensureStoragePermission(context);
    if (!hasPermission) {
      return;
    }

    try {
      if (await file.exists()) {
        await file.delete();
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.deleteFileSuccess)),
      );
      await _refresh();
    } on Object catch (error, stackTrace) {
      AppLogger.e('Failed to delete local file', error, stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.deleteFileFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text(AppStrings.downloadedFilesTitle),
        actions: <Widget>[
          IconButton(
            tooltip: AppStrings.refreshList,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<FileSystemEntity>>(
        future: _filesFuture,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<FileSystemEntity>> snapshot,
        ) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<FileSystemEntity> files = snapshot.data ?? <FileSystemEntity>[];
          if (files.isEmpty) {
            return Center(
              child: Text(
                AppStrings.noDownloadedFiles,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: c.textSecondary,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppDimensions.paddingMd),
              itemCount: files.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final File file = files[index] as File;
                final String name = file.uri.pathSegments.isNotEmpty
                    ? file.uri.pathSegments.last
                    : file.path;
                return Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
                    border: Border.all(color: c.border),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.video_library_rounded,
                      color: c.primary,
                    ),
                    title: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: AppStrings.playFile,
                          onPressed: () => _playWithDefaultPlayer(file.path),
                          icon: Icon(
                            Icons.play_circle_fill_rounded,
                            color: c.primary,
                          ),
                        ),
                        IconButton(
                          tooltip: AppStrings.deleteFileConfirm,
                          onPressed: () => _confirmAndDelete(file),
                          icon: Icon(
                            Icons.delete_rounded,
                            color: c.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
