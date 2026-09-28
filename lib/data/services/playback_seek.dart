/// Relative seek math for YouTube-style ±10s skip.
library;

/// Clamps [position] + [delta] to `[0, duration]` (or 0 if duration is unknown).
Duration playbackClampSeek(
  Duration position,
  Duration delta,
  Duration duration,
) {
  final Duration next = position + delta;
  if (next < Duration.zero) {
    return Duration.zero;
  }
  if (duration > Duration.zero && next > duration) {
    return duration;
  }
  return next;
}
