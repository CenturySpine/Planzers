import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:planerz/app/update/remote_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPreviewVersionJsonPath = 'versions/version.json';
const _kPreviewApkPath = 'versions/planerz.preview.apk';
const _kPreviewBucketHost = 'planerz-preview.firebasestorage.app';

const _kCacheDurationMs = 60 * 60 * 1000; // 1 hour
const _kPrefTs = '_update_check_ts_preview';
const _kPrefTag = '_update_check_tag_preview';
const _kPrefApk = '_update_check_apk_preview';

/// Preview-only: reads [versions/version.json] and resolves APK URL via Storage.
/// Call only when the app runs against the preview Firebase project.
Future<RemoteRelease?> fetchPreviewLatestReleaseFromStorage() async {
  final prefs = await SharedPreferences.getInstance();
  final cachedRelease = _loadCache(prefs);
  if (cachedRelease != null) return cachedRelease;

  try {
    final rawBucket = (Firebase.app().options.storageBucket ?? '').trim();
    final effectiveBucket =
        rawBucket.isEmpty ? _kPreviewBucketHost : rawBucket;
    final bucketUri = effectiveBucket.startsWith('gs://')
        ? effectiveBucket
        : 'gs://$effectiveBucket';
    final storage = FirebaseStorage.instanceFor(bucket: bucketUri);

    final versionRef = storage.ref(_kPreviewVersionJsonPath);
    final bytes =
        await versionRef.getData(32768).timeout(const Duration(seconds: 15));
    if (bytes == null || bytes.isEmpty) return null;
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final tag = decoded['tag'] as String?;
    if (tag == null || tag.isEmpty) return null;

    final apkRef = storage.ref(_kPreviewApkPath);
    final apkUrl =
        await apkRef.getDownloadURL().timeout(const Duration(seconds: 15));

    final release = RemoteRelease(tag: tag, apkDownloadUrl: apkUrl);
    _saveCache(prefs, release);
    return release;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('fetchPreviewLatestReleaseFromStorage failed: $e\n$st');
    }
    return null;
  }
}

RemoteRelease? _loadCache(SharedPreferences prefs) {
  final ts = prefs.getInt(_kPrefTs);
  if (ts == null) return null;
  final age = DateTime.now().millisecondsSinceEpoch - ts;
  if (age > _kCacheDurationMs) return null;

  final tag = prefs.getString(_kPrefTag);
  final apk = prefs.getString(_kPrefApk);
  if (tag == null || apk == null) return null;
  return RemoteRelease(tag: tag, apkDownloadUrl: apk);
}

void _saveCache(SharedPreferences prefs, RemoteRelease release) {
  prefs.setInt(_kPrefTs, DateTime.now().millisecondsSinceEpoch);
  prefs.setString(_kPrefTag, release.tag);
  prefs.setString(_kPrefApk, release.apkDownloadUrl);
}
