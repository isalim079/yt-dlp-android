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
import '../../../data/services/ytdlp_platform_channel.dart';

enum _FileCategory { all, videos, audio }

const List<String> _videoExtensions = <String>[
  '.mp4',
  '.mkv',
  '.webm',
  '.mov',
  '.avi',
  '.flv',
];

const List<String> _audioExtensions = <String>[
  '.mp3',
  '.m4a',
  '.flac',
  '.opus',
  '.wav',
  '.ogg',
  '.aac',
];

const List<String> _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Displays locally downloaded video and audio files with playback, search, filter, and share.
class DownloadedFilesScreen extends ConsumerStatefulWidget {
  /// Creates the downloaded files screen.
  const DownloadedFilesScreen({super.key});

  @override
  ConsumerState<DownloadedFilesScreen> createState() =>
      _DownloadedFilesScreenState();
}

class _DownloadedFilesScreenState extends ConsumerState<DownloadedFilesScreen> {
  late Future<List<File>> _filesFuture;
  _FileCategory _selectedCategory = _FileCategory.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filesFuture = _loadFiles();
    _searchController.addListener(() {
      final String trimmed = _searchController.text.trim().toLowerCase();
      if (trimmed != _searchQuery) {
        setState(() {
          _searchQuery = trimmed;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<File>> _loadFiles() async {
    final String outputPath = ref.read(outputPathProvider);
    if (outputPath.isEmpty) {
      return <File>[];
    }
    final Directory dir = Directory(outputPath);
    if (!await dir.exists()) {
      return <File>[];
    }
    final List<File> files = <File>[];
    await for (final FileSystemEntity entity in dir.list()) {
      if (entity is! File) {
        continue;
      }
      final String lower = entity.path.toLowerCase();
      if (_isVideo(lower) || _isAudio(lower)) {
        files.add(entity);
      }
    }
    files.sort((File a, File b) {
      try {
        final DateTime aTime = a.statSync().modified;
        final DateTime bTime = b.statSync().modified;
        return bTime.compareTo(aTime);
      } on Object {
        return 0;
      }
    });
    return files;
  }

  bool _isVideo(String pathLower) =>
      _videoExtensions.any((String ext) => pathLower.endsWith(ext));

  bool _isAudio(String pathLower) =>
      _audioExtensions.any((String ext) => pathLower.endsWith(ext));

  Future<void> _refresh() async {
    setState(() {
      _filesFuture = _loadFiles();
    });
    await _filesFuture;
  }

  Future<void> _playWithDefaultPlayer(String path) async {
    HapticFeedback.lightImpact();
    try {
      await YtdlpPlatformChannel.openFile(path);
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

  Future<void> _shareFile(String path) async {
    HapticFeedback.lightImpact();
    try {
      await YtdlpPlatformChannel.shareFile(path);
    } on Object catch (error, stackTrace) {
      AppLogger.e('Failed to share local file', error, stackTrace);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to share file')),
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime dt) {
    final String month = _monthNames[dt.month - 1];
    final String hour = dt.hour.toString().padLeft(2, '0');
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '$month ${dt.day}, $hour:$minute';
  }

  List<File> _filterFiles(List<File> files) {
    return files.where((File f) {
      final String lower = f.path.toLowerCase();
      if (_selectedCategory == _FileCategory.videos && !_isVideo(lower)) {
        return false;
      }
      if (_selectedCategory == _FileCategory.audio && !_isAudio(lower)) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final String name = f.uri.pathSegments.isNotEmpty
            ? f.uri.pathSegments.last.toLowerCase()
            : lower;
        if (!name.contains(_searchQuery)) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text(AppStrings.downloadedFilesTitle),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.background,
        actions: <Widget>[
          IconButton(
            tooltip: AppStrings.refreshList,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: <Widget>[
              // Search & Filter header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingMd,
                  vertical: AppDimensions.spaceSm,
                ),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _searchController,
                      style: TextStyle(color: c.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: AppStrings.searchFilesHint,
                        hintStyle: TextStyle(
                          color: c.textSecondary.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: c.textSecondary,
                          size: 20,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: c.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: c.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: c.primary, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    Row(
                      children: <Widget>[
                        ChoiceChip(
                          label: const Text(AppStrings.filterAll),
                          selected: _selectedCategory == _FileCategory.all,
                          onSelected: (bool selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategory = _FileCategory.all;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: AppDimensions.spaceSm),
                        ChoiceChip(
                          avatar: const Icon(Icons.movie_outlined, size: 16),
                          label: const Text(AppStrings.filterVideos),
                          selected: _selectedCategory == _FileCategory.videos,
                          onSelected: (bool selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategory = _FileCategory.videos;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: AppDimensions.spaceSm),
                        ChoiceChip(
                          avatar: const Icon(Icons.audiotrack_outlined, size: 16),
                          label: const Text(AppStrings.filterAudio),
                          selected: _selectedCategory == _FileCategory.audio,
                          onSelected: (bool selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategory = _FileCategory.audio;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<File>>(
                  future: _filesFuture,
                  builder: (
                    BuildContext context,
                    AsyncSnapshot<List<File>> snapshot,
                  ) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final List<File> allFiles = snapshot.data ?? <File>[];
                    final List<File> files = _filterFiles(allFiles);

                    if (allFiles.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.folder_open_rounded,
                              size: 56,
                              color: c.textSecondary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppStrings.noDownloadedFiles,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (files.isEmpty) {
                      return Center(
                        child: Text(
                          'No matching files found',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.paddingMd,
                          vertical: AppDimensions.spaceSm,
                        ),
                        itemCount: files.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final File file = files[index];
                          final String name = file.uri.pathSegments.isNotEmpty
                              ? file.uri.pathSegments.last
                              : file.path;
                          final bool isAud = _isAudio(name.toLowerCase());

                          int fileSize = 0;
                          DateTime? modifiedTime;
                          try {
                            final FileStat stat = file.statSync();
                            fileSize = stat.size;
                            modifiedTime = stat.modified;
                          } on Object {
                            // stat fallback
                          }

                          return Container(
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(
                                AppDimensions.cardRadius,
                              ),
                              border: Border.all(color: c.border),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppDimensions.paddingMd,
                                vertical: 4,
                              ),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isAud
                                      ? c.primary.withValues(alpha: 0.12)
                                      : c.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isAud
                                      ? Icons.audiotrack_rounded
                                      : Icons.movie_rounded,
                                  color: isAud ? c.primary : c.success,
                                  size: 24,
                                ),
                              ),
                              title: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${_formatBytes(fileSize)} • ${modifiedTime != null ? _formatDate(modifiedTime) : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: c.textSecondary),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  IconButton(
                                    tooltip: AppStrings.playFile,
                                    onPressed: () =>
                                        _playWithDefaultPlayer(file.path),
                                    icon: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: c.primary,
                                      size: 28,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: AppStrings.shareFile,
                                    onPressed: () => _shareFile(file.path),
                                    icon: Icon(
                                      Icons.share_outlined,
                                      color: c.textSecondary,
                                      size: 22,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: AppStrings.deleteFromDevice,
                                    onPressed: () => _confirmAndDelete(file),
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      color: c.error,
                                      size: 22,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
