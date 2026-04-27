/// Spawns and supervises yt-dlp processes (list formats, download, metadata).
library;

export 'ytdlp_service_stub.dart' if (dart.library.io) 'ytdlp_service_io.dart';
