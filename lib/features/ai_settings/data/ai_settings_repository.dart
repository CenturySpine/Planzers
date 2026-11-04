import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/ai_settings/data/ai_settings.dart';

final aiSettingsRepositoryProvider = Provider<AiSettingsRepository>((ref) {
  return AiSettingsRepository(firestore: FirebaseFirestore.instance);
});

/// Live AI settings (defaults while the document does not exist).
final aiSettingsProvider = StreamProvider.autoDispose<AiSettings>(
  (ref) => ref.watch(aiSettingsRepositoryProvider).watch(),
);

/// Reads and writes `system/aiSettings` for the administration. Only
/// application owners can write it (Firestore rules); the AI Cloud Functions
/// read it on each call.
class AiSettingsRepository {
  AiSettingsRepository({required this.firestore});

  final FirebaseFirestore firestore;

  static const String systemDocId = 'aiSettings';

  DocumentReference<Map<String, dynamic>> get _doc =>
      firestore.collection('system').doc(systemDocId);

  Stream<AiSettings> watch() =>
      _doc.snapshots().map((snap) => AiSettings.fromFirestore(snap.data()));

  Future<void> save(AiSettings settings) => _doc.set(settings.toFirestore());
}
