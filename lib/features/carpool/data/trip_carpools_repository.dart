import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/carpool/data/trip_carpool.dart';
import 'package:planerz/features/carpool/data/trip_carpool_section.dart';

final tripCarpoolsRepositoryProvider = Provider<TripCarpoolsRepository>((ref) {
  return TripCarpoolsRepository(firestore: FirebaseFirestore.instance);
});

final tripCarpoolsStreamProvider =
    StreamProvider.autoDispose.family<List<TripCarpool>, String>((ref, tripId) {
  return ref.watch(tripCarpoolsRepositoryProvider).watchTripCarpools(tripId);
});

final tripCarpoolSectionStreamProvider =
    StreamProvider.autoDispose.family<TripCarpoolSection, String>((ref, tripId) {
  return ref.watch(tripCarpoolsRepositoryProvider).watchTripCarpoolSection(tripId);
});

class TripCarpoolsRepository {
  TripCarpoolsRepository({required this.firestore});

  final FirebaseFirestore firestore;
  static const _carpoolDocId = 'carpool';

  DocumentReference<Map<String, dynamic>> _carpoolDocRef(String tripId) {
    return firestore
        .collection('trips')
        .doc(tripId)
        .collection('sections')
        .doc(_carpoolDocId);
  }

  Stream<List<TripCarpool>> watchTripCarpools(String tripId) {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      return Stream.value(const <TripCarpool>[]);
    }

    return _carpoolDocRef(cleanTripId).snapshots().map((snapshot) {
      final section = TripCarpoolSection.fromMap(
        snapshot.data() ?? const <String, dynamic>{},
      );
      final carpools = section.cars
          .map((carData) {
            final carId = (carData['id'] as String? ?? '').trim();
            if (carId.isEmpty) return null;
            return TripCarpool.fromMap(
              id: carId,
              tripId: cleanTripId,
              data: carData,
            );
          })
          .whereType<TripCarpool>()
          .toList(growable: false);
      carpools.sort((a, b) => a.departureAt.compareTo(b.departureAt));
      return carpools;
    });
  }

  Stream<TripCarpoolSection> watchTripCarpoolSection(String tripId) {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      return Stream.value(const TripCarpoolSection());
    }
    return _carpoolDocRef(cleanTripId).snapshots().map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      return TripCarpoolSection.fromMap(data);
    });
  }

  Future<void> upsertTripCarpoolSection({
    required String tripId,
    required String shoppingMeetupLinkUrl,
  }) async {
    final cleanTripId = tripId.trim();
    if (cleanTripId.isEmpty) {
      throw ArgumentError('tripId is required');
    }
    await _carpoolDocRef(cleanTripId).set(<String, dynamic>{
      'shoppingMeetupLinkUrl': shoppingMeetupLinkUrl.trim(),
      'updatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
    }, SetOptions(merge: true));
  }

  Future<void> upsertTripCarpool({
    required String tripId,
    required String? carpoolId,
    required String createdByUserId,
    required String driverUserId,
    required String meetingPointAddress,
    required String nearestTransitStop,
    required DateTime departureAt,
    required int availableSeats,
    required List<String> assignedParticipantIds,
    required bool goesShopping,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanCarpoolId = carpoolId?.trim() ?? '';
    final cleanCreatedByUserId = createdByUserId.trim();
    final cleanDriverUserId = driverUserId.trim();
    final normalizedAssignedIds = <String>{
      ...assignedParticipantIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
      if (cleanDriverUserId.isNotEmpty) cleanDriverUserId,
    }.toList(growable: false);
    if (cleanTripId.isEmpty ||
        cleanCreatedByUserId.isEmpty ||
        cleanDriverUserId.isEmpty) {
      throw ArgumentError('tripId, createdByUserId and driverUserId are required');
    }
    if (availableSeats < 1) {
      throw ArgumentError.value(
        availableSeats,
        'availableSeats',
        'must be at least 1',
      );
    }
    if (normalizedAssignedIds.length > availableSeats) {
      throw ArgumentError(
        'assignedParticipantIds cannot exceed availableSeats',
      );
    }
    final now = DateTime.now().toUtc();
    final targetCarpoolId = cleanCarpoolId.isEmpty
        ? firestore.collection('_').doc().id
        : cleanCarpoolId;
    final sectionRef = _carpoolDocRef(cleanTripId);

    await firestore.runTransaction((tx) async {
      final snapshot = await tx.get(sectionRef);
      final sectionData = snapshot.data() ?? const <String, dynamic>{};
      final existingCars = TripCarpoolSection.fromMap(sectionData).cars;

      final assignedInOtherCars = <String>{};
      for (final car in existingCars) {
        final carId = (car['id'] as String? ?? '').trim();
        if (carId == targetCarpoolId) continue;
        final rawAssigned = (car['assignedParticipantIds'] as List<dynamic>?) ?? const [];
        assignedInOtherCars.addAll(
          rawAssigned.map((entry) => entry.toString().trim()).where((id) => id.isNotEmpty),
        );
      }
      for (final participantId in normalizedAssignedIds) {
        if (assignedInOtherCars.contains(participantId)) {
          throw StateError('Participant already assigned to another carpool.');
        }
      }

      final currentCar = existingCars.cast<Map<String, dynamic>?>().firstWhere(
            (car) => (car?['id'] as String? ?? '').trim() == targetCarpoolId,
            orElse: () => null,
          );
      final createdAt = (currentCar?['createdAt'] as Timestamp?)?.toDate().toUtc() ?? now;
      final existingCreator = (currentCar?['createdByUserId'] as String?)?.trim() ?? '';

      final updatedCar = <String, dynamic>{
        'id': targetCarpoolId,
        'createdByUserId': existingCreator.isNotEmpty
            ? existingCreator
            : cleanCreatedByUserId,
        'driverUserId': cleanDriverUserId,
        'meetingPointAddress': meetingPointAddress.trim(),
        'nearestTransitStop': nearestTransitStop.trim(),
        'departureAt': Timestamp.fromDate(departureAt.toUtc()),
        'availableSeats': availableSeats,
        'assignedParticipantIds': normalizedAssignedIds,
        'goesShopping': goesShopping,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(now),
      };

      final nextCars = existingCars
          .where((car) => (car['id'] as String? ?? '').trim() != targetCarpoolId)
          .toList(growable: true)
        ..add(updatedCar);

      tx.set(
        sectionRef,
        <String, dynamic>{
          'cars': nextCars,
          'updatedAt': Timestamp.fromDate(now),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Moves the signed-in trip member into [targetCarpoolId], removing them from
  /// any other car first (Cloud Function + Admin SDK).
  Future<void> joinTripCarpoolAsSelfAssignedPassenger({
    required String tripId,
    required String targetCarpoolId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanTargetId = targetCarpoolId.trim();
    if (cleanTripId.isEmpty || cleanTargetId.isEmpty) {
      throw ArgumentError('tripId and targetCarpoolId are required');
    }

    final callable = FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion)
        .httpsCallable('joinTripCarpoolAsPassenger');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'targetCarpoolId': cleanTargetId,
    });
  }

  /// Removes the signed-in member from [carpoolId] only when they are not the driver.
  Future<void> leaveTripCarpoolAsSelfAssignedPassenger({
    required String tripId,
    required String carpoolId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanCarpoolId = carpoolId.trim();
    if (cleanTripId.isEmpty || cleanCarpoolId.isEmpty) {
      throw ArgumentError('tripId and carpoolId are required');
    }

    final callable = FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion)
        .httpsCallable('leaveTripCarpoolAsPassenger');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'carpoolId': cleanCarpoolId,
    });
  }

  Future<void> deleteTripCarpool({
    required String tripId,
    required String carpoolId,
  }) async {
    final cleanTripId = tripId.trim();
    final cleanCarpoolId = carpoolId.trim();
    if (cleanTripId.isEmpty || cleanCarpoolId.isEmpty) return;
    final now = DateTime.now().toUtc();
    final sectionRef = _carpoolDocRef(cleanTripId);
    await firestore.runTransaction((tx) async {
      final snapshot = await tx.get(sectionRef);
      final sectionData = snapshot.data() ?? const <String, dynamic>{};
      final cars = TripCarpoolSection.fromMap(sectionData).cars;
      final nextCars = cars
          .where((car) => (car['id'] as String? ?? '').trim() != cleanCarpoolId)
          .toList(growable: false);
      tx.set(
        sectionRef,
        <String, dynamic>{
          'cars': nextCars,
          'updatedAt': Timestamp.fromDate(now),
        },
        SetOptions(merge: true),
      );
    });
  }
}
