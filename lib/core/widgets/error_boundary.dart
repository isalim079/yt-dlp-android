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
      AppLogger.e('Uncaught Flutter error', details.exception, details.stack);
      final String exceptionString = details.exception.toString();
      final bool isOverflow = exceptionString.contains('overflowed');
      final bool isLayoutError = details.library == 'rendering library';

      if (isOverflow || isLayoutError) {
        AppLogger.w('Layout warning (non-fatal): $exceptionString');
        return;
      }

      if (mounted) {
        setState(() => _error = details);
      }
    };
  }

  @override
  void dispose() {
    FlutterError.onError = _previousOnError;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorScreen(_error!);
    }
    return widget.child;
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen(this.details);
  final FlutterErrorDetails details;

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
                  'An unexpected error occurred.\nPlease restart the app.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF757575)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('Close app'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
