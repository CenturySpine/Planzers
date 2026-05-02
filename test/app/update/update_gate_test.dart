import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/app/app_version_provider.dart';
import 'package:planerz/app/update/android_apk_update_installer.dart';
import 'package:planerz/app/update/latest_release_provider.dart';
import 'package:planerz/app/update/remote_release.dart';
import 'package:planerz/app/update/update_gate.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'UpdateGate invalidates cached APK and retries download after installer failure',
    (tester) async {
      final downloadedApk = File('/tmp/fake-update.apk');
      int downloadCallCount = 0;
      int invalidateCallCount = 0;

      Future<File?> fakeDownload({
        required String apkDownloadUrl,
        required String releaseTag,
      }) async {
        downloadCallCount += 1;
        return downloadedApk;
      }

      Future<void> fakeInvalidate({required String releaseTag}) async {
        invalidateCallCount += 1;
      }

      Future<AndroidApkInstallPromptOutcome> fakePrompt(File apkFile) async {
        return AndroidApkInstallPromptOutcome.installerIntentFailed;
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            latestReleaseProvider.overrideWith(
              (ref) async => const RemoteRelease(
                tag: 'v2.0.0',
                apkDownloadUrl: 'https://example.com/planerz.apk',
              ),
            ),
            appVersionProvider.overrideWith((ref) async => 'v1.0.0'),
            firebaseTargetProvider.overrideWithValue(FirebaseTarget.preview),
          ],
          child: MaterialApp(
            locale: const Locale('fr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: UpdateGate(
              isAndroidCheck: () => true,
              downloadUpdateApkToCacheFn: fakeDownload,
              promptAndroidApkInstallFn: fakePrompt,
              invalidateCachedUpdateApkFn: fakeInvalidate,
              child: const Scaffold(body: Text('child')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(downloadCallCount, 1);
      expect(invalidateCallCount, 1);
      expect(find.text('Réessayer'), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(downloadCallCount, 2);
      expect(invalidateCallCount, 2);
    },
  );
}
