import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/app/preview_environment_chrome.dart';
import 'package:planzers/app/router.dart';
import 'package:planzers/core/firebase/bootstrap.dart';
import 'package:planzers/core/firebase/firebase_target.dart';
import 'package:planzers/core/firebase/firebase_target_provider.dart';

class PlanzersApp extends StatelessWidget {
  const PlanzersApp({required this.firebaseTarget, super.key});

  final FirebaseTarget firebaseTarget;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        firebaseTargetProvider.overrideWithValue(firebaseTarget),
      ],
      child: MaterialApp.router(
        title: firebaseTarget.isPreview ? 'Planzers · Preview' : 'Planzers',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        routerConfig: appRouter,
        builder: (context, child) {
          return FirebaseBootstrap(
            target: firebaseTarget,
            child: PreviewEnvironmentChrome(
              target: firebaseTarget,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}
