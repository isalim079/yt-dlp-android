/// User-visible strings for the whole application (no inline literals).
library;

abstract final class AppStrings {
  // App
  static const String appName = 'yt-dlp';

  // Bundled yt-dlp bootstrap
  static const String binaryInitializing = 'Preparing downloader…';
  static const String binaryInitError =
      'Could not prepare the downloader. Check storage space and try again.';
  static const String retryButton = 'Try again';

  // Screen titles
  static const String homeScreenTitle = 'Home';
  static const String downloadScreenTitle = 'Downloads';
  static const String settingsScreenTitle = 'Settings';
  static const String settingsTitle = 'Settings';

  // Home
  static const String homePlaceholderBody = 'Paste a video URL to get started.';
  static const String hintVideoUrl = 'https://www.youtube.com/watch?v=…';
  static const String urlHint = 'Paste YouTube URL here…';
  static const String searchButton = 'Search';
  static const String downloadButton = 'Download';
  static const String selectFormat = 'Select quality';
  static const String pasteFromClipboard = 'Paste from clipboard';
  static const String playlistBanner = 'Playlist detected';
  static const String playlistVideosPrefix = 'Playlist:';
  static const String playlistVideosWord = 'videos';
  static const String videoWillBeSavedTo = 'Video will be saved to:';
  static const String noFormatsFound =
      'No downloadable formats found for this URL.';
  static const String errorTitle = 'Something went wrong';
  static const String formatSelectedPrefix = '✓ ';
  static const String formatSelectedSuffix = ' selected';
  static const String labelUrlField = 'Video URL';

  // Navigation (placeholders)
  static const String navDownloads = 'Downloads';
  static const String navSettings = 'Settings';
  static const String navHome = 'Home';
  static const String navGoHome = 'Go to Home';

  // Buttons
  static const String buttonPasteUrl = 'Paste URL';
  static const String buttonStartDownload = 'Start download';
  static const String buttonCancel = 'Cancel';
  static const String buttonRetry = 'Retry';
  static const String buttonOpenFolder = 'Open folder';
  static const String buttonClear = 'Clear';
  static const String buttonSave = 'Save';
  static const String buttonContinue = 'Continue';
  static const String buttonClose = 'Close';
  static const String buttonSelectFolder = 'Choose folder';
  static const String buttonGrantPermission = 'Grant permission';

  // Downloads screen
  static const String downloadsTitle = 'Downloads';
  static const String downloadsEmptyTitle = 'No downloads yet';
  static const String downloadsEmptySubtitle =
      'Start a download from the home tab.';
  static const String noDownloadsYet = 'No downloads yet';
  static const String noDownloadsSubtitle =
      'Go back home and paste a YouTube URL to start';
  static const String downloadStarted = 'Download started!';
  static const String clearCompleted = 'Clear completed';
  static const String clearDone = 'Clear done';
  static const String cancelDownload = 'Cancel';
  static const String retryDownload = 'Retry';
  static const String removeDownload = 'Remove';
  static const String openFolder = 'Open folder';
  static const String playFile = 'Play';
  static const String openWith = 'Open with';
  static const String openWithSystem = 'System Default Player';
  static const String openWithSystemSub = 'Let Android choose';
  static const String openWithVlc = 'VLC Media Player';
  static const String openWithMx = 'MX Player';
  static const String openWithMpv = 'MPV Player';
  static const String openFailed =
      'Could not open file. Check installed players.';
  static const String noPlayerFound = 'No video player found';
  static const String statusFinalizing = 'Finalizing…';
  static const String statusProcessing = 'Processing...';
  static const String statusPreparing = 'Preparing...';
  static const String waitingInQueue = 'Waiting in queue…';
  static const String waitingInQueuePlain = 'Waiting in queue';
  static const String sectionDownloading = 'Downloading';
  static const String sectionCompleted = 'Completed';
  static const String sectionFailed = 'Failed';
  static const String sectionQueued = 'Queued';
  static const String sectionActive = 'Active';
  static const String sectionDone = 'Done';
  static const String labelFormatSelector = 'Format';
  static const String labelProgress = 'Progress';

  // Download status labels (UI)
  static const String statusQueued = 'Queued';
  static const String statusDownloading = 'Downloading';
  static const String statusCompleted = 'Completed';
  static const String statusFailed = 'Failed';

  // Settings
  static const String resetDefaults = 'Reset';
  static const String resetConfirmTitle = 'Reset settings?';
  static const String resetConfirmBody =
      'All settings will be restored to defaults. '
      'Your downloads will not be affected.';
  static const String resetConfirmButton = 'Reset';
  static const String settingsSaved = 'Settings saved';
  static const String locationUpdated = 'Download location updated';
  static const String historyCleared = 'Download history cleared';
  static const String chooseThemeTitle = 'Choose theme';
  static const String chooseQualityTitle = 'Choose default quality';
  static const String chooseFormatTitle = 'Choose preferred format';
  static const String chooseConcurrentTitle = 'Choose simultaneous downloads';
  static const String chooseSubLanguageTitle = 'Choose subtitle language';
  static const String chooseSpeedTitle = 'Choose speed limit';
  static const String clearHistoryTitle = 'Clear download history?';
  static const String clearHistoryBody =
      'This will remove completed and failed entries from history.';
  static const String clearHistoryConfirm = 'Clear';
  static const String reportBugUrl = 'https://github.com/yt-dlp/yt-dlp/issues';

  // Settings section titles
  static const String sectionDownloadLocation = 'DOWNLOAD LOCATION';
  static const String sectionVideoQuality = 'VIDEO QUALITY';
  static const String sectionDownloadOptions = 'DOWNLOAD OPTIONS';
  static const String sectionAdvanced = 'ADVANCED';
  static const String sectionSpeedLimit = 'SPEED LIMIT';
  static const String sectionAppearance = 'APPEARANCE';
  static const String sectionAbout = 'ABOUT';

  // Settings tile labels
  static const String tileDownloadLocation = 'Download location';
  static const String tilePlaylistSubfolder = 'Create subfolder for playlists';
  static const String tilePlaylistSubfolderSub =
      'Playlist videos saved in a named subfolder';
  static const String tileDefaultQuality = 'Default quality';
  static const String tilePreferredFormat = 'Preferred format';
  static const String tileAutoSelectBest = 'Auto-select best format';
  static const String tileAutoSelectBestSub =
      'Skip format dropdown — download best quality instantly';
  static const String tileMaxConcurrent = 'Max simultaneous downloads';
  static const String tileSkipExisting = 'Skip existing files';
  static const String tileSkipExistingSub =
      'Do not re-download files that already exist';
  static const String tileDownloadSubs = 'Download subtitles';
  static const String tileDownloadSubsSub =
      'Auto-download subtitles when available';
  static const String tileSubLanguage = 'Subtitle language';
  static const String tileEmbedThumbnail = 'Embed thumbnail';
  static const String tileEmbedThumbnailSub =
      'Save video thumbnail inside the file metadata';
  static const String tileAddMetadata = 'Add metadata';
  static const String tileAddMetadataSub =
      'Embed title, uploader, and date in file';
  static const String tileLimitSpeed = 'Limit download speed';
  static const String tileLimitSpeedSub =
      'Prevent yt-dlp from using full bandwidth';
  static const String tileMaxSpeed = 'Max download speed';
  static const String tileTheme = 'Theme';
  static const String tileAppVersion = 'App version';
  static const String tileYtdlpVersion = 'yt-dlp version';
  static const String tileReportBug = 'Report a bug';
  static const String tileReportBugSub = 'Open GitHub issues page';
  static const String tileClearHistory = 'Clear download history';
  static const String tileClearHistorySub =
      'Remove all completed and failed entries';
  static const String appVersion = '1.0.0';
  static const String downloadsAtOnceSuffix = 'downloads at once';
  static const String speedUnlimited = 'Unlimited';
  static const String speedKbpsSuffix = 'KB/s';
  static const String speedMbpsSuffix = 'MB/s';
  static const List<String> subtitleLanguageOptions = <String>[
    'en',
    'bn',
    'hi',
    'ar',
    'es',
  ];

  static const String settingsSectionGeneral = 'General';
  static const String settingsSectionDownloads = 'Downloads';
  static const String settingsSectionAbout = 'About';
  static const String settingsTheme = 'Theme';
  static const String settingsThemeSystem = 'System';
  static const String settingsThemeLight = 'Light';
  static const String settingsThemeDark = 'Dark';
  static const String settingsDefaultPath = 'Default download folder';
  static const String settingsMaxConcurrent = 'Max concurrent downloads';
  static const String settingsClearCache = 'Clear cache';
  static const String aboutVersionLabel = 'Version';
  static const String aboutOpenSource = 'Open source licenses';

  // Errors
  static const String errorGeneric = 'Something went wrong. Please try again.';

  /// Unsupported or empty URL for yt-dlp metadata requests.
  static const String errorInvalidUrl = 'Invalid or unsupported URL.';
  static const String errorTimeout =
      'Request timed out. Check your connection.';
  static const String errorNoFormats =
      'No downloadable formats were found for this video.';
  static const String errorProcessFailed =
      'The downloader reported an error while reading this link.';
  static const String errorUnknown =
      'An unexpected error occurred. Please try again.';
  static const String errorParseVideoInformation =
      'Failed to parse video information.';
  static const String errorNetwork =
      'Network error. Check your connection and try again.';
  static const String errorPermissionDenied =
      'Permission was denied. Grant access in system settings.';
  static const String errorYtdlpNotFound =
      'The downloader executable was not found.';
  static const String errorDiskFull = 'Not enough free storage space.';
  static const String errorDownloadCancelled = 'Cancelled by user';

  // Snackbar
  static const String snackbarSaved = 'Saved';
  static const String snackbarCopied = 'Copied to clipboard';
  static const String snackbarDownloadStarted = 'Download started';
  static const String snackbarDownloadCompleted = 'Download completed';

  /// Success line when a single download finishes, e.g. `✓ Title downloaded`.
  static String downloadCompletedLine(String title) {
    final String safe = title.trim().isEmpty ? notAvailable : title.trim();
    return '$formatSelectedPrefix$safe downloaded successfully';
  }

  // Permissions
  static const String permissionStorageRationale =
      'Storage access is needed to save downloaded files.';
  static const String permissionDeniedTitle = 'Storage permission required';
  static const String permissionDeniedBody =
      'YT Downloader needs storage access to save videos to your device. '
      'Please grant permission in app settings.';
  static const String permissionNotNow = 'Not now';
  static const String openAppSettings = 'Open Settings';

  // Connectivity
  static const String offlineMessage = 'No internet connection';
  static const String errorNoInternet =
      'No internet connection. Please check your network and try again.';

  // Error boundary
  static const String unexpectedError = 'Something went wrong';
  static const String unexpectedErrorSub =
      'An unexpected error occurred. Please restart the app.';
  static const String restartApp = 'Close app';

  // Home empty state
  static const String homeEmptyTitle = 'Ready to download';
  static const String homeEmptySubtitle =
      'Paste any YouTube video or playlist URL above and tap Search';
  static const String homeUrlHintWatch = 'youtube.com/watch?v=…';
  static const String homeUrlHintShort = 'youtu.be/…';
  static const String homeUrlHintPlaylist = 'youtube.com/playlist?list=…';

  // Share intent
  static const String shareIntentReceived = 'YouTube URL received!';
  static const String subtitleDownloadEasy = 'Download videos easily';
  static const String selectQuality = 'Select Quality';
  static const String optionsCountSuffix = 'options';
  static const String tapToStartDownloading = 'Tap to start downloading';
  static const String downloadCompleteTitle = 'Download complete!';
  static const String playerPackageVlc = 'org.videolan.vlc';
  static const String playerPackageMx = 'com.mxtech.videoplayer.ad';
  static const String playerPackageMpv = 'is.xyz.mpv';
  static const String cancelDownloadTitle = 'Cancel download?';
  static const String cancelDownloadBody = 'The partial file will be deleted.';
  static const String keepDownloading = 'Keep downloading';
  static const String cancelDownloadConfirm = 'Cancel download';
  static const String playlistOptionTitle = 'Download options';
  static const String playlistAllVideos = 'All videos';
  static const String playlistAudioOnly = 'Audio only';

  // Misc
  static const String loading = 'Loading…';
  static const String notAvailable = '—';

  // File size labels (used by [VideoFormat.formattedFileSize])
  static const String fileSizeUnknown = 'Unknown size';
  static const String fileSizeUnitBytes = 'B';
  static const String fileSizeUnitKb = 'KB';
  static const String fileSizeUnitMb = 'MB';
  static const String fileSizeUnitGb = 'GB';

  // yt-dlp format display fragments (joined in [FormatParser])
  static const String formatLabelSeparator = ' • ';
  static const String formatAudioOnlyLabel = 'Audio only';
  static const String formatSizeUnknown = 'size unknown';
  static const String formatApproximatePrefix = '~';
  static const String formatVideoSuffix = 'p';

  // View count / duration display
  static const String viewCountSuffix = ' views';
  static const String viewCountThousandSuffix = 'K';
  static const String viewCountMillionSuffix = 'M';
  static const String viewCountBillionSuffix = 'B';

  /// Playlist summary line, e.g. `Playlist: 12 videos`.
  static String playlistVideosLine(int count) {
    return '$playlistVideosPrefix $count $playlistVideosWord';
  }
}
