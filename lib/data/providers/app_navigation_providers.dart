/// Shared UI navigation state (e.g. bottom tab index).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-tab navigator with a back stack (0 Home, 1 Search, 2 Library, 3 Settings).
class TabIndexController extends Notifier<int> {
  final List<int> _history = <int>[];

  static const int _maxHistory = 24;

  @override
  int build() => 0;

  /// Selects [index], pushing the current tab onto the back stack.
  void goTo(int index) {
    if (index == state) {
      return;
    }
    _history.add(state);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
    state = index;
  }

  /// Pops the previous tab. Returns `false` when the stack is empty.
  bool goBack() {
    if (_history.isEmpty) {
      return false;
    }
    state = _history.removeLast();
    return true;
  }

  /// Whether a previous tab can be restored.
  bool get hasPrevious => _history.isNotEmpty;
}

/// Selected index for the root bottom navigation.
final NotifierProvider<TabIndexController, int> tabIndexProvider =
    NotifierProvider<TabIndexController, int>(TabIndexController.new);
