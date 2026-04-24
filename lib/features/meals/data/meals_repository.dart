import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';

final mealsRepositoryProvider = Provider<MealsRepository>((ref) {
  return MealsRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});

/// Live meals for a trip, sorted chronologically (oldest date first, by day part within date).
final tripMealsStreamProvider =
    StreamProvider.autoDispose.family<List<TripMeal>, String>(
  (ref, tripId) {
    return ref.watch(mealsRepositoryProvider).watchMealsByTrip(tripId);
  },
);

/// Single meal by ID and trip.
final tripMealStreamProvider = StreamProvider.autoDispose
    .family<TripMeal?, ({String tripId, String mealId})>(
  (ref, params) {
    return ref
        .watch(mealsRepositoryProvider)
        .watchMealById(params.tripId, params.mealId);
  },
);

class MealsRepository {
  MealsRepository({
    required this.firestore,
    required this.auth,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> _mealsCol(String tripId) {
    return firestore.collection('trips').doc(tripId).collection('meals');
  }

  DocumentReference<Map<String, dynamic>> _memberRef({
    required String tripId,
    required String memberId,
  }) {
    return firestore
        .collection('trips')
        .doc(tripId.trim())
        .collection('members')
        .doc(memberId.trim());
  }

  /// Calculate automatic participants for a meal at given date + day part,
  /// based on all trip members' presence (TripMemberStay).
  /// Ignores members whose stay data is missing or invalid.
  Future<List<String>> calculateMealParticipants({
    required String tripId,
    required String mealDateKey, // YYYY-MM-DD format
    required String mealDayPart, // 'morning', 'midday', 'evening'
    required List<String> allMemberIds,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty || mealDateKey.trim().isEmpty) {
      return const [];
    }

    final participants = <String>[];
    final targetDayPart = tripDayPartFromFirestore(mealDayPart.trim());
    if (targetDayPart == null) {
      return const [];
    }
    for (final memberId in allMemberIds) {
      final staySnap =
          await _memberRef(tripId: cleanTripId, memberId: memberId).get();
      if (!staySnap.exists) continue;

      final stay = TripMemberStay.tryFromFirestore(staySnap.data() ?? {});
      if (stay == null) continue;

      // Inclusive comparison: mealDate >= stayStart && mealDate <= stayEnd
      final mealIsWithinBounds =
          mealDateKey.compareTo(stay.startDateKey) >= 0 &&
              mealDateKey.compareTo(stay.endDateKey) <= 0;
      if (!mealIsWithinBounds) continue;

      final isStartDate = mealDateKey == stay.startDateKey;
      final isEndDate = mealDateKey == stay.endDateKey;
      final targetIndex = tripDayPartSortIndex(targetDayPart);
      final startIndex = tripDayPartSortIndex(stay.startDayPart);
      final endIndex = tripDayPartSortIndex(stay.endDayPart);

      if (isStartDate && targetIndex < startIndex) continue;
      if (isEndDate && targetIndex > endIndex) continue;
      participants.add(memberId);
    }

    participants.sort();
    return participants;
  }

  Stream<List<TripMeal>> watchMealsByTrip(String tripId) {
    final cleanId = tripId.trim();
    if (cleanId.isEmpty) {
      return Stream.value(const <TripMeal>[]);
    }

    return _mealsCol(cleanId)
        .orderBy('mealDateKey', descending: false)
        .snapshots()
        .map((snap) => TripMeal.sortedChronological(
              snap.docs.map(TripMeal.fromDoc).toList(),
            ));
  }

  Stream<TripMeal?> watchMealById(String tripId, String mealId) {
    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      return Stream.value(null);
    }

    return _mealsCol(cleanTripId).doc(cleanMealId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return TripMeal.fromDoc(snap);
    });
  }

  Future<String> addMeal({
    required String tripId,
    required String name,
    required String mealDateKey,
    required String mealDayPart, // 'morning', 'midday', 'evening'
    required List<String> participantIds,
    String? chefParticipantId,
    required String notes,
    List<MealComponent> components = const [],
    MealMode mealMode = MealMode.cooked,
    String restaurantUrl = '',
    List<MealPotluckItem> potluckItems = const [],
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanName = name.trim();
    if (cleanTripId.isEmpty) {
      throw StateError('Voyage invalide');
    }

    final docRef = await _mealsCol(cleanTripId).add({
      'name': cleanName,
      'mealDateKey': mealDateKey.trim(),
      'mealDayPart': mealDayPart.trim(),
      'participantIds': participantIds,
      'chefParticipantId': chefParticipantId?.trim().isEmpty ?? true
          ? null
          : chefParticipantId!.trim(),
      'notes': notes.trim(),
      'components': components.map((c) => c.toMap()).toList(growable: false),
      'mealMode': mealMode.firestoreValue,
      'restaurantUrl': restaurantUrl.trim(),
      'potluckItems': potluckItems
          .map((item) => item.toMap())
          .where((item) => (item['label'] as String).isNotEmpty)
          .toList(growable: false),
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  Future<void> updateMeal({
    required String tripId,
    required String mealId,
    required String name,
    required String mealDateKey,
    required String mealDayPart,
    required List<String> participantIds,
    String? chefParticipantId,
    required String notes,
    List<MealComponent> components = const [],
    MealMode mealMode = MealMode.cooked,
    String restaurantUrl = '',
    List<MealPotluckItem> potluckItems = const [],
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    final cleanName = name.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    await docRef.update({
      'name': cleanName,
      'mealDateKey': mealDateKey.trim(),
      'mealDayPart': mealDayPart.trim(),
      'participantIds': participantIds,
      'chefParticipantId': chefParticipantId?.trim().isEmpty ?? true
          ? null
          : chefParticipantId!.trim(),
      'notes': notes.trim(),
      'components': components.map((c) => c.toMap()).toList(growable: false),
      'mealMode': mealMode.firestoreValue,
      'restaurantUrl': restaurantUrl.trim(),
      'potluckItems': potluckItems
          .map((item) => item.toMap())
          .where((item) => (item['label'] as String).isNotEmpty)
          .toList(growable: false),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMealName({
    required String tripId,
    required String mealId,
    required String name,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    await docRef.update({
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMealDate({
    required String tripId,
    required String mealId,
    required String mealDateKey,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    await docRef.update({
      'mealDateKey': mealDateKey.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMealDayPart({
    required String tripId,
    required String mealId,
    required String mealDayPart,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    await docRef.update({
      'mealDayPart': mealDayPart.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMealParticipants({
    required String tripId,
    required String mealId,
    required List<String> participantIds,
    String? chefParticipantId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    final normalizedParticipantIds = participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    final normalizedChef = (chefParticipantId ?? '').trim();

    await docRef.update({
      'participantIds': normalizedParticipantIds,
      'chefParticipantId': normalizedChef.isEmpty ||
              !normalizedParticipantIds.contains(normalizedChef)
          ? null
          : normalizedChef,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMealMode({
    required String tripId,
    required String mealId,
    required MealMode mealMode,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    await docRef.update({
      'mealMode': mealMode.firestoreValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMealPotluckItems({
    required String tripId,
    required String mealId,
    required List<MealPotluckItem> potluckItems,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    await docRef.update({
      'potluckItems': potluckItems
          .map((item) => item.toMap())
          .where((item) => (item['label'] as String).isNotEmpty)
          .toList(growable: false),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMealRestaurantUrl({
    required String tripId,
    required String mealId,
    required String restaurantUrl,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    await docRef.update({
      'restaurantUrl': restaurantUrl.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMealComponents({
    required String tripId,
    required String mealId,
    required List<MealComponent> components,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    await docRef.update({
      'components': components.map((c) => c.toMap()).toList(growable: false),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> lockMealComponent({
    required String tripId,
    required String mealId,
    required String componentId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    final cleanComponentId = componentId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty || cleanComponentId.isEmpty) {
      throw StateError('Composant invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    return firestore.runTransaction<String?>((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) {
        throw StateError('Repas introuvable');
      }
      final data = snap.data() ?? const <String, dynamic>{};
      final components = ((data['components'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList(growable: true);
      final index = components.indexWhere(
        (component) => (component['id'] as String? ?? '').trim() == cleanComponentId,
      );
      if (index < 0) {
        throw StateError('Composant introuvable');
      }

      final currentLockOwner = (components[index]['lockedBy'] as String? ?? '').trim();
      if (currentLockOwner.isNotEmpty && currentLockOwner != user.uid) {
        return currentLockOwner;
      }

      components[index]['lockedBy'] = user.uid;
      tx.update(docRef, {
        'components': components,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    });
  }

  Future<void> unlockMealComponent({
    required String tripId,
    required String mealId,
    required String componentId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    final cleanComponentId = componentId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty || cleanComponentId.isEmpty) {
      throw StateError('Composant invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    await firestore.runTransaction<void>((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) {
        return;
      }
      final data = snap.data() ?? const <String, dynamic>{};
      final components = ((data['components'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList(growable: true);
      final index = components.indexWhere(
        (component) => (component['id'] as String? ?? '').trim() == cleanComponentId,
      );
      if (index < 0) return;

      final currentLockOwner = (components[index]['lockedBy'] as String? ?? '').trim();
      if (currentLockOwner.isEmpty || currentLockOwner != user.uid) {
        return;
      }

      components[index]['lockedBy'] = null;
      tx.update(docRef, {
        'components': components,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> deleteMeal({
    required String tripId,
    required String mealId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecte');
    }

    final cleanTripId = tripId.trim();
    final cleanMealId = mealId.trim();
    if (cleanTripId.isEmpty || cleanMealId.isEmpty) {
      throw StateError('Repas invalide');
    }

    final docRef = _mealsCol(cleanTripId).doc(cleanMealId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Repas introuvable');
    }

    await docRef.delete();
  }
}
