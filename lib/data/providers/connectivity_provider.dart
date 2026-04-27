/// Reactive connectivity for banners and guards.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/connectivity_util.dart';

/// Reactive stream of online (`true`) / offline (`false`) state.
final StreamProvider<bool> connectivityProvider = StreamProvider<bool>((Ref ref) async* {
  yield await ConnectivityUtil.hasConnection();
  yield* ConnectivityUtil.connectivityStream;
});

/// One-shot connectivity read (e.g. before a single action).
final FutureProvider<bool> isConnectedProvider =
    FutureProvider<bool>((Ref ref) async {
  return ConnectivityUtil.hasConnection();
});
