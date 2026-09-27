import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device reports a network connection. On the web this follows
/// the browser's online/offline status: "online" does not guarantee the
/// servers are reachable, so network calls must still handle failures.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
});

/// Last known value, assuming online until told otherwise.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(isOnlineProvider).asData?.value == false;
});
