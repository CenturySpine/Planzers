import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';

/// Documents sent in one analysis (must match the Cloud Function).
const int walletActivityImportMaxDocuments = 5;

/// Free-text instructions sent with the documents (must match the Cloud
/// Function).
const int walletActivityImportMaxInstructionsLength = 1000;

final walletActivityImportRepositoryProvider =
    Provider<WalletActivityImportRepository>(
  (ref) => WalletActivityImportRepository(
    functions: FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion),
  ),
);

/// Planning activity proposed by the AI from travel documents, not stored
/// until the user keeps it.
class WalletActivityProposal {
  const WalletActivityProposal({
    required this.label,
    required this.category,
    required this.plannedAt,
    required this.durationMinutes,
    required this.address,
    required this.freeComments,
    required this.sourceDocumentIds,
  });

  final String label;
  final TripActivityCategory category;

  /// Local time read from the documents, taken in the device time zone like
  /// a manual entry.
  final DateTime? plannedAt;

  /// Null means the category default applies.
  final int? durationMinutes;
  final String address;
  final String freeComments;
  final List<String> sourceDocumentIds;

  Duration get effectiveDuration =>
      Duration(minutes: durationMinutes ?? category.defaultDurationMinutes);

  factory WalletActivityProposal.fromMap(Map<String, dynamic> map) {
    final plannedAtLocal = (map['plannedAtLocal'] as String?)?.trim() ?? '';
    final duration = map['durationMinutes'];
    return WalletActivityProposal(
      label: (map['label'] as String?)?.trim() ?? '',
      category: TripActivityCategory.fromFirestore(map['category']),
      // No offset in the string: parsed as local time.
      plannedAt:
          plannedAtLocal.isEmpty ? null : DateTime.tryParse(plannedAtLocal),
      durationMinutes: duration is num && duration > 0 ? duration.toInt() : null,
      address: (map['address'] as String?)?.trim() ?? '',
      freeComments: (map['freeComments'] as String?)?.trim() ?? '',
      sourceDocumentIds: ((map['sourceDocumentIds'] as List?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toImportMap() => {
        'label': label,
        'category': category.firestoreValue,
        if (plannedAt != null)
          'plannedAtMillis': plannedAt!.millisecondsSinceEpoch,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'address': address,
        'freeComments': freeComments,
        'sourceDocumentIds': sourceDocumentIds,
      };
}

class WalletActivityImportRepository {
  WalletActivityImportRepository({required this.functions});

  final FirebaseFunctions functions;

  /// Reads the documents with AI; nothing is written.
  Future<List<WalletActivityProposal>> extractProposals({
    required String tripId,
    required List<String> documentIds,
    required String languageCode,
    String instructions = '',
  }) async {
    final result = await functions
        .httpsCallable(
          'extractTripActivitiesFromDocuments',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
        )
        .call<Map<String, dynamic>>({
      'tripId': tripId.trim(),
      'documentIds': documentIds,
      'lang': languageCode == 'en' ? 'en' : 'fr',
      if (instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
    });
    final raw = (result.data['activities'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((m) => WalletActivityProposal.fromMap(Map<String, dynamic>.from(m)))
        .where((p) => p.label.isNotEmpty)
        .toList(growable: false);
  }

  /// Adds the kept proposals to the planning, linked to their documents.
  Future<void> importProposals({
    required String tripId,
    required List<WalletActivityProposal> proposals,
  }) async {
    await functions
        .httpsCallable('importTripActivitiesFromDocuments')
        .call<Map<String, dynamic>>({
      'tripId': tripId.trim(),
      'activities': proposals.map((p) => p.toImportMap()).toList(),
    });
  }
}
