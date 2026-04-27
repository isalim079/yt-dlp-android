# yt-dlp (Flutter Downloader Client)

Production-focused Flutter app for downloading YouTube videos and playlists
using yt-dlp, with Android-native integration and polished UX.

## Overview

This project provides a mobile-first UI for:

- Fetching video/playlist metadata
- Selecting formats for single videos
- Auto best-quality playlist downloads
- Managing active/queued/completed/failed jobs
- Opening downloaded media in the system default player
- Running downloads in Android background via foreground service

The app is designed for reliability, clear error handling, and a clean
download workflow.

## Core Features

- **Single Video Downloads**
  - URL search and metadata fetch
  - Format selection
  - Live progress, ETA, and processing states
- **Playlist Downloads**
  - Playlist-aware flow
  - Skips manual format chooser for playlists
  - Uses yt-dlp auto best fallback (`bv*+ba/b`)
  - Serialized queue behavior for smoother processing
- **Download Management**
  - Queue, retry, cancel, remove
  - Completed/failed history
  - Downloaded Files screen with play and delete actions
- **Android Native Bridge**
  - `youtubedl-android` via `MethodChannel` + `EventChannel`
  - Native progress events surfaced to Flutter
  - Foreground service support for background downloading
- **UX and Stability**
  - Runtime permission checks
  - Connectivity-aware behavior
  - Error boundary and structured logging
  - Light-theme polished UI

## Tech Stack

- **Flutter** + **Dart**
- **Riverpod** (state management)
- **Kotlin** (Android platform integration)
- **youtubedl-android** (Android yt-dlp runtime)
- **permission_handler**, **connectivity_plus**, **shared_preferences**

## Project Structure

High-level layout:

- `lib/core/` - constants, theme, utilities, error handling
- `lib/data/` - models, providers, repositories, download services
- `lib/presentation/` - screens and widgets
- `android/` - native platform bridge and manifest/service config
- `assets/` - icons and bundled binaries (desktop targets)

## Getting Started

### 1) Prerequisites

- Flutter SDK (stable)
- Dart SDK (from Flutter)
- Android Studio / Xcode as needed for platform builds
- A connected device or emulator

### 2) Install dependencies

```bash
flutter pub get
```

### 3) Run the app

```bash
flutter run
```

## Build

Debug APK:

```bash
flutter build apk --debug
```

Release APK:

```bash
flutter build apk --release
```

## Android Notes

- App uses a native foreground service for background downloads.
- Required foreground service permissions are declared in
  `AndroidManifest.xml`.
- Storage/media permissions are handled at runtime based on Android SDK level.
- `FileProvider` is configured for opening local media files with external
  players.

## Useful Commands

Generate launcher icons:

```bash
dart run flutter_launcher_icons
```

Generate native splash:

```bash
dart run flutter_native_splash:create
```

Static analysis:

```bash
flutter analyze
```

## Troubleshooting

- **403 / Forbidden during download**
  - Usually source-side restriction.
  - App includes fallback retry behavior for safer format selection.
- **Video unavailable / copyright claim**
  - Content is restricted or removed on source platform.
- **No files visible in queue after relaunch**
  - Use the **Downloaded Files** screen to view actual files from output path.
- **Cannot open or delete files**
  - Grant storage/media permissions when prompted.

## Disclaimer

Use this app responsibly and comply with YouTube Terms of Service and local
copyright laws. You are responsible for how downloaded content is used.
