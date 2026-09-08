/// Segmented and modern quality picker for choosing a [VideoFormat] before download.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../data/models/video_format.dart';
import '../../../data/providers/ytdlp_providers.dart';
import '../common/app_dropdown.dart';

/// Segmented quality selector separating Video and Audio formats with quick chips and details.
class FormatSelector extends ConsumerStatefulWidget {
  /// Creates a selector for the given [formats] list.
  const FormatSelector({super.key, required this.formats});

  /// Non-empty formats returned by yt-dlp.
  final List<VideoFormat> formats;

  @override
  ConsumerState<FormatSelector> createState() => _FormatSelectorState();
}

class _FormatSelectorState extends ConsumerState<FormatSelector> {
  // 0 = Video, 1 = Audio Only
  int _selectedTab = 0;
  bool _showAllFormats = false;

  @override
  void initState() {
    super.initState();
    final VideoFormat? current = ref.read(selectedFormatProvider);
    if (current != null && current.isAudioOnly) {
      _selectedTab = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final VideoFormat? selected = ref.watch(selectedFormatProvider);

    final List<VideoFormat> videoFormats = widget.formats
        .where((VideoFormat f) => !f.isAudioOnly)
        .toList(growable: false);

    final List<VideoFormat> audioFormats = widget.formats
        .where((VideoFormat f) => f.isAudioOnly)
        .toList(growable: false);

    // If active tab has no formats, fall back to the other
    final bool hasVideo = videoFormats.isNotEmpty;
    final bool hasAudio = audioFormats.isNotEmpty;
    final int activeTab = (_selectedTab == 0 && !hasVideo && hasAudio)
        ? 1
        : (_selectedTab == 1 && !hasAudio && hasVideo)
            ? 0
            : _selectedTab;

    final List<VideoFormat> activeList = activeTab == 0 ? videoFormats : audioFormats;

    // Resolve matched dropdown / selected format
    VideoFormat? activeSelected = selected;
    if (activeSelected != null) {
      final int idx = widget.formats.indexWhere(
        (VideoFormat f) => f.formatId == activeSelected!.formatId,
      );
      activeSelected = idx >= 0 ? widget.formats[idx] : null;
    }

    // Top representative formats for quick chips (up to 4 distinct qualities)
    final List<VideoFormat> quickChips = _extractQuickChips(activeList);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Segmented Tab Switcher (Video vs Audio Only)
        Container(
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _TabButton(
                  icon: Icons.videocam_rounded,
                  label: AppStrings.videoTab,
                  count: videoFormats.length,
                  isSelected: activeTab == 0,
                  color: c.primary,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedTab = 0);
                    if (videoFormats.isNotEmpty && (selected == null || selected.isAudioOnly)) {
                      ref.read(selectedFormatProvider.notifier).state = videoFormats.first;
                    }
                  },
                ),
              ),
              Expanded(
                child: _TabButton(
                  icon: Icons.audiotrack_rounded,
                  label: AppStrings.audioTab,
                  count: audioFormats.length,
                  isSelected: activeTab == 1,
                  color: c.secondary,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedTab = 1);
                    if (audioFormats.isNotEmpty && (selected == null || !selected.isAudioOnly)) {
                      ref.read(selectedFormatProvider.notifier).state = audioFormats.first;
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.spaceMd),

        // Quick Quality Chips Grid
        if (quickChips.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: AppDimensions.spaceSm,
            runSpacing: AppDimensions.spaceSm,
            children: quickChips.map((VideoFormat f) {
              final bool isCurrent = activeSelected?.formatId == f.formatId;
              final Color accentColor = activeTab == 0 ? c.primary : c.secondary;
              final Color accentLight = activeTab == 0 ? c.primaryLight : c.secondary.withValues(alpha: 0.12);

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(selectedFormatProvider.notifier).state = f;
                },
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spaceMd,
                    vertical: AppDimensions.spaceSm,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrent ? accentLight : c.surface,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    border: Border.all(
                      color: isCurrent ? accentColor : c.border,
                      width: isCurrent ? 1.8 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (isCurrent) ...<Widget>[
                        Icon(Icons.check_circle_rounded, size: 16, color: accentColor),
                        const SizedBox(width: AppDimensions.spaceXs),
                      ],
                      Text(
                        f.displayLabel.isNotEmpty ? f.displayLabel : (f.resolution ?? 'Best'),
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isCurrent ? accentColor : c.textPrimary,
                        ),
                      ),
                      const SizedBox(width: AppDimensions.spaceXs),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isCurrent ? accentColor : c.textSecondary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          f.formattedFileSize != AppStrings.notAvailable
                              ? f.formattedFileSize
                              : f.extension.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isCurrent ? accentColor : c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
        ],

        // Toggle to show full list / advanced formats
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _showAllFormats = !_showAllFormats);
          },
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _showAllFormats
                      ? 'Hide full format list'
                      : 'More formats (${activeList.length} available)',
                  style: textTheme.bodySmall?.copyWith(
                    color: activeTab == 0 ? c.primary : c.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  _showAllFormats ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: activeTab == 0 ? c.primary : c.secondary,
                ),
              ],
            ),
          ),
        ),

        // Advanced Full Dropdown List
        if (_showAllFormats) ...<Widget>[
          const SizedBox(height: AppDimensions.spaceSm),
          AppDropdown<VideoFormat>(
            items: activeList,
            value: activeSelected,
            onChanged: (VideoFormat? next) {
              if (next != null) {
                HapticFeedback.selectionClick();
                ref.read(selectedFormatProvider.notifier).state = next;
              }
            },
            labelBuilder: (BuildContext ctx, VideoFormat f) {
              final TextStyle? mainStyle = Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: c.textPrimary,
                  );
              final String res = (f.resolution?.isNotEmpty ?? false)
                  ? f.resolution!
                  : AppStrings.notAvailable;
              final String ext = f.extension.isNotEmpty
                  ? f.extension.toUpperCase()
                  : AppStrings.notAvailable;
              final String label = '${f.displayLabel}${AppStrings.formatLabelSeparator}$res · $ext';

              return Row(
                children: <Widget>[
                  Icon(
                    f.isAudioOnly ? Icons.audiotrack_outlined : Icons.videocam_outlined,
                    color: f.isAudioOnly ? c.secondary : c.primary,
                    size: AppDimensions.iconMd,
                  ),
                  const SizedBox(width: AppDimensions.spaceSm),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: mainStyle,
                    ),
                  ),
                ],
              );
            },
          ),
        ],

        // Selected Format Active Summary Card
        if (activeSelected != null) ...<Widget>[
          const SizedBox(height: AppDimensions.spaceMd),
          Container(
            padding: const EdgeInsets.all(AppDimensions.paddingMd),
            decoration: BoxDecoration(
              color: (activeTab == 0 ? c.primary : c.secondary).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(
                color: (activeTab == 0 ? c.primary : c.secondary).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (activeTab == 0 ? c.primary : c.secondary).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    activeSelected.isAudioOnly ? Icons.audiotrack_rounded : Icons.videocam_rounded,
                    size: 20,
                    color: activeTab == 0 ? c.primary : c.secondary,
                  ),
                ),
                const SizedBox(width: AppDimensions.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '${activeSelected.displayLabel} (${activeSelected.extension.toUpperCase()})',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeSelected.formattedFileSize != AppStrings.notAvailable
                            ? 'Estimated size: ${activeSelected.formattedFileSize}'
                            : 'Dynamic stream size',
                        style: textTheme.bodySmall?.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.check_circle_rounded,
                  color: activeTab == 0 ? c.primary : c.secondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Extracts the most representative quality options for clean display.
  List<VideoFormat> _extractQuickChips(List<VideoFormat> list) {
    if (list.isEmpty) return <VideoFormat>[];
    final Set<String> seenResolutions = <String>{};
    final List<VideoFormat> result = <VideoFormat>[];

    for (final VideoFormat f in list) {
      final String key = f.resolution ?? f.displayLabel;
      if (!seenResolutions.contains(key)) {
        seenResolutions.add(key);
        result.add(f);
        if (result.length >= 4) break;
      }
    }
    return result;
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : c.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : c.textSecondary,
              ),
            ),
            if (count > 0) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withValues(alpha: 0.25) : c.border,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : c.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
