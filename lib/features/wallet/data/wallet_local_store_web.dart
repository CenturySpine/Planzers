import 'dart:js_interop';
import 'dart:typed_data';

import 'package:planerz/features/wallet/data/wallet_local_store.dart';

// Helpers defined in web/planerz_wallet_store.js (IndexedDB).
@JS('planerzWalletStore.save')
external JSPromise<JSAny?> _save(String key, JSUint8Array bytes);

@JS('planerzWalletStore.read')
external JSPromise<JSUint8Array?> _read(String key);

@JS('planerzWalletStore.keys')
external JSPromise<JSArray<JSString>> _keys(String prefix);

@JS('planerzWalletStore.remove')
external JSPromise<JSAny?> _remove(String key);

@JS('planerzWalletStore.removePrefix')
external JSPromise<JSAny?> _removePrefix(String prefix);

@JS('planerzWalletStore.requestPersistence')
external JSPromise<JSAny?> _requestPersistence();

@JS('planerzWalletStore.warmUp')
external JSPromise<JSAny?> _warmUp(JSArray<JSString> urls);

WalletLocalStore createWalletLocalStore() => _IndexedDbWalletLocalStore();

class _IndexedDbWalletLocalStore implements WalletLocalStore {
  @override
  Future<void> save(String key, Uint8List bytes) async {
    await _save(key, bytes.toJS).toDart;
  }

  @override
  Future<Uint8List?> read(String key) async {
    try {
      return (await _read(key).toDart)?.toDart;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Set<String>> keysWithPrefix(String prefix) async {
    try {
      final keys = await _keys(prefix).toDart;
      return keys.toDart.map((key) => key.toDart).toSet();
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> remove(String key) async {
    await _remove(key).toDart;
  }

  @override
  Future<void> removePrefix(String prefix) async {
    await _removePrefix(prefix).toDart;
  }

  @override
  Future<void> requestPersistence() async {
    try {
      await _requestPersistence().toDart;
    } catch (_) {}
  }

  @override
  Future<void> warmUp(List<String> urls) async {
    try {
      await _warmUp(urls.map((url) => url.toJS).toList().toJS).toDart;
    } catch (_) {}
  }
}
