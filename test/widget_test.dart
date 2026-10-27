import 'package:flutter_test/flutter_test.dart';
import 'package:wavvy/utils/player.utils.dart';

void main() {
  group('PlayerUtils', () {
    test('formatDuration handles minutes and hours', () {
      expect(PlayerUtils.formatDuration(const Duration(seconds: 65)), '1:05');
      expect(
        PlayerUtils.formatDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '1:02:03',
      );
    });

    test('formatBytes scales units', () {
      expect(PlayerUtils.formatBytes(0, 2), '0 B');
      expect(PlayerUtils.formatBytes(512, 2), '512 B');
      expect(PlayerUtils.formatBytes(2048, 2), '2.00 KB');
      expect(PlayerUtils.formatBytes(5 * 1024 * 1024, 2), '5.00 MB');
    });
  });
}
