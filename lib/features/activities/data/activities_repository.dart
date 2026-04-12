import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/activities/data/trip_activity.dart';

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
    required String itinerary,
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

    await _activitiesCol(cleanTripId).add({
      'label': cleanLabel,
      'category': category.firestoreValue,
      'linkUrl': linkUrl.trim(),
      'itinerary': itinerary.trim(),
      'freeComments': freeComments.trim(),
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateActivity({
    required String tripId,
    required String activityId,
    required String label,
    required TripActivityCategory category,
    required String linkUrl,
    required String itinerary,
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
    final createdBy = (snap.data()?['createdBy'] as String?)?.trim() ?? '';
    if (createdBy.isEmpty || createdBy != user.uid) {
      throw StateError('Modification reservee a l auteur de la proposition');
    }

    await docRef.update({
      'label': cleanLabel,
      'category': category.firestoreValue,
      'linkUrl': linkUrl.trim(),
      'itinerary': itinerary.trim(),
      'freeComments': freeComments.trim(),
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
    final createdBy = (snap.data()?['createdBy'] as String?)?.trim() ?? '';
    if (createdBy.isEmpty || createdBy != user.uid) {
      throw StateError('Suppression reservee a l auteur de la proposition');
    }

    await docRef.delete();
  }
}
