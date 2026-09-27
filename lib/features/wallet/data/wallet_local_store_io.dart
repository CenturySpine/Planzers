import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:planerz/features/wallet/data/wallet_local_store.dart';

WalletLocalStore createWalletLocalStore() => _FileWalletLocalStore();

/// Files under the app's private support directory (`wallet/{key}`).
class _FileWalletLocalStore implements WalletLocalStore {
  Future<Directory> _root() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'wallet'));
  }

  Future<File> _file(String key) async =>
      File(p.joinAll([(await _root()).path, ...key.split('/')]));

  @override
  Future<void> save(String key, Uint8List bytes) async {
    final file = await _file(key);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final file = await _file(key);
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Set<String>> keysWithPrefix(String prefix) async {
    final root = await _root();
    if (!await root.exists()) return const {};
    final keys = <String>{};
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final key = p.split(p.relative(entity.path, from: root.path)).join('/');
      if (key.startsWith(prefix)) keys.add(key);
    }
    return keys;
  }

  @override
  Future<void> remove(String key) async {
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> removePrefix(String prefix) async {
    for (final key in await keysWithPrefix(prefix)) {
      await remove(key);
    }
  }

  @override
  Future<void> requestPersistence() async {}

  @override
  Future<void> warmUp(List<String> urls) async {}
}
