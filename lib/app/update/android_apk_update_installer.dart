import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Outcome of attempting to open the system APK installer.
enum AndroidApkInstallPromptOutcome {
  installerPromptShown,
  installerIntentFailed,
}

/// Normalizes [releaseTag] for use in a local file basename (Windows/Android reserved chars).
String sanitizeReleaseTagForApkFileName(String releaseTag) {
  return releaseTag.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

Future<void> _deleteStaleUpdateApks(Directory apkUpdatesDir, String keepBasename) async {
  if (!await apkUpdatesDir.exists()) return;
  await for (final entity in apkUpdatesDir.list()) {
    if (entity is! File) continue;
    final basename = p.basename(entity.path);
    if (!basename.endsWith('.apk')) continue;
    if (basename == keepBasename) continue;
    try {
      await entity.delete();
    } catch (_) {}
  }
}

Future<Directory> _apkUpdatesDirectory() async {
  final cacheRoot = await getTemporaryDirectory();
  final apkUpdatesDir = Directory(p.join(cacheRoot.path, 'apk_updates'));
  await apkUpdatesDir.create(recursive: true);
  return apkUpdatesDir;
}

/// Returns the APK file in app cache, downloading first when missing or empty.
/// Returns `null` when the download fails.
///
/// Call only when `Platform.isAndroid`.
Future<File?> downloadUpdateApkToCache({
  required String apkDownloadUrl,
  required String releaseTag,
}) async {
  if (!Platform.isAndroid) {
    throw StateError('downloadUpdateApkToCache is Android-only');
  }

  final sanitizedTag = sanitizeReleaseTagForApkFileName(releaseTag);
  if (sanitizedTag.isEmpty) {
    return null;
  }

  final basename = 'planerz_$sanitizedTag.apk';
  final apkUpdatesDir = await _apkUpdatesDirectory();
  await _deleteStaleUpdateApks(apkUpdatesDir, basename);

  final outFile = File(p.join(apkUpdatesDir.path, basename));

  final needsDownload =
      !await outFile.exists() || await outFile.length() == 0;

  if (!needsDownload) {
    return outFile;
  }

  final client = http.Client();
  try {
    final uri = Uri.parse(apkDownloadUrl);
    final request = http.Request('GET', uri);
    final streamed =
        await client.send(request).timeout(const Duration(minutes: 15));
    if (streamed.statusCode != 200) {
      return null;
    }
    final sink = outFile.openWrite();
    try {
      await streamed.stream.pipe(sink);
    } finally {
      await sink.close();
    }
    return outFile;
  } catch (_) {
    if (await outFile.exists()) {
      try {
        await outFile.delete();
      } catch (_) {}
    }
    return null;
  } finally {
    client.close();
  }
}

/// Opens Android's package installer for [apkFile] via [OpenFilex] (plugin FileProvider).
///
/// Call only when `Platform.isAndroid`.
Future<AndroidApkInstallPromptOutcome> promptAndroidApkInstall(File apkFile) async {
  if (!Platform.isAndroid) {
    throw StateError('promptAndroidApkInstall is Android-only');
  }

  final openOutcome = await OpenFilex.open(
    apkFile.path,
    type: 'application/vnd.android.package-archive',
  );
  if (openOutcome.type != ResultType.done) {
    return AndroidApkInstallPromptOutcome.installerIntentFailed;
  }
  return AndroidApkInstallPromptOutcome.installerPromptShown;
}
