/// Riverpod providers for persisted app settings.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../repositories/settings_repository.dart';

/// Provides [SettingsRepository] instance.
final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>((Ref ref) {
      return SettingsRepository();
    });

/// Loads settings once at startup and exposes mutations.
final AsyncNotifierProvider<SettingsNotifier, AppSettings> settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// Async settings state and persistence mutations.
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final SettingsRepository repo = ref.read(settingsRepositoryProvider);
    final AppSettings settings = await repo.loadSettings();
    if (settings.outputPath.isEmpty) {
      final String defaultPath = await repo.resolveDefaultOutputPath();
      final AppSettings updated = settings.copyWith(outputPath: defaultPath);
      await repo.saveSettings(updated);
      return updated;
    }
    return settings;
  }

  /// Updates a single setting via [updater] and persists immediately.
  Future<void> updateSetting(AppSettings Function(AppSettings) updater) async {
    final AppSettings current = await future;
    final AppSettings updated = updater(current);
    state = AsyncData(updated);
    await ref.read(settingsRepositoryProvider).saveSettings(updated);
  }

  /// Attempts to apply [newPath], creating it when missing.
  ///
  /// Returns true when persisted; otherwise leaves state unchanged.
  Future<bool> updateOutputPath(String newPath) async {
    final AppSettings current = await future;
    final String trimmed = newPath.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final Directory dir = Directory(trimmed);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } on Object {
      state = AsyncData(current);
      return false;
    }
    final AppSettings updated = current.copyWith(outputPath: trimmed);
    state = AsyncData(updated);
    await ref.read(settingsRepositoryProvider).saveSettings(updated);
    return true;
  }
}

/// Convenience provider for current app [ThemeMode].
final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>((Ref ref) {
  final AppSettings? settings = ref.watch(settingsProvider).valueOrNull;
  return switch (settings?.themeMode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

/// Convenience provider for output path.
final Provider<String> outputPathProvider = Provider<String>((Ref ref) {
  return ref.watch(settingsProvider).valueOrNull?.outputPath ?? '';
});
