import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/services/playback_seek.dart';

void main() {
  test('clamps relative seek to zero and duration', () {
    expect(
      playbackClampSeek(
        const Duration(seconds: 4),
        const Duration(seconds: -10),
        const Duration(seconds: 60),
      ),
      Duration.zero,
    );
    expect(
      playbackClampSeek(
        const Duration(seconds: 55),
        const Duration(seconds: 10),
        const Duration(seconds: 60),
      ),
      const Duration(seconds: 60),
    );
    expect(
      playbackClampSeek(
        const Duration(seconds: 20),
        const Duration(seconds: 10),
        const Duration(seconds: 60),
      ),
      const Duration(seconds: 30),
    );
  });
}
