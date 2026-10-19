import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';

final adminTripActivitiesRepositoryProvider =
    Provider<AdminTripActivitiesRepository>(
  (ref) => AdminTripActivitiesRepository(
    functions: FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion),
  ),
);

/// A trip and how many activities it holds.
class AdminTripActivityCount {
  const AdminTripActivityCount({
    required this.tripId,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.activityCount,
  });

  final String tripId;
  final String title;

  /// `YYYY-MM-DD`, empty when unknown.
  final String startDate;
  final String endDate;
  final int activityCount;

  factory AdminTripActivityCount.fromMap(Map<dynamic, dynamic> map) {
    final count = map['activityCount'];
    return AdminTripActivityCount(
      tripId: (map['tripId'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      startDate: (map['startDate'] as String?) ?? '',
      endDate: (map['endDate'] as String?) ?? '',
      activityCount: count is num ? count.toInt() : 0,
    );
  }
}

/// Administration-only: deletes all the activities of a trip and the links
/// pointing to them (travel documents, meal restaurants).
class AdminTripActivitiesRepository {
  AdminTripActivitiesRepository({required this.functions});

  final FirebaseFunctions functions;

  /// Every trip, most recent start first.
  Future<List<AdminTripActivityCount>> listTrips() async {
    final result =
        await functions.httpsCallable('adminListTripActivityCounts').call();
    final trips = ((result.data as Map)['trips'] as List?) ?? const [];
    return trips
        .whereType<Map>()
        .map(AdminTripActivityCount.fromMap)
        .toList(growable: false);
  }

  /// Returns the number of deleted activities. Refused by the server when
  /// the trip no longer holds [expectedActivityCount] activities.
  Future<int> deleteActivities({
    required String tripId,
    required int expectedActivityCount,
  }) async {
    final result = await functions
        .httpsCallable(
      'adminDeleteTripActivities',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    )
        .call<Map<String, dynamic>>({
      'tripId': tripId,
      'expectedActivityCount': expectedActivityCount,
    });
    final deleted = result.data['deletedCount'];
    return deleted is num ? deleted.toInt() : 0;
  }
}
