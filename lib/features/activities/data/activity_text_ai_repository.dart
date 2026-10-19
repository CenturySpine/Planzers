import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';

/// Free-text description sent for interpretation (must match the Cloud
/// Function).
const int tripActivityTextMaxLength = 1000;

final activityTextAiRepositoryProvider = Provider<ActivityTextAiRepository>(
  (ref) => ActivityTextAiRepository(
    functions: FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion),
  ),
);

/// Activity read by the AI from a free-text description, used to fill the
/// creation form (nothing is stored).
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

  factory TripActivityTextProposal.fromMap(Map<String, dynamic> map) {
    final plannedAtLocal = (map['plannedAtLocal'] as String?)?.trim() ?? '';
    final duration = map['durationMinutes'];
    return TripActivityTextProposal(
      label: (map['label'] as String?)?.trim() ?? '',
      category: TripActivityCategory.fromFirestore(map['category']),
      // No offset in the string: parsed as local time.
      plannedAt:
          plannedAtLocal.isEmpty ? null : DateTime.tryParse(plannedAtLocal),
      durationMinutes: duration is num && duration > 0 ? duration.toInt() : null,
      address: (map['address'] as String?)?.trim() ?? '',
      freeComments: (map['freeComments'] as String?)?.trim() ?? '',
    );
  }
}

class ActivityTextAiRepository {
  ActivityTextAiRepository({required this.functions});

  final FirebaseFunctions functions;

  /// Reads the description with AI; returns null when no activity is
  /// recognised. [categories] are the ones the form offers.
  Future<TripActivityTextProposal?> interpret({
    required String tripId,
    required String text,
    required String languageCode,
    required List<TripActivityCategory> categories,
  }) async {
    final result = await functions
        .httpsCallable('extractTripActivityFromText')
        .call<Map<String, dynamic>>({
      'tripId': tripId.trim(),
      'text': text.trim(),
      'lang': languageCode == 'en' ? 'en' : 'fr',
      'nowLocal': DateFormat("yyyy-MM-dd'T'HH:mm").format(DateTime.now()),
      'categories': categories.map((c) => c.firestoreValue).toList(),
    });
    final raw = result.data['activity'];
    if (raw is! Map) return null;
    final proposal =
        TripActivityTextProposal.fromMap(Map<String, dynamic>.from(raw));
    return proposal.label.isEmpty ? null : proposal;
  }
}
