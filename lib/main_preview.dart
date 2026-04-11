import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/app/app.dart';
import 'package:planzers/core/firebase/firebase_target.dart';
import 'package:planzers/core/firebase/firebase_target_provider.dart';
import 'package:planzers/core/intl/intl_locale_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeAppDateFormatting();
  runApp(
    ProviderScope(
      overrides: [
        firebaseTargetProvider.overrideWithValue(FirebaseTarget.preview),
      ],
      child: const PlanzersApp(firebaseTarget: FirebaseTarget.preview),
    ),
  );
}
