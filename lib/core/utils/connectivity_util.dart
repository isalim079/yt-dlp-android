/// Internet connectivity checks for network-dependent flows.
library;

import 'package:connectivity_plus/connectivity_plus.dart';

/// Utility to check internet connectivity before network operations.
abstract final class ConnectivityUtil {
  /// Returns true when at least one non-none connectivity result is present.
  static Future<bool> hasConnection() async {
    final List<ConnectivityResult> result =
        await Connectivity().checkConnectivity();
    return result.any((ConnectivityResult r) => r != ConnectivityResult.none);
  }

  /// Emits `true` when the device likely has internet, `false` when offline.
  static Stream<bool> get connectivityStream {
    return Connectivity().onConnectivityChanged.map(
      (List<ConnectivityResult> results) => results.any(
        (ConnectivityResult r) => r != ConnectivityResult.none,
      ),
    );
  }
}
