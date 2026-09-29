/// Represents persisted user preferences for app behavior.
library;

/// Represents all user-configurable settings for the app.
class AppSettings {
  /// Creates a full immutable settings snapshot.
  const AppSettings({
    required this.outputPath,
    required this.themeMode,
    required this.defaultQuality,
    required this.maxConcurrentDownloads,
    required this.useHardwareAcceleration,
    required this.autoSelectBestFormat,
    required this.preferredFormat,
    required this.downloadSubtitles,
    required this.subtitleLanguage,
    required this.embedThumbnail,
    required this.addMetadata,
    required this.limitDownloadSpeed,
    required this.maxDownloadSpeedKbps,
    required this.skipExistingFiles,
    required this.createSubfolderForPlaylists,
    required this.playbackQuality,
    required this.playerClient,
    required this.backgroundPlayback,
    this.apiBaseUrl = '',
    this.preferServerPlayback = true,
    this.preferServerDownload = true,
  });

  /// Output path where yt-dlp writes files.
  final String outputPath;
  final AppThemeMode themeMode;
  final DefaultQuality defaultQuality;
  final int maxConcurrentDownloads;
  final bool useHardwareAcceleration;
  final bool autoSelectBestFormat;
  final PreferredFormat preferredFormat;
  final bool downloadSubtitles;
  final String subtitleLanguage;
  final bool embedThumbnail;
  final bool addMetadata;
  final bool limitDownloadSpeed;
  final int maxDownloadSpeedKbps;
  final bool skipExistingFiles;
  final bool createSubfolderForPlaylists;
  final PlaybackQualitySetting playbackQuality;
  final PlayerClientPreset playerClient;
  final bool backgroundPlayback;

  /// Production API origin (empty = local-only). Example: `http://10.0.2.2:8080`.
  final String apiBaseUrl;

  /// Prefer Playback API when [apiBaseUrl] is set.
  final bool preferServerPlayback;

  /// Prefer server download jobs when [apiBaseUrl] is set.
  final bool preferServerDownload;

  /// Default settings used on first launch.
  static const AppSettings defaults = AppSettings(
    outputPath: '',
    themeMode: AppThemeMode.system,
    defaultQuality: DefaultQuality.best,
    maxConcurrentDownloads: 3,
    useHardwareAcceleration: false,
    autoSelectBestFormat: false,
    preferredFormat: PreferredFormat.mp4,
    downloadSubtitles: false,
    subtitleLanguage: 'en',
    embedThumbnail: false,
    addMetadata: true,
    limitDownloadSpeed: false,
    maxDownloadSpeedKbps: 2048,
    skipExistingFiles: true,
    createSubfolderForPlaylists: true,
    playbackQuality: PlaybackQualitySetting.auto,
    playerClient: PlayerClientPreset.androidWeb,
    backgroundPlayback: true,
    apiBaseUrl: '',
    preferServerPlayback: true,
    preferServerDownload: true,
  );

  /// Returns a copy with optional field overrides.
  AppSettings copyWith({
    String? outputPath,
    AppThemeMode? themeMode,
    DefaultQuality? defaultQuality,
    int? maxConcurrentDownloads,
    bool? useHardwareAcceleration,
    bool? autoSelectBestFormat,
    PreferredFormat? preferredFormat,
    bool? downloadSubtitles,
    String? subtitleLanguage,
    bool? embedThumbnail,
    bool? addMetadata,
    bool? limitDownloadSpeed,
    int? maxDownloadSpeedKbps,
    bool? skipExistingFiles,
    bool? createSubfolderForPlaylists,
    PlaybackQualitySetting? playbackQuality,
    PlayerClientPreset? playerClient,
    bool? backgroundPlayback,
    String? apiBaseUrl,
    bool? preferServerPlayback,
    bool? preferServerDownload,
  }) {
    return AppSettings(
      outputPath: outputPath ?? this.outputPath,
      themeMode: themeMode ?? this.themeMode,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      useHardwareAcceleration:
          useHardwareAcceleration ?? this.useHardwareAcceleration,
      autoSelectBestFormat: autoSelectBestFormat ?? this.autoSelectBestFormat,
      preferredFormat: preferredFormat ?? this.preferredFormat,
      downloadSubtitles: downloadSubtitles ?? this.downloadSubtitles,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      embedThumbnail: embedThumbnail ?? this.embedThumbnail,
      addMetadata: addMetadata ?? this.addMetadata,
      limitDownloadSpeed: limitDownloadSpeed ?? this.limitDownloadSpeed,
      maxDownloadSpeedKbps: maxDownloadSpeedKbps ?? this.maxDownloadSpeedKbps,
      skipExistingFiles: skipExistingFiles ?? this.skipExistingFiles,
      createSubfolderForPlaylists:
          createSubfolderForPlaylists ?? this.createSubfolderForPlaylists,
      playbackQuality: playbackQuality ?? this.playbackQuality,
      playerClient: playerClient ?? this.playerClient,
      backgroundPlayback: backgroundPlayback ?? this.backgroundPlayback,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      preferServerPlayback: preferServerPlayback ?? this.preferServerPlayback,
      preferServerDownload: preferServerDownload ?? this.preferServerDownload,
    );
  }

  /// Serializes settings into primitive values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'outputPath': outputPath,
      'themeMode': themeMode.name,
      'defaultQuality': defaultQuality.name,
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'useHardwareAcceleration': useHardwareAcceleration,
      'autoSelectBestFormat': autoSelectBestFormat,
      'preferredFormat': preferredFormat.name,
      'downloadSubtitles': downloadSubtitles,
      'subtitleLanguage': subtitleLanguage,
      'embedThumbnail': embedThumbnail,
      'addMetadata': addMetadata,
      'limitDownloadSpeed': limitDownloadSpeed,
      'maxDownloadSpeedKbps': maxDownloadSpeedKbps,
      'skipExistingFiles': skipExistingFiles,
      'createSubfolderForPlaylists': createSubfolderForPlaylists,
      'playbackQuality': playbackQuality.name,
      'playerClient': playerClient.name,
      'backgroundPlayback': backgroundPlayback,
      'apiBaseUrl': apiBaseUrl,
      'preferServerPlayback': preferServerPlayback,
      'preferServerDownload': preferServerDownload,
    };
  }

  /// Deserializes settings while falling back to defaults.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      outputPath: json['outputPath']?.toString() ?? defaults.outputPath,
      themeMode: AppThemeMode.values.firstWhere(
        (AppThemeMode value) => value.name == json['themeMode'],
        orElse: () => defaults.themeMode,
      ),
      defaultQuality: DefaultQuality.values.firstWhere(
        (DefaultQuality value) => value.name == json['defaultQuality'],
        orElse: () => defaults.defaultQuality,
      ),
      maxConcurrentDownloads:
          (json['maxConcurrentDownloads'] as int?) ??
          defaults.maxConcurrentDownloads,
      useHardwareAcceleration:
          (json['useHardwareAcceleration'] as bool?) ??
          defaults.useHardwareAcceleration,
      autoSelectBestFormat:
          (json['autoSelectBestFormat'] as bool?) ??
          defaults.autoSelectBestFormat,
      preferredFormat: PreferredFormat.values.firstWhere(
        (PreferredFormat value) => value.name == json['preferredFormat'],
        orElse: () => defaults.preferredFormat,
      ),
      downloadSubtitles:
          (json['downloadSubtitles'] as bool?) ?? defaults.downloadSubtitles,
      subtitleLanguage:
          json['subtitleLanguage']?.toString() ?? defaults.subtitleLanguage,
      embedThumbnail:
          (json['embedThumbnail'] as bool?) ?? defaults.embedThumbnail,
      addMetadata: (json['addMetadata'] as bool?) ?? defaults.addMetadata,
      limitDownloadSpeed:
          (json['limitDownloadSpeed'] as bool?) ?? defaults.limitDownloadSpeed,
      maxDownloadSpeedKbps:
          (json['maxDownloadSpeedKbps'] as int?) ??
          defaults.maxDownloadSpeedKbps,
      skipExistingFiles:
          (json['skipExistingFiles'] as bool?) ?? defaults.skipExistingFiles,
      createSubfolderForPlaylists:
          (json['createSubfolderForPlaylists'] as bool?) ??
          defaults.createSubfolderForPlaylists,
      playbackQuality: PlaybackQualitySetting.values.firstWhere(
        (PlaybackQualitySetting value) => value.name == json['playbackQuality'],
        orElse: () => defaults.playbackQuality,
      ),
      playerClient: PlayerClientPreset.values.firstWhere(
        (PlayerClientPreset value) => value.name == json['playerClient'],
        orElse: () => defaults.playerClient,
      ),
      backgroundPlayback:
          (json['backgroundPlayback'] as bool?) ?? defaults.backgroundPlayback,
      apiBaseUrl: json['apiBaseUrl']?.toString() ?? defaults.apiBaseUrl,
      preferServerPlayback:
          (json['preferServerPlayback'] as bool?) ??
          defaults.preferServerPlayback,
      preferServerDownload:
          (json['preferServerDownload'] as bool?) ??
          defaults.preferServerDownload,
    );
  }
}

enum AppThemeMode {
  light,
  dark,
  system;

  /// Human readable label for picker rows.
  String get label => switch (this) {
    AppThemeMode.light => 'Light',
    AppThemeMode.dark => 'Dark',
    AppThemeMode.system => 'System default',
  };
}

enum DefaultQuality {
  best,
  p1080,
  p720,
  p480,
  p360,
  audioOnly;

  /// Human readable label for picker rows.
  String get label => switch (this) {
    DefaultQuality.best => 'Best available',
    DefaultQuality.p1080 => '1080p',
    DefaultQuality.p720 => '720p',
    DefaultQuality.p480 => '480p',
    DefaultQuality.p360 => '360p',
    DefaultQuality.audioOnly => 'Audio only',
  };
}

enum PlaybackQualitySetting {
  auto,
  p2160,
  p1440,
  p1080,
  p720,
  p480,
  p360;

  /// Human readable label for picker rows.
  String get label => switch (this) {
    PlaybackQualitySetting.auto => 'Auto (best)',
    PlaybackQualitySetting.p2160 => '2160p',
    PlaybackQualitySetting.p1440 => '1440p',
    PlaybackQualitySetting.p1080 => '1080p',
    PlaybackQualitySetting.p720 => '720p',
    PlaybackQualitySetting.p480 => '480p',
    PlaybackQualitySetting.p360 => '360p',
  };
}

enum PlayerClientPreset {
  androidWeb,
  androidVr,
  web,
  tv;

  /// Value passed to `youtube:player_client=`.
  String get ytDlpValue => switch (this) {
    PlayerClientPreset.androidWeb => 'android,web',
    PlayerClientPreset.androidVr => 'android_vr,web',
    PlayerClientPreset.web => 'web',
    PlayerClientPreset.tv => 'tv',
  };

  /// Human readable label for picker rows.
  String get label => switch (this) {
    PlayerClientPreset.androidWeb => 'Android + Web (default)',
    PlayerClientPreset.androidVr => 'Android VR (SABR workaround)',
    PlayerClientPreset.web => 'Web',
    PlayerClientPreset.tv => 'TV',
  };
}

enum PreferredFormat {
  mp4,
  mkv,
  webm,
  mp3,
  m4a;

  /// Human readable label for picker rows.
  String get label => switch (this) {
    PreferredFormat.mp4 => 'MP4',
    PreferredFormat.mkv => 'MKV',
    PreferredFormat.webm => 'WebM',
    PreferredFormat.mp3 => 'MP3 (audio)',
    PreferredFormat.m4a => 'M4A (audio)',
  };
}
