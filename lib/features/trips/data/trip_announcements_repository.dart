import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_announcement.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';

final tripAnnouncementsRepositoryProvider = Provider<TripAnnouncementsRepository>((
  ref,
) {
  return TripAnnouncementsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

final tripAnnouncementsStreamProvider = StreamProvider.autoDispose
    .family<List<TripAnnouncement>, String>((ref, tripId) {
  return ref.watch(tripAnnouncementsRepositoryProvider).watchAnnouncements(tripId);
});

class TripAnnouncementsRepository {
  TripAnnouncementsRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  static const int maxTextLength = 4000;

  CollectionReference<Map<String, dynamic>> _announcementsCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('announcements');
  }

  Future<(Trip trip, String uid)> _resolveAllowedPublisher(String tripId) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }
    final tripRef = firestore.collection('trips').doc(cleanTripId);
    final tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw StateError('Voyage introuvable');
    }
    final tripData = tripSnap.data() ?? const <String, dynamic>{};
    final trip = Trip.fromMap(tripSnap.id, tripData);
    final uid = user.uid.trim();
    if (!trip.memberIds.contains(uid)) {
      throw StateError('Acces refuse');
    }
    final currentRole = resolveTripPermissionRole(trip: trip, userId: uid);
    final canPublish = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: trip.generalPermissions.publishAnnouncementsMinRole,
    );
    if (!canPublish) {
      throw StateError('Droits insuffisants pour publier une annonce');
    }
    return (trip, uid);
  }

  Stream<List<TripAnnouncement>> watchAnnouncements(String tripId) {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      return Stream.value(const <TripAnnouncement>[]);
    }
    return _announcementsCol(cleanTripId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(TripAnnouncement.fromDoc).toList());
  }

  Future<void> sendAnnouncement({
    required String tripId,
    required String text,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw StateError('Message vide');
    }
    if (trimmed.length > maxTextLength) {
      throw StateError('Message trop long');
    }

    final (_, uid) = await _resolveAllowedPublisher(cleanTripId);

    await _announcementsCol(cleanTripId).add(<String, dynamic>{
      'text': trimmed,
      'authorId': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAnnouncement({
    required String tripId,
    required String announcementId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanAnnouncementId = announcementId.trim();
    if (cleanTripId.isEmpty || cleanAnnouncementId.isEmpty) {
      throw StateError('Parametres invalides');
    }
    await _resolveAllowedPublisher(cleanTripId);
    await _announcementsCol(cleanTripId).doc(cleanAnnouncementId).delete();
  }

  Future<void> updateAnnouncement({
    required String tripId,
    required String announcementId,
    required String text,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanAnnouncementId = announcementId.trim();
    if (cleanTripId.isEmpty || cleanAnnouncementId.isEmpty) {
      throw StateError('Parametres invalides');
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw StateError('Message vide');
    }
    if (trimmed.length > maxTextLength) {
      throw StateError('Message trop long');
    }

    await _resolveAllowedPublisher(cleanTripId);
    await _announcementsCol(cleanTripId).doc(cleanAnnouncementId).update(<String, dynamic>{
      'text': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
