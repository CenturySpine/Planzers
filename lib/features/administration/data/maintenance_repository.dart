import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/auth/auth_gate.dart';

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  return MaintenanceRepository(
    firestore: FirebaseFirestore.instance,
  );
});

final maintenanceOngoingProvider = StreamProvider.autoDispose<bool>((ref) {
  return ref.watch(maintenanceRepositoryProvider).watchIsMaintenanceOngoing();
});

final isApplicationOwnerProvider = StreamProvider.autoDispose<bool>((ref) {
  ref.watch(authStateProvider);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream<bool>.value(false);
  }
  return ref.read(accountRepositoryProvider).watchMyUserDocument().map((snap) {
    return snap.data()?['isApplicationOwner'] == true;
  });
});

class MaintenanceRepository {
  MaintenanceRepository({required this.firestore});

  final FirebaseFirestore firestore;

  static const String systemDocId = 'maintenance';
  static const String ongoingField = 'isMaintenanceOngoing';

  DocumentReference<Map<String, dynamic>> get _maintenanceDoc =>
      firestore.collection('system').doc(systemDocId);

  /// Realtime maintenance flag. On mobile, Firestore persistence can keep a stale
  /// cached `true` after the server value is `false`; prefer server snapshots
  /// and seed with an explicit server read on subscribe.
  Stream<bool> watchIsMaintenanceOngoing() {
    return Stream<bool>.multi((controller) {
      DocumentSnapshot<Map<String, dynamic>>? lastServerSnapshot;

      void emitFrom(DocumentSnapshot<Map<String, dynamic>> snap) {
        if (!snap.metadata.isFromCache) {
          lastServerSnapshot = snap;
          controller.add(_readIsMaintenanceOngoing(snap));
          return;
        }
        if (lastServerSnapshot == null) {
          controller.add(_readIsMaintenanceOngoing(snap));
        }
      }

      final listener = _maintenanceDoc
          .snapshots(includeMetadataChanges: true)
          .listen(emitFrom, onError: controller.addError);

      _maintenanceDoc
          .get(const GetOptions(source: Source.server))
          .then((snap) {
            lastServerSnapshot = snap;
            if (!controller.isClosed) {
              controller.add(_readIsMaintenanceOngoing(snap));
            }
          })
          .catchError((_) {
            // Offline: cache listener above is the only source.
          });

      controller.onCancel = () async {
        await listener.cancel();
      };
    });
  }

  bool _readIsMaintenanceOngoing(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) return false;
    return snap.data()?[ongoingField] == true;
  }

  Future<void> setMaintenanceOngoing(bool ongoing) async {
    await _maintenanceDoc.set(
      {ongoingField: ongoing},
      SetOptions(merge: true),
    );
  }
}
