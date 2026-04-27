/// Resolves how to spawn the bundled yt-dlp binary on each OS.
library;

import 'dart:io';

/// Executable + argv for [Process.run] / [Process.start].
///
/// On Android 10+, direct [exec] of an ELF in app-private storage often fails
/// with `Permission denied` even after `chmod`. The dynamic linker is invoked
/// instead; it loads the real program when given its absolute path as the
/// first argument after the linker (same approach as Termux).
final class YtdlpLaunchCommand {
  /// Creates a resolved launch command.
  const YtdlpLaunchCommand({
    required this.executable,
    required this.arguments,
  });

  /// Process image to execute (yt-dlp path, or `/system/bin/linker64` on Android).
  final String executable;

  /// Full argument vector after [executable] (includes yt-dlp path when using linker).
  final List<String> arguments;

  /// [ytdlpArgs] are yt-dlp flags only (e.g. `--version`, `-J`), not the binary path.
  static YtdlpLaunchCommand from(String binaryPath, List<String> ytdlpArgs) {
    if (Platform.isAndroid) {
      return YtdlpLaunchCommand(
        executable: _androidDynamicLinker(),
        arguments: <String>[binaryPath, ...ytdlpArgs],
      );
    }
    return YtdlpLaunchCommand(
      executable: binaryPath,
      arguments: ytdlpArgs,
    );
  }

  static String _androidDynamicLinker() {
    if (File('/system/bin/linker64').existsSync()) {
      return '/system/bin/linker64';
    }
    return '/system/bin/linker';
  }
}
