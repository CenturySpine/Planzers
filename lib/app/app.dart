import 'package:flutter/material.dart';
import 'package:planzers/app/router.dart';
import 'package:planzers/core/firebase/bootstrap.dart';

class PlanzersApp extends StatelessWidget {
  const PlanzersApp({super.key});

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
        return FirebaseBootstrap(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
