import 'dart:typed_data';

import 'wallet_local_store_stub.dart'
    if (dart.library.io) 'wallet_local_store_io.dart'
    if (dart.library.js_interop) 'wallet_local_store_web.dart' as impl;

/// App-private, on-device copies of wallet files (offline access). Nothing
/// is ever written to a user-visible folder. Keys: `uid/tripId/documentId`.
abstract class WalletLocalStore {
  Future<void> save(String key, Uint8List bytes);

  /// null when there is no (readable) copy.
  Future<Uint8List?> read(String key);

  Future<Set<String>> keysWithPrefix(String prefix);

  Future<void> remove(String key);

  Future<void> removePrefix(String prefix);

  /// Asks the platform not to evict the copies (web only; native files are
  /// not evicted).
  Future<void> requestPersistence();

  /// Loads the given app files once while online so they stay available
  /// offline (web only).
  Future<void> warmUp(List<String> urls);
}

final WalletLocalStore walletLocalStore = impl.createWalletLocalStore();

String walletLocalKey(String uid, String tripId, String documentId) =>
    '$uid/$tripId/$documentId';

String walletLocalTripPrefix(String uid, String tripId) => '$uid/$tripId/';

String walletLocalUserPrefix(String uid) => '$uid/';

/// Erases every offline copy on this device (e.g. at sign-out: the device
/// may be shared).
Future<void> clearWalletLocalStore() async {
  try {
    await walletLocalStore.removePrefix('');
  } catch (_) {}
}
