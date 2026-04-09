import 'package:flutter/material.dart';
import 'package:planzers/app/router.dart';
import 'package:planzers/core/firebase/bootstrap.dart';
import 'package:planzers/core/firebase/firebase_target.dart';

class PlanzersApp extends StatelessWidget {
  const PlanzersApp({required this.firebaseTarget, super.key});

  final FirebaseTarget firebaseTarget;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Planzers',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
      builder: (context, child) {
        return FirebaseBootstrap(
          target: firebaseTarget,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
