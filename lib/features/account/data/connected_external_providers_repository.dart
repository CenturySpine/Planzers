import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';

final connectedExternalProvidersRepositoryProvider =
    Provider<ConnectedExternalProvidersRepository>((ref) {
  return ConnectedExternalProvidersRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

class ConnectedExternalProvider {
  const ConnectedExternalProvider({
    required this.providerId,
    required this.displayName,
    required this.iconUrl,
    required this.scope,
    required this.connectedAt,
    required this.lastUsedAt,
  });

  final String providerId;
  final String displayName;
  final String iconUrl;
  final String scope;
  final DateTime? connectedAt;
  final DateTime? lastUsedAt;

  factory ConnectedExternalProvider.fromMap(
    String providerId,
    Map<String, dynamic> data,
  ) {
    return ConnectedExternalProvider(
      providerId: providerId,
      displayName:
          (data['providerDisplayName'] as String?)?.trim() ?? providerId,
      iconUrl: (data['providerIconUrl'] as String?)?.trim() ?? '',
      scope: (data['scope'] as String?)?.trim() ?? '',
      connectedAt: (data['connectedAt'] as Timestamp?)?.toDate(),
      lastUsedAt: (data['lastUsedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// External ecosystem providers (e.g. Ridgegear) the current user has
/// connected their Planerz account to — Planerz acting as an OAuth
/// *client* this time (mirror image of `ConnectedAppsRepository`). See
/// [ExternalConnectionRepository] for the connection flow itself.
class ConnectedExternalProvidersRepository {
  ConnectedExternalProvidersRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  Stream<List<ConnectedExternalProvider>> watchMyConnectedProviders() {
    final uid = auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <ConnectedExternalProvider>[]);
    return firestore
        .collection('users')
        .doc(uid)
        .collection('connectedExternalProviders')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ConnectedExternalProvider.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<void> revoke(String providerId) async {
    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    ).httpsCallable('revokeExternalConnection');
    await callable.call(<String, dynamic>{'providerId': providerId});
  }
}
