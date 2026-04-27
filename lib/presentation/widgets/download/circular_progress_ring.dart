library;

import 'package:flutter/material.dart';

/// Thumbnail overlay ring progress for active downloads.
class CircularProgressRing extends StatelessWidget {
  const CircularProgressRing({super.key, required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final double clamped = percent.clamp(0.0, 1.0);
    final bool indeterminate = clamped <= 0;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CircularProgressIndicator(
            value: 1,
            strokeWidth: 3,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          CircularProgressIndicator(
            value: indeterminate ? null : clamped,
            strokeWidth: 3,
            strokeCap: StrokeCap.round,
            color: Colors.white,
          ),
          Text(
            indeterminate ? '...' : '${(clamped * 100).toInt()}%',
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
