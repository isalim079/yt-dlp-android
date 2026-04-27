/// Conditional export for opening a folder on the host OS.
library;

export 'open_folder_stub.dart' if (dart.library.io) 'open_folder_io.dart';
