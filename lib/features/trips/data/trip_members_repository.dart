import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';

final tripMembersRepositoryProvider = Provider<TripMembersRepository>((ref) {
  return TripMembersRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Stream of [TripMember] documents for a trip (`trips/{tripId}/participants/*`).
final tripParticipantsStreamProvider =
    StreamProvider.autoDispose.family<List<TripMember>, String>((ref, tripId) {
  return ref.watch(tripMembersRepositoryProvider).streamParticipants(tripId);
});

/// The current user's [TripMember] document for a trip, or null if not a participant.
final myTripMemberStreamProvider =
    StreamProvider.autoDispose.family<TripMember?, String>((ref, tripId) {
  return ref.watch(tripMembersRepositoryProvider).watchMyParticipant(tripId);
});

/// The current user's [TripMemberStay] for a trip, derived from their participant doc.
final tripMemberStayStreamProvider =
    StreamProvider.autoDispose.family<TripMemberStay?, String>((ref, tripId) {
  return ref
      .watch(tripMembersRepositoryProvider)
      .watchMyParticipant(tripId)
      .map((member) => member?.stay);
});

/// The current user's [TripMemberPhoneVisibility] for a trip.
final tripMemberPhoneVisibilityStreamProvider =
    StreamProvider.autoDispose.family<TripMemberPhoneVisibility?, String>((ref, tripId) {
  return ref
      .watch(tripMembersRepositoryProvider)
      .watchMyParticipant(tripId)
      .map((member) => member?.phoneVisibility);
});

/// Phone visibility for all claimed participants of a trip, keyed by userId.
final tripMembersPhoneVisibilityStreamProvider =
    StreamProvider.autoDispose.family<Map<String, TripMemberPhoneVisibility>, String>((ref, tripId) {
  return ref
      .watch(tripMembersRepositoryProvider)
      .watchAllMembersPhoneVisibility(tripId);
});

class TripMembersRepository {
  TripMembersRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _participantsRef(String tripId) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('participants');
  }

  Stream<List<TripMember>> streamParticipants(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) return const Stream.empty();
    return _participantsRef(cleanId).snapshots().map(
          (snap) => snap.docs
              .map((doc) => TripMember.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<TripMember?> watchMyParticipant(String tripId) {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return const Stream.empty();
    }
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) return const Stream.empty();
    return _participantsRef(cleanId)
        .where('userId', isEqualTo: uid)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return TripMember.fromMap(doc.id, doc.data());
    });
  }

  Stream<Map<String, TripMemberPhoneVisibility>> watchAllMembersPhoneVisibility(
      String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) return Stream.value(const {});
    return _participantsRef(cleanId).snapshots().map((snap) {
      final result = <String, TripMemberPhoneVisibility>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final uid = (data['userId'] as String?)?.trim() ?? '';
        if (uid.isEmpty) continue;
        final visibility = TripMemberPhoneVisibility.fromString(
            data['phoneVisibility'] as String?);
        if (visibility != null) {
          result[uid] = visibility;
        }
      }
      return result;
    });
  }

  Future<void> addParticipant({
    required String tripId,
    required String participantName,
  }) async {
    final cleanId = tripId.trim();
    final name = participantName.trim();
    if (cleanId.isEmpty) throw StateError('Voyage invalide');
    if (name.isEmpty) throw StateError('Nom obligatoire');
    await _participantsRef(cleanId).add({
      'participantName': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateParticipantName({
    required String tripId,
    required String memberId,
    required String participantName,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanMemberId = memberId.trim();
    final name = participantName.trim();
    if (cleanTripId.isEmpty || cleanMemberId.isEmpty) {
      throw StateError('Paramètres invalides');
    }
    if (name.isEmpty) throw StateError('Nom obligatoire');
    await _participantsRef(cleanTripId).doc(cleanMemberId).update({
      'participantName': name,
    });
  }

  Future<void> removeParticipant({
    required String tripId,
    required String memberId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanMemberId = memberId.trim();
    if (cleanTripId.isEmpty || cleanMemberId.isEmpty) {
      throw StateError('Paramètres invalides');
    }
    await _participantsRef(cleanTripId).doc(cleanMemberId).delete();
  }

  /// Sets [userId] on an existing participant document (claim flow).
  Future<void> claimParticipant({
    required String tripId,
    required String memberId,
    required String userId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanMemberId = memberId.trim();
    final cleanUserId = userId.trim();
    if (cleanTripId.isEmpty || cleanMemberId.isEmpty || cleanUserId.isEmpty) {
      throw StateError('Paramètres invalides');
    }
    await _participantsRef(cleanTripId).doc(cleanMemberId).update({
      'userId': cleanUserId,
    });
  }

  /// Updates stay bounds and/or phone visibility for a participant via Cloud Function.
  /// Allowed for the participant themselves or a user with manageParticipants permission.
  Future<void> updateParticipantProfile({
    required String tripId,
    required String participantId,
    TripMemberStay? stay,
    TripMemberPhoneVisibility? phoneVisibility,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanParticipantId = participantId.trim();
    if (cleanTripId.isEmpty || cleanParticipantId.isEmpty) {
      throw StateError('Paramètres invalides');
    }
    final payload = <String, dynamic>{
      'tripId': cleanTripId,
      'participantId': cleanParticipantId,
      if (stay != null) ...stay.toFirestoreMap(),
      if (phoneVisibility != null) 'phoneVisibility': phoneVisibility.toFirestore(),
    };
    final callable = FirebaseFunctions.instanceFor(
      region: kFirebaseFunctionsRegion,
    ).httpsCallable('updateParticipantProfile');
    await callable.call(payload);
  }
}
