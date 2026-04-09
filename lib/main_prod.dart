import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/app/app.dart';
import 'package:planzers/core/firebase/firebase_target.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: PlanzersApp(firebaseTarget: FirebaseTarget.prod),
    ),
  );
}
