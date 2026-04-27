/// Structured logging facade wrapping `package:logger`.
library;

import 'package:logger/logger.dart';

/// Static logging helpers used across services and startup.
abstract final class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
    ),
  );

  /// Logs a debug-level message.
  static void d(String message) => _logger.d(message);

  /// Logs an informational message.
  static void i(String message) => _logger.i(message);

  /// Logs a warning.
  static void w(String message) => _logger.w(message);

  /// Logs an error with optional cause and stack trace.
  static void e(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.e(message, error: error, stackTrace: stackTrace);
}
