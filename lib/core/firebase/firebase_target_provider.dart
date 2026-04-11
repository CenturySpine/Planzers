import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/core/firebase/firebase_target.dart';

/// Set via [ProviderScope.overrides] in each entrypoint [main_*.dart].
final firebaseTargetProvider = Provider<FirebaseTarget>((ref) {
  throw StateError(
    'firebaseTargetProvider must be overridden (see main_preview / main_prod).',
  );
});
