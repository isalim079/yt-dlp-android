import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yt_downloader/core/theme/app_theme.dart';

class TestHelpers {
  static Widget wrapWithApp(
    Widget child, {
    List<Override> overrides = const <Override>[],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: child),
      ),
    );
  }
}
