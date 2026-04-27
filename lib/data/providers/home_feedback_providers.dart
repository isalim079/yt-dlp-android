/// Ephemeral home UI messages (e.g. connectivity failures).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Last search-blocking error message for snackbars; clear after display.
final StateProvider<String?> homeSearchErrorProvider =
    StateProvider<String?>((Ref ref) => null);

/// Incremented when a share intent applies a URL (for one-shot snackbars).
final StateProvider<int> shareIntentCounterProvider =
    StateProvider<int>((Ref ref) => 0);
