import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';

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

  Future<bool> _isTripAdmin(String tripId, String userId) async {
    final tripSnap = await firestore.collection('trips').doc(tripId).get();
    final tripData = tripSnap.data() ?? const <String, dynamic>{};
    final ownerId = (tripData['ownerId'] as String?)?.trim() ?? '';
    if (ownerId.isNotEmpty && ownerId == userId) return true;
    final admins = (tripData['adminMemberIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString().trim())
        .where((id) => id.isNotEmpty);
    return admins.contains(userId);
  }

  Future<void> _assertCanModifyActivity({
    required String tripId,
    required String userId,
    required Map<String, dynamic> activityData,
  }) async {
    final isLocked = activityData['isLocked'] == true;
    if (!isLocked) return;
    final isAdmin = await _isTripAdmin(tripId, userId);
    if (!isAdmin) {
      throw StateError('Activite verrouillee: modification reservee aux admins');
    }
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
    required bool isLocked,
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
      'address': address.trim(),
      'freeComments': freeComments.trim(),
      'done': false,
      'isLocked': isLocked,
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
    await _assertCanModifyActivity(
      tripId: cleanTripId,
      userId: user.uid,
      activityData: snap.data() ?? const <String, dynamic>{},
    );

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
    await _assertCanModifyActivity(
      tripId: cleanTripId,
      userId: user.uid,
      activityData: snap.data() ?? const <String, dynamic>{},
    );

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
    required bool isLocked,
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
    await _assertCanModifyActivity(
      tripId: cleanTripId,
      userId: user.uid,
      activityData: snap.data() ?? const <String, dynamic>{},
    );

    await docRef.update({
      'label': cleanLabel,
      'category': category.firestoreValue,
      'linkUrl': linkUrl.trim(),
      'address': address.trim(),
      'freeComments': freeComments.trim(),
      'isLocked': isLocked,
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
    await _assertCanModifyActivity(
      tripId: cleanTripId,
      userId: user.uid,
      activityData: snap.data() ?? const <String, dynamic>{},
    );

    await docRef.delete();
  }
}
