import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';

/// Free-text account sent for interpretation (must match the Cloud
/// Function).
const int tripActivityTextMaxLength = 3000;

final activityTextAiRepositoryProvider = Provider<ActivityTextAiRepository>(
  (ref) => ActivityTextAiRepository(
    functions: FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion),
  ),
);

/// Activity done read by the AI from a free-text account, reviewed and
/// possibly edited before being added (nothing is stored until then).
class TripActivityTextProposal {
  const TripActivityTextProposal({
    required this.label,
    required this.category,
    required this.plannedAt,
    required this.durationMinutes,
    required this.address,
    required this.freeComments,
  });

  final String label;
  final TripActivityCategory category;

  /// Local time, taken in the device time zone like a manual entry.
  final DateTime? plannedAt;

  /// Null means the category default applies.
  final int? durationMinutes;
  final String address;
  final String freeComments;

  Duration get effectiveDuration =>
      Duration(minutes: durationMinutes ?? category.defaultDurationMinutes);

  factory TripActivityTextProposal.fromMap(Map<String, dynamic> map) {
    final plannedAtLocal = (map['plannedAtLocal'] as String?)?.trim() ?? '';
    final duration = map['durationMinutes'];
    return TripActivityTextProposal(
      label: (map['label'] as String?)?.trim() ?? '',
      category: TripActivityCategory.fromFirestore(map['category']),
      // No offset in the string: parsed as local time.
      plannedAt:
          plannedAtLocal.isEmpty ? null : DateTime.tryParse(plannedAtLocal),
      durationMinutes:
          duration is num && duration > 0 ? duration.toInt() : null,
      address: (map['address'] as String?)?.trim() ?? '',
      freeComments: (map['freeComments'] as String?)?.trim() ?? '',
    );
  }
}

class ActivityTextAiRepository {
  ActivityTextAiRepository({required this.functions});

  final FirebaseFunctions functions;

  /// Reads the account with AI; nothing is written. Chronological.
  Future<List<TripActivityTextProposal>> extractProposals({
    required String tripId,
    required String text,
    required String languageCode,
  }) async {
    final result = await functions
        .httpsCallable(
      'extractTripActivitiesFromText',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
    )
        .call<Map<String, dynamic>>({
      'tripId': tripId.trim(),
      'text': text.trim(),
      'lang': languageCode == 'en' ? 'en' : 'fr',
      'nowLocal': DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now()),
    });
    final raw = (result.data['activities'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((m) =>
            TripActivityTextProposal.fromMap(Map<String, dynamic>.from(m)))
        .where((p) => p.label.isNotEmpty)
        .toList(growable: false);
  }
}
