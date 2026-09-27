import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:planerz/core/platform/page_reload.dart';

/// Keeps a disk copy of Firestore data so the app can be used offline.
///
/// Native platforms already persist by default; on web the SDK only keeps an
/// in-memory cache unless IndexedDB persistence is requested explicitly. The
/// multi-tab manager lets several open tabs share the same cache.
///
/// Must run before the first Firestore read/write: settings are ignored once
/// the instance is in use (e.g. after a hot restart), hence the guard.
void configureFirestoreOfflineCache() {
  if (!kIsWeb) return;
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      webPersistentTabManager: WebPersistentMultipleTabManager(),
    );
  } catch (error) {
    debugPrint('Firestore offline cache not configured: $error');
  }
}

/// Wipes the offline copy of the signed-out user's data (the browser may be
/// shared), then reloads the page: a terminated Firestore instance cannot be
/// reused on web, the reload starts a fresh one.
///
/// Call after signing out. Native keeps its per-install cache, as before.
Future<void> clearFirestoreOfflineCacheAndReload() async {
  if (!kIsWeb) return;
  try {
    await FirebaseFirestore.instance.terminate();
    await FirebaseFirestore.instance.clearPersistence();
  } catch (error) {
    debugPrint('Firestore offline cache not cleared: $error');
  }
  reloadPage();
}
