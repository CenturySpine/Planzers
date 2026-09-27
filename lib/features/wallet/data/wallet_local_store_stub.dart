import 'dart:typed_data';

import 'package:planerz/features/wallet/data/wallet_local_store.dart';

WalletLocalStore createWalletLocalStore() => _NoopWalletLocalStore();

class _NoopWalletLocalStore implements WalletLocalStore {
  @override
  Future<Set<String>> keysWithPrefix(String prefix) async => const {};

  @override
  Future<Uint8List?> read(String key) async => null;

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> removePrefix(String prefix) async {}

  @override
  Future<void> requestPersistence() async {}

  @override
  Future<void> save(String key, Uint8List bytes) async {}

  @override
  Future<void> warmUp(List<String> urls) async {}
}
