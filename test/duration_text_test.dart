import 'package:flutter_music/core/format/duration_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatTrackDuration pads seconds and keeps unknown as placeholder', () {
    expect(formatTrackDuration(0), '0:00');
    expect(formatTrackDuration(5_000), '0:05');
    expect(formatTrackDuration(65_000), '1:05');
    expect(formatTrackDuration(3_725_000), '62:05');
    expect(formatTrackDuration(null), '--:--');
  });

  test('formatPlaybackDuration does not truncate minutes at an hour', () {
    expect(formatPlaybackDuration(Duration.zero), '0:00');
    expect(
      formatPlaybackDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '62:03',
    );
  });
}
