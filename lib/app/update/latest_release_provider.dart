import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/update/github_latest_release_fetcher.dart';
import 'package:planerz/app/update/preview_storage_latest_release_fetcher.dart';
import 'package:planerz/app/update/remote_release.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';

/// Latest remote release: GitHub (prod) or Firebase Storage `versions/*` (preview).
final latestReleaseProvider = FutureProvider<RemoteRelease?>((ref) async {
  final target = ref.watch(firebaseTargetProvider);
  if (target.isPreview) {
    return fetchPreviewLatestReleaseFromStorage();
  }
  return fetchLatestProdReleaseFromGitHub();
});
