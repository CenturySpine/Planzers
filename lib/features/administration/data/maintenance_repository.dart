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

  Future<void> setMaintenanceOngoing(bool ongoing) async {
    await _maintenanceDoc.set(
      {ongoingField: ongoing},
      SetOptions(merge: true),
    );
  }
}
