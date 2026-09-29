/// Root Material shell with bottom navigation and IndexedStack tabs.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_colors.dart';
import 'core/constants/app_dimensions.dart';
import 'core/constants/app_strings.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_ui_colors.dart';
import 'data/models/app_settings.dart';
import 'data/providers/app_navigation_providers.dart';
import 'data/providers/browse_providers.dart';
import 'data/providers/download_providers.dart';
import 'data/providers/feed_providers.dart';
import 'data/providers/player_provider.dart';
import 'data/providers/settings_providers.dart';
import 'data/services/ytdlp_platform_channel.dart';
import 'presentation/player/mini_player.dart';
import 'presentation/player/watch_page.dart';
import 'presentation/screens/home/home_feed_screen.dart';
import 'presentation/screens/library/library_screen.dart';
import 'presentation/screens/search/search_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/shorts/shorts_feed_screen.dart';

/// Root [MaterialApp] supporting light and dark modes dynamically.
class YtDownloaderApp extends ConsumerWidget {
  /// Creates the app root.
  const YtDownloaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AppSettings> settingsAsync = ref.watch(settingsProvider);
    final ThemeMode themeMode = settingsAsync.maybeWhen(
      data: (AppSettings s) => switch (s.themeMode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      },
      orElse: () => ThemeMode.system,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStrings.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      scrollBehavior: const AppScrollBehavior(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(
            textScaler: MediaQuery.of(
              context,
            ).textScaler.clamp(minScaleFactor: 0.8, maxScaleFactor: 1.2),
          ),
          child: child!,
        );
      },
      home: const _MainShell(),
    );
  }
}

class _LazyIndexedStack extends StatefulWidget {
  const _LazyIndexedStack({
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late final List<bool> _activated = List.generate(
    widget.children.length,
    (i) => i == 0, // Home is always active
  );

  @override
  void didUpdateWidget(_LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      setState(() => _activated[widget.index] = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      sizing: StackFit.expand,
      children: List.generate(
        widget.children.length,
        (i) => _activated[i] ? widget.children[i] : const SizedBox.shrink(),
      ),
    );
  }
}

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell>
    with WidgetsBindingObserver {
  bool _handlingBack = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final AppSettings? settings = ref.read(settingsProvider).valueOrNull;
    final bool background = settings?.backgroundPlayback ?? true;
    if (!background &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive)) {
      ref.read(playerControllerProvider.notifier).rawPlayer?.pause();
    }
    if (state == AppLifecycleState.detached && Platform.isAndroid) {
      YtdlpPlatformChannel.setPlaybackService(active: false);
    }
  }

  Future<void> _onSystemBack() async {
    if (_handlingBack) {
      return;
    }
    _handlingBack = true;
    try {
      final PlayerUiState player = ref.read(playerControllerProvider);
      if (player.expanded) {
        ref.read(playerControllerProvider.notifier).collapse();
        return;
      }

      final int tab = ref.read(tabIndexProvider);
      final String query = ref.read(searchQueryProvider);
      if (tab == AppTabs.search && query.isNotEmpty) {
        ref.read(searchQueryProvider.notifier).state = '';
        return;
      }

      if (ref.read(tabIndexProvider.notifier).goBack()) {
        return;
      }

      if (!mounted) {
        return;
      }
      final bool? leave = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Text(AppStrings.exitAppTitle),
            content: const Text(AppStrings.exitAppBody),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(AppStrings.buttonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(AppStrings.exitAppConfirm),
              ),
            ],
          );
        },
      );
      if (leave == true) {
        await SystemNavigator.pop();
      }
    } finally {
      _handlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int tab = ref.watch(tabIndexProvider);
    final int activeCount = ref.watch(activeDownloadCountProvider);
    final PlayerUiState playerState = ref.watch(playerControllerProvider);
    final AppUiColors c = AppColors.of(context);
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isWideScreen = screenWidth >= 600;
    final bool expanded = playerState.expanded;

    final Widget tabContent = _LazyIndexedStack(
      index: tab,
      children: const <Widget>[
        HomeFeedScreen(),
        ShortsFeedScreen(),
        SearchScreen(),
        LibraryScreen(),
        SettingsScreen(),
      ],
    );

    final bool showMini =
        !expanded && !playerState.shortsMode && tab != AppTabs.shorts;

    final Widget stacked = Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            Expanded(child: tabContent),
            if (showMini) const MiniPlayerBar(),
          ],
        ),
        if (expanded && !playerState.shortsMode) const WatchPage(),
      ],
    );

    final Widget shell = isWideScreen
        ? Scaffold(
            backgroundColor: c.background,
            body: Row(
              children: <Widget>[
                if (!expanded)
                  NavigationRail(
                    backgroundColor: c.surface,
                    selectedIndex: tab,
                    onDestinationSelected: (int idx) {
                      ref.read(tabIndexProvider.notifier).goTo(idx);
                    },
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDimensions.spaceMd,
                      ),
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: c.primary,
                        size: AppDimensions.iconLg,
                      ),
                    ),
                    destinations: <NavigationRailDestination>[
                      NavigationRailDestination(
                        icon: const Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded, color: c.primary),
                        label: const Text(AppStrings.navHome),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.video_library_outlined),
                        selectedIcon: Icon(
                          Icons.smart_display_rounded,
                          color: c.primary,
                        ),
                        label: const Text(AppStrings.navShorts),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.search_outlined),
                        selectedIcon:
                            Icon(Icons.search_rounded, color: c.primary),
                        label: const Text(AppStrings.navSearch),
                      ),
                      NavigationRailDestination(
                        icon: Badge(
                          isLabelVisible: activeCount > 0,
                          label: Text('$activeCount'),
                          backgroundColor: c.primary,
                          child: const Icon(Icons.folder_outlined),
                        ),
                        selectedIcon: Badge(
                          isLabelVisible: activeCount > 0,
                          label: Text('$activeCount'),
                          backgroundColor: c.primary,
                          child: Icon(
                            Icons.folder_rounded,
                            color: c.primary,
                          ),
                        ),
                        label: const Text(AppStrings.navLibrary),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.settings_outlined),
                        selectedIcon:
                            Icon(Icons.settings_rounded, color: c.primary),
                        label: const Text(AppStrings.navSettings),
                      ),
                    ],
                  ),
                if (!expanded)
                  VerticalDivider(width: 1, thickness: 1, color: c.border),
                Expanded(child: stacked),
              ],
            ),
          )
        : Scaffold(
            body: stacked,
            bottomNavigationBar: expanded
                ? null
                : Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(top: BorderSide(color: c.border, width: 1)),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 20,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: <Widget>[
                          _NavItem(
                            icon: tab == AppTabs.home
                                ? Icons.home_rounded
                                : Icons.home_outlined,
                            label: AppStrings.navHome,
                            isSelected: tab == AppTabs.home,
                            badge: 0,
                            onTap: () => ref
                                .read(tabIndexProvider.notifier)
                                .goTo(AppTabs.home),
                          ),
                          _NavItem(
                            icon: tab == AppTabs.shorts
                                ? Icons.smart_display_rounded
                                : Icons.smart_display_outlined,
                            label: AppStrings.navShorts,
                            isSelected: tab == AppTabs.shorts,
                            badge: 0,
                            onTap: () => ref
                                .read(tabIndexProvider.notifier)
                                .goTo(AppTabs.shorts),
                          ),
                          _NavItem(
                            icon: tab == AppTabs.search
                                ? Icons.search_rounded
                                : Icons.search_outlined,
                            label: AppStrings.navSearch,
                            isSelected: tab == AppTabs.search,
                            badge: 0,
                            onTap: () => ref
                                .read(tabIndexProvider.notifier)
                                .goTo(AppTabs.search),
                          ),
                          _NavItem(
                            icon: tab == AppTabs.library
                                ? Icons.folder_rounded
                                : Icons.folder_outlined,
                            label: AppStrings.navLibrary,
                            isSelected: tab == AppTabs.library,
                            badge: activeCount,
                            onTap: () => ref
                                .read(tabIndexProvider.notifier)
                                .goTo(AppTabs.library),
                          ),
                          _NavItem(
                            icon: tab == AppTabs.settings
                                ? Icons.settings_rounded
                                : Icons.settings_outlined,
                            label: AppStrings.navSettings,
                            isSelected: tab == AppTabs.settings,
                            badge: 0,
                            onTap: () => ref
                                .read(tabIndexProvider.notifier)
                                .goTo(AppTabs.settings),
                          ),
                        ],
                      ),
                    ),
                  ),
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        unawaited(_onSystemBack());
      },
      child: shell,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimensions.spaceSm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: isSelected
                        ? const EdgeInsets.symmetric(
                            horizontal: AppDimensions.spaceLg,
                            vertical: AppDimensions.spaceXs,
                          )
                        : EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: isSelected ? c.primaryLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        AppDimensions.chipRadius,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: isSelected ? c.primary : c.textSecondary,
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: c.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppDimensions.spaceXs),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? c.primary : c.textSecondary,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
