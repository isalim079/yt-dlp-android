/// Shared UI navigation state (e.g. bottom tab index).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected index for the root bottom navigation (0 Home, 1 Downloads, 2 Settings).
final StateProvider<int> tabIndexProvider = StateProvider<int>((Ref ref) => 0);
