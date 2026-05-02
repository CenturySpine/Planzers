import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/app/update/android_apk_update_installer.dart';

void main() {
  group('sanitizeReleaseTagForApkFileName', () {
    test('preserves safe semver-like tags', () {
      expect(sanitizeReleaseTagForApkFileName('v0.2.0-beta1+6'), 'v0.2.0-beta1+6');
    });

    test('replaces path-reserved characters', () {
      expect(sanitizeReleaseTagForApkFileName(r'a\b:c*d?"<>|'), 'a_b_c_d_____');
    });

    test('trims whitespace', () {
      expect(sanitizeReleaseTagForApkFileName('  v1  '), 'v1');
    });
  });
}
