/// Bundled yt-dlp extraction and lifecycle (IO implementation on native).
library;

export 'binary_manager_stub.dart' if (dart.library.io) 'binary_manager_io.dart';
