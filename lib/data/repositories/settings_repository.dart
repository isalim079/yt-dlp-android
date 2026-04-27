/// SharedPreferences-backed user settings persistence.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

/// Handles reading and writing all settings to SharedPreferences.
///
/// Single source of truth for all persisted user preferences.
class SettingsRepository {
  static const String _keyPrefix = 'setting_';
  static const String _outputPathKey = '${_keyPrefix}output_path';
  static const String _themeModeKey = '${_keyPrefix}theme_mode';
  static const String _defaultQualityKey = '${_keyPrefix}default_quality';
  static const String _maxConcurrentKey = '${_keyPrefix}max_concurrent';
  static const String _autoSelectBestKey = '${_keyPrefix}auto_select_best';
  static const String _preferredFormatKey = '${_keyPrefix}preferred_format';
  static const String _downloadSubtitlesKey = '${_keyPrefix}download_subtitles';
  static const String _subtitleLanguageKey = '${_keyPrefix}subtitle_language';
  static const String _embedThumbnailKey = '${_keyPrefix}embed_thumbnail';
  static const String _addMetadataKey = '${_keyPrefix}add_metadata';
  static const String _limitSpeedKey = '${_keyPrefix}limit_speed';
  static const String _maxSpeedKbpsKey = '${_keyPrefix}max_speed_kbps';
  static const String _skipExistingKey = '${_keyPrefix}skip_existing';
  static const String _playlistSubfolderKey = '${_keyPrefix}playlist_subfolder';
  static const String _useHardwareAccelerationKey =
      '${_keyPrefix}use_hw_acceleration';

  /// Loads all settings from SharedPreferences.
  ///
  /// Falls back to [AppSettings.defaults] for any missing key.
  Future<AppSettings> loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return AppSettings(
      outputPath:
          prefs.getString(_outputPathKey) ?? AppSettings.defaults.outputPath,
      themeMode: AppThemeMode.values.firstWhere(
        (AppThemeMode mode) => mode.name == prefs.getString(_themeModeKey),
        orElse: () => AppSettings.defaults.themeMode,
      ),
      defaultQuality: DefaultQuality.values.firstWhere(
        (DefaultQuality quality) =>
            quality.name == prefs.getString(_defaultQualityKey),
        orElse: () => AppSettings.defaults.defaultQuality,
      ),
      maxConcurrentDownloads:
          prefs.getInt(_maxConcurrentKey) ??
          AppSettings.defaults.maxConcurrentDownloads,
      useHardwareAcceleration:
          prefs.getBool(_useHardwareAccelerationKey) ??
          AppSettings.defaults.useHardwareAcceleration,
      autoSelectBestFormat:
          prefs.getBool(_autoSelectBestKey) ??
          AppSettings.defaults.autoSelectBestFormat,
      preferredFormat: PreferredFormat.values.firstWhere(
        (PreferredFormat format) =>
            format.name == prefs.getString(_preferredFormatKey),
        orElse: () => AppSettings.defaults.preferredFormat,
      ),
      downloadSubtitles:
          prefs.getBool(_downloadSubtitlesKey) ??
          AppSettings.defaults.downloadSubtitles,
      subtitleLanguage:
          prefs.getString(_subtitleLanguageKey) ??
          AppSettings.defaults.subtitleLanguage,
      embedThumbnail:
          prefs.getBool(_embedThumbnailKey) ??
          AppSettings.defaults.embedThumbnail,
      addMetadata:
          prefs.getBool(_addMetadataKey) ?? AppSettings.defaults.addMetadata,
      limitDownloadSpeed:
          prefs.getBool(_limitSpeedKey) ??
          AppSettings.defaults.limitDownloadSpeed,
      maxDownloadSpeedKbps:
          prefs.getInt(_maxSpeedKbpsKey) ??
          AppSettings.defaults.maxDownloadSpeedKbps,
      skipExistingFiles:
          prefs.getBool(_skipExistingKey) ??
          AppSettings.defaults.skipExistingFiles,
      createSubfolderForPlaylists:
          prefs.getBool(_playlistSubfolderKey) ??
          AppSettings.defaults.createSubfolderForPlaylists,
    );
  }

  /// Saves a complete [settings] object to SharedPreferences.
  Future<void> saveSettings(AppSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_outputPathKey, settings.outputPath);
    await prefs.setString(_themeModeKey, settings.themeMode.name);
    await prefs.setString(_defaultQualityKey, settings.defaultQuality.name);
    await prefs.setInt(_maxConcurrentKey, settings.maxConcurrentDownloads);
    await prefs.setBool(
      _useHardwareAccelerationKey,
      settings.useHardwareAcceleration,
    );
    await prefs.setBool(_autoSelectBestKey, settings.autoSelectBestFormat);
    await prefs.setString(_preferredFormatKey, settings.preferredFormat.name);
    await prefs.setBool(_downloadSubtitlesKey, settings.downloadSubtitles);
    await prefs.setString(_subtitleLanguageKey, settings.subtitleLanguage);
    await prefs.setBool(_embedThumbnailKey, settings.embedThumbnail);
    await prefs.setBool(_addMetadataKey, settings.addMetadata);
    await prefs.setBool(_limitSpeedKey, settings.limitDownloadSpeed);
    await prefs.setInt(_maxSpeedKbpsKey, settings.maxDownloadSpeedKbps);
    await prefs.setBool(_skipExistingKey, settings.skipExistingFiles);
    await prefs.setBool(
      _playlistSubfolderKey,
      settings.createSubfolderForPlaylists,
    );
  }

  /// Saves one settings field using its full preference [key].
  Future<void> saveSingleSetting(String key, dynamic value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString(key, value);
      return;
    }
    if (value is int) {
      await prefs.setInt(key, value);
      return;
    }
    if (value is bool) {
      await prefs.setBool(key, value);
      return;
    }
    throw ArgumentError('Unsupported setting value type for key: $key');
  }

  /// Resolves the default output path for this device/platform.
  ///
  /// Android -> `/storage/emulated/0/Download`.
  /// Windows -> `C:\Users\{user}\Downloads`.
  /// macOS/Linux -> `~/Downloads`.
  Future<String> resolveDefaultOutputPath() async {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download';
    }
    if (Platform.isWindows) {
      final String userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\';
      return p.join(userProfile, 'Downloads');
    }
    final String home = Platform.environment['HOME'] ?? '.';
    return p.join(home, 'Downloads');
  }

  /// Resets all settings keys to [AppSettings.defaults].
  Future<void> resetToDefaults() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_outputPathKey);
    await prefs.remove(_themeModeKey);
    await prefs.remove(_defaultQualityKey);
    await prefs.remove(_maxConcurrentKey);
    await prefs.remove(_useHardwareAccelerationKey);
    await prefs.remove(_autoSelectBestKey);
    await prefs.remove(_preferredFormatKey);
    await prefs.remove(_downloadSubtitlesKey);
    await prefs.remove(_subtitleLanguageKey);
    await prefs.remove(_embedThumbnailKey);
    await prefs.remove(_addMetadataKey);
    await prefs.remove(_limitSpeedKey);
    await prefs.remove(_maxSpeedKbpsKey);
    await prefs.remove(_skipExistingKey);
    await prefs.remove(_playlistSubfolderKey);
  }
}
