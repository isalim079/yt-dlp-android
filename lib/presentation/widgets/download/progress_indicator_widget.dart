/// Row combining percent text and [AppProgressBar] for a download.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../common/app_progress_bar.dart';

/// Shows numeric percent and a linear bar for one active transfer.
class ProgressIndicatorWidget extends StatelessWidget {
  /// Creates a labeled progress row.
  const ProgressIndicatorWidget({super.key, this.percent});

  /// `0`–`100`, or `null` while indeterminate.
  final double? percent;

  @override
  Widget build(BuildContext context) {
    // TODO: add speed/ETA line from [DownloadProgress].
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String label = percent == null
        ? AppStrings.loading
        : '${percent!.clamp(0, 100).toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(AppStrings.labelProgress, style: textTheme.labelLarge),
            const Spacer(),
            Text(label, style: textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: AppDimensions.spaceSm),
        AppProgressBar(value: (percent ?? 0).clamp(0, 100) / 100),
      ],
    );
  }
}
