/// Root Material shell with bottom navigation and IndexedStack tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_colors.dart';
import 'core/constants/app_dimensions.dart';
import 'core/constants/app_strings.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_ui_colors.dart';
import 'data/providers/app_navigation_providers.dart';
import 'data/providers/download_providers.dart';
import 'presentation/screens/download/download_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';

/// Root [MaterialApp] with permanent light mode.
class YtDownloaderApp extends ConsumerWidget {
  /// Creates the app root.
  const YtDownloaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStrings.appName,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      scrollBehavior: const AppScrollBehavior(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
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

class _MainShell extends ConsumerWidget {
  const _MainShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int tab = ref.watch(tabIndexProvider);
    final int activeCount = ref.watch(activeDownloadCountProvider);

    return Scaffold(
      
      body: IndexedStack(
        index: tab,
        sizing: StackFit.expand,
        children: const <Widget>[
          HomeScreen(),
          DownloadScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          boxShadow: <BoxShadow>[
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
                icon: tab == 0 ? Icons.home_rounded : Icons.home_outlined,
                label: AppStrings.navHome,
                isSelected: tab == 0,
                badge: 0,
                onTap: () => ref.read(tabIndexProvider.notifier).state = 0,
              ),
              _NavItem(
                icon: Icons.download_rounded,
                label: AppStrings.navDownloads,
                isSelected: tab == 1,
                badge: activeCount,
                onTap: () => ref.read(tabIndexProvider.notifier).state = 1,
              ),
              _NavItem(
                icon: tab == 2
                    ? Icons.settings_rounded
                    : Icons.settings_outlined,
                label: AppStrings.navSettings,
                isSelected: tab == 2,
                badge: 0,
                onTap: () => ref.read(tabIndexProvider.notifier).state = 2,
              ),
            ],
          ),
        ),
      ),
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
