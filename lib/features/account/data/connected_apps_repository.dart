import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';

final connectedAppsRepositoryProvider = Provider<ConnectedAppsRepository>((ref) {
  return ConnectedAppsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

class ConnectedApp {
  const ConnectedApp({
    required this.clientId,
    required this.displayName,
    required this.iconUrl,
    required this.scope,
    required this.connectedAt,
    required this.lastUsedAt,
  });

  final String clientId;
  final String displayName;
  final String iconUrl;
  final String scope;
  final DateTime? connectedAt;
  final DateTime? lastUsedAt;

  factory ConnectedApp.fromMap(String clientId, Map<String, dynamic> data) {
    final rawScope = data['scope'];
    final scope = rawScope is List
        ? rawScope.map((e) => e.toString()).join(' ')
        : (rawScope as String?)?.trim() ?? '';
    return ConnectedApp(
      clientId: clientId,
      displayName: (data['clientDisplayName'] as String?)?.trim() ?? clientId,
      iconUrl: (data['clientIconUrl'] as String?)?.trim() ?? '',
      scope: scope,
      connectedAt: (data['connectedAt'] as Timestamp?)?.toDate(),
      lastUsedAt: (data['lastUsedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Third-party apps (e.g. Ridgegear) the current user has authorized via
/// the OAuth consent flow. See [OAuthRepository] for the consent side.
class ConnectedAppsRepository {
  ConnectedAppsRepository({required this.firestore, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  Stream<List<ConnectedApp>> watchMyConnectedApps() {
    final uid = auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <ConnectedApp>[]);
    return firestore
        .collection('users')
        .doc(uid)
        .collection('connectedApps')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ConnectedApp.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<void> revoke(String clientId) async {
    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    ).httpsCallable('revokeConnectedApp');
    await callable.call(<String, dynamic>{'clientId': clientId});
  }
}
