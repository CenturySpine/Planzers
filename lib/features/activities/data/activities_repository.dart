import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';

final activitiesRepositoryProvider = Provider<ActivitiesRepository>((ref) {
  return ActivitiesRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Live activities for a trip, newest first.
final tripActivitiesStreamProvider =
    StreamProvider.autoDispose.family<List<TripActivity>, String>(
        (ref, tripId) {
  return ref.watch(activitiesRepositoryProvider).watchTripActivities(tripId);
});

class ActivitiesRepository {
  ActivitiesRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _activitiesCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('activities');
  }

  Stream<List<TripActivity>> watchTripActivities(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const <TripActivity>[]);
    }

    return _activitiesCol(cleanId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(TripActivity.fromDoc).toList());
  }

  Future<void> addActivity({
    required String tripId,
    required String label,
    required TripActivityCategory category,
    required String linkUrl,
    required String address,
    required String freeComments,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty) {
      throw StateError('Libelle obligatoire');
    }

    final tripSnap = await firestore.collection('trips').doc(cleanTripId).get();
    if (!tripSnap.exists || tripSnap.data() == null) {
      throw StateError('Voyage introuvable');
    }
    final trip = Trip.fromMap(tripSnap.id, tripSnap.data()!);
    final canSuggest = canSuggestActivityForTrip(
      trip: trip,
      userId: user.uid,
    );
    if (!canSuggest) {
      throw StateError('Droits insuffisants pour suggerer une activite');
    }

    await _activitiesCol(cleanTripId).add({
      'label': cleanLabel,
      'category': category.firestoreValue,
      'linkUrl': linkUrl.trim(),
      'address': address.trim(),
      'freeComments': freeComments.trim(),
      'done': false,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Any signed-in user may toggle (trip membership enforced by Firestore rules).
  Future<void> setActivityDone({
    required String tripId,
    required String activityId,
    required bool done,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanActivityId = activityId.trim();
    if (cleanTripId.isEmpty || cleanActivityId.isEmpty) {
      throw StateError('Activite invalide');
    }

    final docRef = _activitiesCol(cleanTripId).doc(cleanActivityId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Activite introuvable');
    }

    final tripSnap = await firestore.collection('trips').doc(cleanTripId).get();
    if (!tripSnap.exists || tripSnap.data() == null) {
      throw StateError('Voyage introuvable');
    }
    final trip = Trip.fromMap(tripSnap.id, tripSnap.data()!);
    final canEdit = canEditActivityForTrip(
      trip: trip,
      userId: user.uid,
    );
    if (!canEdit) {
      throw StateError('Droits insuffisants pour modifier une activite');
    }

    await docRef.update({
      'done': done,
      'doneAt': done ? FieldValue.serverTimestamp() : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setActivityPlannedAt({
    required String tripId,
    required String activityId,
    DateTime? plannedAt,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanActivityId = activityId.trim();
    if (cleanTripId.isEmpty || cleanActivityId.isEmpty) {
      throw StateError('Activite invalide');
    }

    final docRef = _activitiesCol(cleanTripId).doc(cleanActivityId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Activite introuvable');
    }

    final tripSnap = await firestore.collection('trips').doc(cleanTripId).get();
    if (!tripSnap.exists || tripSnap.data() == null) {
      throw StateError('Voyage introuvable');
    }
    final trip = Trip.fromMap(tripSnap.id, tripSnap.data()!);
    final canPlan = canPlanActivityForTrip(
      trip: trip,
      userId: user.uid,
    );
    if (!canPlan) {
      throw StateError('Droits insuffisants pour planifier une activite');
    }

    await docRef.update({
      'plannedAt':
          plannedAt != null ? Timestamp.fromDate(plannedAt) : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateActivity({
    required String tripId,
    required String activityId,
    required String label,
    required TripActivityCategory category,
    required String linkUrl,
    required String address,
    required String freeComments,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanActivityId = activityId.trim();
    if (cleanTripId.isEmpty || cleanActivityId.isEmpty) {
      throw StateError('Activite invalide');
    }

    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty) {
      throw StateError('Libelle obligatoire');
    }

    final docRef = _activitiesCol(cleanTripId).doc(cleanActivityId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Activite introuvable');
    }

    final tripSnap = await firestore.collection('trips').doc(cleanTripId).get();
    if (!tripSnap.exists || tripSnap.data() == null) {
      throw StateError('Voyage introuvable');
    }
    final trip = Trip.fromMap(tripSnap.id, tripSnap.data()!);
    final canEdit = canEditActivityForTrip(
      trip: trip,
      userId: user.uid,
    );
    if (!canEdit) {
      throw StateError('Droits insuffisants pour modifier une activite');
    }

    await docRef.update({
      'label': cleanLabel,
      'category': category.firestoreValue,
      'linkUrl': linkUrl.trim(),
      'address': address.trim(),
      'freeComments': freeComments.trim(),
      'itinerary': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteActivity({
    required String tripId,
    required String activityId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanActivityId = activityId.trim();
    if (cleanTripId.isEmpty || cleanActivityId.isEmpty) {
      throw StateError('Activite invalide');
    }

    final docRef = _activitiesCol(cleanTripId).doc(cleanActivityId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Activite introuvable');
    }

    final tripSnap = await firestore.collection('trips').doc(cleanTripId).get();
    if (!tripSnap.exists || tripSnap.data() == null) {
      throw StateError('Voyage introuvable');
    }
    final trip = Trip.fromMap(tripSnap.id, tripSnap.data()!);
    final canDelete = canDeleteActivityForTrip(
      trip: trip,
      userId: user.uid,
    );
    if (!canDelete) {
      throw StateError('Droits insuffisants pour supprimer une activite');
    }

    await docRef.delete();
  }
}
