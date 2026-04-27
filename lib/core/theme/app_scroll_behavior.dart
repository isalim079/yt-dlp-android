/// Scroll behavior that allows mouse / trackpad dragging on desktop.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Enables touch, mouse, and trackpad drag scrolling.
class AppScrollBehavior extends MaterialScrollBehavior {
  /// Creates scroll behavior with expanded pointer kinds.
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
