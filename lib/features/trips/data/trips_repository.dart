import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/trips/data/trip.dart';

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  return TripsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final tripsStreamProvider = StreamProvider<List<Trip>>((ref) {
  return ref.watch(tripsRepositoryProvider).watchMyTrips();
});

class TripsRepository {
  TripsRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  static final Uri _inviteBaseUri = _resolveInviteBaseUri();

  static Uri _resolveInviteBaseUri() {
    const configured = String.fromEnvironment('INVITE_BASE_URL');
    if (configured.trim().isNotEmpty) {
      return Uri.parse(configured.trim());
    }

    // In web dev (`flutter run -d chrome`), keep same-origin links to avoid
    // history/navigation security errors on localhost.
    if (kIsWeb) {
      return Uri.parse(Uri.base.origin).replace(path: '/invite');
    }

    return Uri.parse('https://planzers.web.app/invite');
  }

  String _generateInviteToken() {
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    final uid = auth.currentUser?.uid ?? 'anon';
    return sha256.convert('$uid-$now'.codeUnits).toString().substring(0, 32);
  }

  Stream<List<Trip>> watchMyTrips() {
    final user = auth.currentUser;
    if (user == null) {
      return Stream.value(const <Trip>[]);
    }

    return firestore
        .collection('trips')
        .where('memberIds', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) {
          final trips = snapshot.docs
              .map((doc) => Trip.fromMap(doc.id, doc.data()))
              .toList();
          trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return trips;
        });
  }

  Future<void> createTrip({
    required String title,
    required String destination,
    String address = '',
    String linkUrl = '',
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final doc = firestore.collection('trips').doc();
    await doc.set({
      'title': title.trim(),
      'destination': destination.trim(),
      'address': address.trim(),
      'linkUrl': linkUrl.trim(),
      'ownerId': user.uid,
      'memberIds': <String>[user.uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteTrip({
    required String tripId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      return;
    }

    final data = snapshot.data();
    final ownerId = (data?['ownerId'] as String?) ?? '';
    if (ownerId != user.uid) {
      throw StateError('Seul le proprietaire peut supprimer ce voyage');
    }

    await docRef.delete();
  }

  Future<void> updateTrip({
    required String tripId,
    required String title,
    required String destination,
    required String address,
    required String linkUrl,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data();
    final ownerId = (data?['ownerId'] as String?) ?? '';
    if (ownerId != user.uid) {
      throw StateError('Seul le proprietaire peut modifier ce voyage');
    }

    await docRef.update({
      'title': title.trim(),
      'destination': destination.trim(),
      'address': address.trim(),
      'linkUrl': linkUrl.trim(),
    });
  }

  Future<String> getOrCreateInviteLink({
    required String tripId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final ownerId = (data['ownerId'] as String?) ?? '';
    if (ownerId != user.uid) {
      throw StateError('Seul le proprietaire peut partager une invitation');
    }

    var inviteToken = (data['inviteToken'] as String?)?.trim() ?? '';
    if (inviteToken.isEmpty) {
      inviteToken = _generateInviteToken();
      await docRef.update({'inviteToken': inviteToken});
    }

    final params = <String, String>{
      'tripId': tripId,
      'token': inviteToken,
    };

    if (kIsWeb) {
      final query = Uri(queryParameters: params).query;
      return '${Uri.base.origin}/#/invite?$query';
    }

    return _inviteBaseUri.replace(queryParameters: params).toString();
  }

  Future<void> joinTripWithInvite({
    required String tripId,
    required String token,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw StateError('Lien d invitation invalide');
    }

    final regionFunctions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = regionFunctions.httpsCallable('joinTripWithInvite');
    await callable.call(<String, dynamic>{
      'tripId': tripId,
      'token': cleanToken,
    });
  }
}
