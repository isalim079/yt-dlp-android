/// Web / IO-less stub for folder opening.
library;

import 'package:flutter/material.dart';

/// No-op on platforms without `dart:io`.
Future<void> openSystemFolder(
  String path, {
  BuildContext? snackbarContext,
}) async {}
