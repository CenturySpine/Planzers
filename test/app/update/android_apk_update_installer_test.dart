import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/app/update/android_apk_update_installer.dart';

void main() {
  test(
    'downloadUpdateApkToCache redownloads when cached APK has no completion marker',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'apk_update_installer_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final payload = List<int>.generate(4096, (index) => index % 251);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.binary;
        request.response.headers.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });

      final apkUpdatesDir = Directory('${tempRoot.path}/apk_updates')
        ..createSync(recursive: true);
      final releaseTag = 'v1.2.3';
      final cachedApk = File('${apkUpdatesDir.path}/planerz_$releaseTag.apk');
      await cachedApk.writeAsString(
        'partial-corrupted-content',
        flush: true,
      );
      final beforeLength = await cachedApk.length();

      final downloaded = await downloadUpdateApkToCache(
        apkDownloadUrl:
            'http://${server.address.host}:${server.port}/planerz.apk',
        releaseTag: releaseTag,
        isAndroidCheck: () => true,
        apkUpdatesDirectoryProvider: () async => apkUpdatesDir,
      );

      expect(downloaded, isNotNull);
      expect(downloaded!.path, cachedApk.path);
      expect(await downloaded.length(), payload.length);
      expect(await downloaded.length(), isNot(beforeLength));

      final bytes = await downloaded.readAsBytes();
      expect(bytes, payload);
      final completionMarker = File('${cachedApk.path}.complete');
      expect(await completionMarker.exists(), isTrue);
    },
  );

  test('invalidateCachedUpdateApk removes apk and sidecar files', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'apk_update_invalidate_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final apkUpdatesDir = Directory('${tempRoot.path}/apk_updates')
      ..createSync(recursive: true);
    const releaseTag = 'v2.0.0';
    final apkPath = '${apkUpdatesDir.path}/planerz_$releaseTag.apk';
    final apkFile = File(apkPath);
    final completionMarker = File('$apkPath.complete');
    final partialFile = File('$apkPath.part');

    await apkFile.writeAsBytes([1, 2, 3], flush: true);
    await completionMarker.writeAsString('complete', flush: true);
    await partialFile.writeAsBytes([9], flush: true);

    await invalidateCachedUpdateApk(
      releaseTag: releaseTag,
      apkUpdatesDirectoryProvider: () async => apkUpdatesDir,
    );

    expect(await apkFile.exists(), isFalse);
    expect(await completionMarker.exists(), isFalse);
    expect(await partialFile.exists(), isFalse);
  });

  group('sanitizeReleaseTagForApkFileName', () {
    test('preserves safe semver-like tags', () {
      expect(
          sanitizeReleaseTagForApkFileName('v0.2.0-beta1+6'), 'v0.2.0-beta1+6');
    });

    test('replaces path-reserved characters', () {
      expect(sanitizeReleaseTagForApkFileName(r'a\b:c*d?"<>|'), 'a_b_c_d_____');
    });

    test('trims whitespace', () {
      expect(sanitizeReleaseTagForApkFileName('  v1  '), 'v1');
    });
  });
}
