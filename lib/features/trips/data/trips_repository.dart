import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
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

/// Single trip document stream (for trip hub shell and deep links).
final tripStreamProvider =
    StreamProvider.autoDispose.family<Trip?, String>((ref, tripId) {
  return ref.watch(tripsRepositoryProvider).watchTrip(tripId);
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

  Stream<Trip?> watchTrip(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(null);
    }

    return firestore.collection('trips').doc(cleanId).snapshots().map((snap) {
      if (!snap.exists) {
        return null;
      }
      final data = snap.data();
      if (data == null) {
        return null;
      }
      return Trip.fromMap(snap.id, data);
    });
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
      final trips =
          snapshot.docs.map((doc) => Trip.fromMap(doc.id, doc.data())).toList();
      trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return trips;
    });
  }

  Future<void> createTrip({
    required String title,
    required String destination,
    String address = '',
    String linkUrl = '',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final ownerEmail = user.email?.trim() ?? '';
    final ownerLabel = displayLabelFromEmail(ownerEmail);

    final data = <String, dynamic>{
      'title': title.trim(),
      'destination': destination.trim(),
      'address': address.trim(),
      'linkUrl': linkUrl.trim(),
      'ownerId': user.uid,
      'memberIds': <String>[user.uid],
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (ownerLabel.isNotEmpty) {
      data['memberPublicLabels'] = <String, dynamic>{user.uid: ownerLabel};
    }
    if (startDate != null) {
      data['startDate'] = Timestamp.fromDate(startDate);
    }
    if (endDate != null) {
      data['endDate'] = Timestamp.fromDate(endDate);
    }

    final doc = firestore.collection('trips').doc();
    final defaultGroupRef = doc.collection('expenseGroups').doc();
    final batch = firestore.batch();
    batch.set(doc, data);
    batch.set(defaultGroupRef, {
      'title': 'Commun',
      'visibleToMemberIds': <String>[user.uid],
      'isDefault': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
    });
    await batch.commit();
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
    DateTime? startDate,
    DateTime? endDate,
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

    final update = <String, dynamic>{
      'title': title.trim(),
      'destination': destination.trim(),
      'address': address.trim(),
      'linkUrl': linkUrl.trim(),
      'startDate': startDate != null
          ? Timestamp.fromDate(startDate)
          : FieldValue.delete(),
      'endDate': endDate != null
          ? Timestamp.fromDate(endDate)
          : FieldValue.delete(),
    };

    await docRef.update(update);
  }

  /// Invite secret shared with guests (same value as the `token` query param
  /// in the invite link). Owner-only.
  Future<String> getOrCreateInviteToken({
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

    return inviteToken;
  }

  Future<String> getOrCreateInviteLink({
    required String tripId,
  }) async {
    final inviteToken = await getOrCreateInviteToken(tripId: tripId);

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

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = regionFunctions.httpsCallable('joinTripWithInvite');
    await callable.call(<String, dynamic>{
      'tripId': tripId,
      'token': cleanToken,
    });
  }

  /// Joins using only the invite token (same as opening the invite link).
  /// Returns the trip id for navigation.
  Future<String> joinTripWithInviteToken(String token) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanToken = token.trim();
    if (cleanToken.isEmpty) {
      throw StateError('Code d invitation invalide');
    }

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = regionFunctions.httpsCallable('joinTripWithInviteToken');
    final result = await callable.call(<String, dynamic>{
      'token': cleanToken,
    });
    final data = result.data;
    if (data is! Map) {
      throw StateError('Reponse serveur invalide');
    }
    final tripId = data['tripId'];
    if (tripId is! String || tripId.trim().isEmpty) {
      throw StateError('Reponse serveur invalide');
    }
    return tripId.trim();
  }

  /// Ensures this user's [memberPublicLabels] entry exists on the trip (email
  /// local part via Admin SDK). Safe to call after join; no-op if Cloud
  /// Function is unavailable.
  Future<void> registerMyTripMemberLabel({required String tripId}) async {
    final user = auth.currentUser;
    if (user == null) {
      return;
    }
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return;
    }

    final regionFunctions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable =
        regionFunctions.httpsCallable('registerMyTripMemberLabel');
    await callable.call(<String, dynamic>{'tripId': cleanId});
  }

  Future<void> removeMemberFromTrip({
    required String tripId,
    required String memberId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanMemberId = memberId.trim();
    if (cleanMemberId.isEmpty) {
      throw StateError('Membre invalide');
    }
    if (cleanMemberId == user.uid) {
      throw StateError('Le proprietaire ne peut pas se supprimer lui-meme');
    }

    final docRef = firestore.collection('trips').doc(tripId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw StateError('Voyage introuvable');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final ownerId = (data['ownerId'] as String?) ?? '';
    if (ownerId != user.uid) {
      throw StateError('Seul le proprietaire peut retirer un membre');
    }

    await docRef.update({
      'memberIds': FieldValue.arrayRemove(<String>[cleanMemberId]),
      'memberPublicLabels.$cleanMemberId': FieldValue.delete(),
    });
  }
}
