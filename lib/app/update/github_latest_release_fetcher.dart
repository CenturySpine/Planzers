import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:planerz/app/update/remote_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOwner = 'CenturySpine';
const _kRepo = 'Planzers';
const _kCacheDurationMs = 60 * 60 * 1000; // 1 hour
const _kPrefTs = '_update_check_ts';
const _kPrefTag = '_update_check_tag';
const _kPrefApk = '_update_check_apk';

/// Prod-only: latest GitHub release with APK asset. Uses SharedPreferences cache;
/// does not call Firebase Storage.
Future<RemoteRelease?> fetchLatestProdReleaseFromGitHub() async {
  final prefs = await SharedPreferences.getInstance();
  final cachedRelease = _loadCache(prefs);
  if (cachedRelease != null) return cachedRelease;

  try {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$_kOwner/$_kRepo/releases/latest',
    );
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/vnd.github.v3+json'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = body['tag_name'] as String?;
    final assets = body['assets'] as List<dynamic>?;

    Map<String, dynamic>? apkAsset;
    for (final raw in assets ?? const <dynamic>[]) {
      final a = raw as Map<String, dynamic>;
      if ((a['name'] as String? ?? '').endsWith('.apk')) {
        apkAsset = a;
        break;
      }
    }
    final apkUrl = apkAsset?['browser_download_url'] as String?;

    if (tag == null || apkUrl == null) return null;

    final release = RemoteRelease(tag: tag, apkDownloadUrl: apkUrl);
    _saveCache(prefs, release);
    return release;
  } catch (_) {
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
