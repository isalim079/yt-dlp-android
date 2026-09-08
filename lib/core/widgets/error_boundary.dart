/// Catches uncaught Flutter framework errors and shows a recovery screen.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// Catches uncaught Flutter errors and shows a friendly error screen
/// instead of a red error screen.
class ErrorBoundary extends StatefulWidget {
  /// Creates a boundary around [child].
  const ErrorBoundary({super.key, required this.child});

  /// Normal app subtree.
  final Widget child;

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  FlutterExceptionHandler? _previousOnError;
  FlutterErrorDetails? _error;

  @override
  void initState() {
    super.initState();
    _previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _previousOnError?.call(details);

      // Ignore silent diagnostic messages and layout/rendering warnings
      if (details.silent) {
        return;
      }

      final String exceptionString = details.exception.toString();
      final bool isOverflow = exceptionString.contains('overflowed');
      final bool isLayoutError = details.library == 'rendering library';
      final bool isDiagnosticWarning = exceptionString.contains('invisible') ||
          exceptionString.contains('ListTile') ||
          exceptionString.contains('ink splashes');

      if (isOverflow || isLayoutError || isDiagnosticWarning) {
        AppLogger.w('Framework diagnostic warning (non-fatal): $exceptionString');
        return;
      }

      AppLogger.e('Uncaught Flutter error', details.exception, details.stack);

      // Defer state update until after the current build frame completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _error == null) {
          setState(() => _error = details);
        }
      });
    };
  }

  @override
  void dispose() {
    FlutterError.onError = _previousOnError;
    super.dispose();
  }

  void _retry() {
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorScreen(details: _error!, onRetry: _retry);
    }
    return widget.child;
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.details, required this.onRetry});
  final FlutterErrorDetails details;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.bug_report_rounded,
                  size: 64,
                  color: Color(0xFFB71C1C),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF212121),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'An unexpected error occurred.\nYou can retry or restart the app.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF757575)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => SystemNavigator.pop(),
                        child: const Text('Close app'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: const Color(0xFFC62828),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
