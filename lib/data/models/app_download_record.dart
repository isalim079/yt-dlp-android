library;

import 'dart:convert';

/// Represents a persistent record of a media file downloaded by this app.
class AppDownloadRecord {
  /// Creates an app download record with attribution metadata.
  const AppDownloadRecord({
    required this.id,
    required this.title,
    required this.filePath,
    required this.fileName,
    required this.url,
    required this.fileSizeBytes,
    required this.completedAt,
    required this.formatLabel,
    this.thumbnailUrl,
    this.isAudio = false,
    this.isAppDownload = true,
  });

  /// Unique item identifier.
  final String id;

  /// Media title.
  final String title;

  /// Absolute file path on the device.
  final String filePath;

  /// File basename.
  final String fileName;

  /// Source URL.
  final String url;

  /// Size in bytes at the time of download completion.
  final int fileSizeBytes;

  /// Timestamp when the download successfully finished.
  final DateTime completedAt;

  /// Format label (e.g. 1080p, audio only).
  final String formatLabel;

  /// Optional thumbnail URL for preview.
  final String? thumbnailUrl;

  /// Whether the file is an audio track.
  final bool isAudio;

  /// Explicit attribution tag designating file was downloaded via this app.
  final bool isAppDownload;

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'filePath': filePath,
      'fileName': fileName,
      'url': url,
      'fileSizeBytes': fileSizeBytes,
      'completedAt': completedAt.toIso8601String(),
      'formatLabel': formatLabel,
      'thumbnailUrl': thumbnailUrl,
      'isAudio': isAudio,
      'isAppDownload': isAppDownload,
    };
  }

  /// Deserializes from a map.
  factory AppDownloadRecord.fromMap(Map<String, dynamic> map) {
    return AppDownloadRecord(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      filePath: map['filePath']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      completedAt: DateTime.tryParse(map['completedAt']?.toString() ?? '') ??
          DateTime.now(),
      formatLabel: map['formatLabel']?.toString() ?? '',
      thumbnailUrl: map['thumbnailUrl']?.toString(),
      isAudio: (map['isAudio'] as bool?) ?? false,
      isAppDownload: (map['isAppDownload'] as bool?) ?? true,
    );
  }

  /// Serializes to JSON string.
  String toJson() => jsonEncode(toMap());

  /// Deserializes from JSON string.
  factory AppDownloadRecord.fromJson(String source) =>
      AppDownloadRecord.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
