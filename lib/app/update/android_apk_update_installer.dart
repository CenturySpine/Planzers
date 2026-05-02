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

String _apkCompletionMarkerPath(String apkPath) => '$apkPath.complete';

String _apkPartialPath(String apkPath) => '$apkPath.part';

Future<void> _deleteFileIfExists(File file) async {
  if (!await file.exists()) return;
  try {
    await file.delete();
  } catch (_) {}
}

Future<bool> _isCachedApkComplete(File outFile) async {
  if (!await outFile.exists()) return false;
  if (await outFile.length() == 0) return false;
  final completionMarker = File(_apkCompletionMarkerPath(outFile.path));
  return completionMarker.exists();
}

Future<void> _deleteStaleUpdateApks(
    Directory apkUpdatesDir, String keepBasename) async {
  if (!await apkUpdatesDir.exists()) return;
  await for (final entity in apkUpdatesDir.list()) {
    if (entity is! File) continue;
    final basename = p.basename(entity.path);
    final isMainApk = basename.endsWith('.apk');
    final isCompletionMarker = basename.endsWith('.apk.complete');
    final isPartialApk = basename.endsWith('.apk.part');
    if (!isMainApk && !isCompletionMarker && !isPartialApk) continue;
    if (basename == keepBasename ||
        basename == '$keepBasename.complete' ||
        basename == '$keepBasename.part') {
      continue;
    }
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

/// Returns the APK file in app cache, downloading first when missing or incomplete.
/// Returns `null` when the download fails.
///
/// Call only when `Platform.isAndroid`.
Future<File?> downloadUpdateApkToCache({
  required String apkDownloadUrl,
  required String releaseTag,
  bool Function()? isAndroidCheck,
  Future<Directory> Function()? apkUpdatesDirectoryProvider,
  http.Client Function()? httpClientFactory,
}) async {
  final checkIsAndroid = isAndroidCheck ?? () => Platform.isAndroid;
  if (!checkIsAndroid()) {
    throw StateError('downloadUpdateApkToCache is Android-only');
  }

  final sanitizedTag = sanitizeReleaseTagForApkFileName(releaseTag);
  if (sanitizedTag.isEmpty) {
    return null;
  }

  final basename = 'planerz_$sanitizedTag.apk';
  final resolveApkUpdatesDirectory =
      apkUpdatesDirectoryProvider ?? _apkUpdatesDirectory;
  final apkUpdatesDir = await resolveApkUpdatesDirectory();
  await _deleteStaleUpdateApks(apkUpdatesDir, basename);

  final outFile = File(p.join(apkUpdatesDir.path, basename));
  final completionMarker = File(_apkCompletionMarkerPath(outFile.path));
  final partialFile = File(_apkPartialPath(outFile.path));

  await _deleteFileIfExists(partialFile);
  final needsDownload = !await _isCachedApkComplete(outFile);

  if (!needsDownload) {
    return outFile;
  }

  await _deleteFileIfExists(outFile);
  await _deleteFileIfExists(completionMarker);

  final createHttpClient = httpClientFactory ?? () => http.Client();
  final client = createHttpClient();
  try {
    final uri = Uri.parse(apkDownloadUrl);
    final request = http.Request('GET', uri);
    final streamed =
        await client.send(request).timeout(const Duration(minutes: 15));
    if (streamed.statusCode != 200) {
      return null;
    }
    final sink = partialFile.openWrite();
    try {
      await streamed.stream.pipe(sink);
    } finally {
      await sink.close();
    }
    if (!await partialFile.exists() || await partialFile.length() == 0) {
      await _deleteFileIfExists(partialFile);
      return null;
    }
    final finalizedApk = await partialFile.rename(outFile.path);
    await completionMarker.writeAsString('complete', flush: true);
    return finalizedApk;
  } catch (_) {
    await _deleteFileIfExists(outFile);
    await _deleteFileIfExists(completionMarker);
    await _deleteFileIfExists(partialFile);
    return null;
  } finally {
    client.close();
  }
}

/// Deletes the cached APK and sidecar files for [releaseTag] from app cache.
Future<void> invalidateCachedUpdateApk({
  required String releaseTag,
  Future<Directory> Function()? apkUpdatesDirectoryProvider,
}) async {
  final sanitizedTag = sanitizeReleaseTagForApkFileName(releaseTag);
  if (sanitizedTag.isEmpty) {
    return;
  }

  final basename = 'planerz_$sanitizedTag.apk';
  final resolveApkUpdatesDirectory =
      apkUpdatesDirectoryProvider ?? _apkUpdatesDirectory;
  final apkUpdatesDir = await resolveApkUpdatesDirectory();
  final outFile = File(p.join(apkUpdatesDir.path, basename));
  final completionMarker = File(_apkCompletionMarkerPath(outFile.path));
  final partialFile = File(_apkPartialPath(outFile.path));

  await _deleteFileIfExists(outFile);
  await _deleteFileIfExists(completionMarker);
  await _deleteFileIfExists(partialFile);
}

/// Opens Android's package installer for [apkFile] via [OpenFilex] (plugin FileProvider).
///
/// Call only when `Platform.isAndroid`.
Future<AndroidApkInstallPromptOutcome> promptAndroidApkInstall(
    File apkFile) async {
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
