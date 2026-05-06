import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/core/firebase/firebase_target.dart';

const bool _kUseFirebaseEmulator = bool.fromEnvironment(
  'USE_FIREBASE_EMULATOR',
  defaultValue: false,
);

const String _kFirebaseEmulatorHostOverride = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
);

/// Ports from `firebase emulators:start` summary (Auth / Firestore / Functions / Storage).
const int _kAuthEmulatorPort = 9099;
const int _kFirestoreEmulatorPort = 8080;
const int _kFunctionsEmulatorPort = 5001;
const int _kStorageEmulatorPort = 9199;

/// Wires the default Firebase app to local emulators when enabled at compile time.
///
/// Enable with `--dart-define=USE_FIREBASE_EMULATOR=true` (preview target only).
/// Host defaults to `127.0.0.1` (same binding as the Java emulators log table).
/// Optional host override: `--dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10`
/// (e.g. physical device on LAN).
class FirebaseEmulatorWiring {
  FirebaseEmulatorWiring._();

  static String _resolveHost() {
    if (_kFirebaseEmulatorHostOverride.isNotEmpty) {
      return _kFirebaseEmulatorHostOverride;
    }
    if (kIsWeb) {
      return '127.0.0.1';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android emulator: host loopback is 10.0.2.2. Physical devices: set
      // FIREBASE_EMULATOR_HOST to your machine's LAN IP.
      return '10.0.2.2';
    }
    return '127.0.0.1';
  }

  static Future<void> applyIfEnabled(FirebaseTarget target) async {
    if (!_kUseFirebaseEmulator) {
      return;
    }
    if (target != FirebaseTarget.preview) {
      return;
    }
    final host = _resolveHost();
    await FirebaseAuth.instance.useAuthEmulator(host, _kAuthEmulatorPort);
    FirebaseFirestore.instance.useFirestoreEmulator(host, _kFirestoreEmulatorPort);
    FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion)
        .useFunctionsEmulator(host, _kFunctionsEmulatorPort);
    await FirebaseStorage.instance.useStorageEmulator(host, _kStorageEmulatorPort);
  }
}
