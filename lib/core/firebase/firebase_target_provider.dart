import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_target.dart';

/// Set via [ProviderScope] overrides in [PlanerzApp].
final firebaseTargetProvider = Provider<FirebaseTarget>((ref) {
  throw StateError(
    'firebaseTargetProvider must be overridden (see PlanerzApp).',
  );
});
