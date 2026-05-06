import 'dart:async';

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
  static const _carpoolShoppingMeetupDocId = 'carpoolShoppingMeetup';

  DocumentReference<Map<String, dynamic>> _carpoolDocRef(String tripId) {
    return firestore
        .collection('trips')
        .doc(tripId)
        .collection('sections')
        .doc(_carpoolDocId);
  }

  DocumentReference<Map<String, dynamic>> _carpoolShoppingMeetupDocRef(
    String tripId,
  ) {
    return firestore
        .collection('trips')
        .doc(tripId)
        .collection('sections')
        .doc(_carpoolShoppingMeetupDocId);
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
    return Stream.multi((controller) {
      Map<String, dynamic> latestCarpoolData = const <String, dynamic>{};
      Map<String, dynamic> latestShoppingMeetupData = const <String, dynamic>{};
      var hasCarpoolSnapshot = false;
      var hasShoppingMeetupSnapshot = false;

      void emitSectionIfReady() {
        if (!hasCarpoolSnapshot || !hasShoppingMeetupSnapshot) {
          return;
        }

        final shoppingMeetupLinkUrl = _resolvedShoppingMeetupLinkUrl(
          latestCarpoolData,
          latestShoppingMeetupData,
        );
        final shoppingMeetupLinkPreview = _resolvedShoppingMeetupLinkPreview(
          latestCarpoolData,
          latestShoppingMeetupData,
        );
        final cars = _resolvedCars(latestCarpoolData);

        controller.add(
          TripCarpoolSection(
            shoppingMeetupLinkUrl: shoppingMeetupLinkUrl,
            shoppingMeetupLinkPreview: shoppingMeetupLinkPreview,
            cars: cars,
          ),
        );
      }

      final carpoolSubscription = _carpoolDocRef(cleanTripId).snapshots().listen(
        (snapshot) {
          latestCarpoolData = snapshot.data() ?? const <String, dynamic>{};
          hasCarpoolSnapshot = true;
          emitSectionIfReady();
        },
        onError: controller.addError,
      );

      final shoppingMeetupSubscription = _carpoolShoppingMeetupDocRef(cleanTripId)
          .snapshots()
          .listen(
            (snapshot) {
              latestShoppingMeetupData =
                  snapshot.data() ?? const <String, dynamic>{};
              hasShoppingMeetupSnapshot = true;
              emitSectionIfReady();
            },
            onError: controller.addError,
          );

      controller.onCancel = () async {
        await carpoolSubscription.cancel();
        await shoppingMeetupSubscription.cancel();
      };
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
    await _carpoolShoppingMeetupDocRef(cleanTripId).set(<String, dynamic>{
      'shoppingMeetupLinkUrl': shoppingMeetupLinkUrl.trim(),
      'updatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
    }, SetOptions(merge: true));
  }

  Future<void> upsertTripCarpool({
    required String tripId,
    required String? carpoolId,
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
    final cleanDriverUserId = driverUserId.trim();
    final normalizedAssignedIds = <String>{
      ...assignedParticipantIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
      if (cleanDriverUserId.isNotEmpty) cleanDriverUserId,
    }.toList(growable: false);
    if (cleanTripId.isEmpty || cleanDriverUserId.isEmpty) {
      throw ArgumentError('tripId and driverUserId are required');
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
    final callable = FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion)
        .httpsCallable('upsertTripCarpool');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'carpoolId': cleanCarpoolId.isEmpty ? null : cleanCarpoolId,
      'driverUserId': cleanDriverUserId,
      'meetingPointAddress': meetingPointAddress.trim(),
      'nearestTransitStop': nearestTransitStop.trim(),
      'departureAtMillis': departureAt.toUtc().millisecondsSinceEpoch,
      'availableSeats': availableSeats,
      'assignedParticipantIds': normalizedAssignedIds,
      'goesShopping': goesShopping,
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
    final callable = FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion)
        .httpsCallable('deleteTripCarpool');
    await callable.call(<String, dynamic>{
      'tripId': cleanTripId,
      'carpoolId': cleanCarpoolId,
    });
  }
}

String _resolvedShoppingMeetupLinkUrl(
  Map<String, dynamic> carpoolData,
  Map<String, dynamic> shoppingMeetupData,
) {
  final shoppingMeetupValue =
      (shoppingMeetupData['shoppingMeetupLinkUrl'] as String? ?? '').trim();
  if (shoppingMeetupValue.isNotEmpty) {
    return shoppingMeetupValue;
  }
  return (carpoolData['shoppingMeetupLinkUrl'] as String? ?? '').trim();
}

Map<String, dynamic> _resolvedShoppingMeetupLinkPreview(
  Map<String, dynamic> carpoolData,
  Map<String, dynamic> shoppingMeetupData,
) {
  final shoppingMeetupPreview = shoppingMeetupData['shoppingMeetupLinkPreview'];
  if (shoppingMeetupPreview is Map<String, dynamic>) {
    return shoppingMeetupPreview;
  }
  final fallbackPreview = carpoolData['shoppingMeetupLinkPreview'];
  if (fallbackPreview is Map<String, dynamic>) {
    return fallbackPreview;
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _resolvedCars(Map<String, dynamic> carpoolData) {
  return ((carpoolData['cars'] as List<dynamic>?) ?? const <dynamic>[])
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}
