import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:planzers/core/firebase/firebase_options_selector.dart';
import 'package:planzers/core/firebase/firebase_target.dart';
import 'package:planzers/core/push/fcm_notification_link_binder.dart';

class FirebaseBootstrap extends StatefulWidget {
  const FirebaseBootstrap(
      {required this.target, required this.child, super.key});

  final FirebaseTarget target;
  final Widget child;

  @override
  State<FirebaseBootstrap> createState() => _FirebaseBootstrapState();
}

class _FirebaseBootstrapState extends State<FirebaseBootstrap> {
  late final Future<FirebaseApp> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initializeFirebase();
  }

  Future<FirebaseApp> _initializeFirebase() async {
    final options = firebaseOptionsFor(widget.target);
    final alreadyInitialized =
        Firebase.apps.where((app) => app.name == defaultFirebaseAppName);
    if (alreadyInitialized.isNotEmpty) {
      final existing = alreadyInitialized.first;

      final sameProject = existing.options.projectId == options.projectId;
      final sameAppId = existing.options.appId == options.appId;
      if (sameProject && sameAppId) {
        return existing;
      }

      // Android can auto-init with google-services.json before Flutter starts.
      // If that app targets another Firebase project/flavor, force re-init
      // with the explicit flavor options passed to this bootstrap.
      await existing.delete();
    }

    try {
      return await Firebase.initializeApp(
        options: options,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'duplicate-app') {
        return Firebase.app();
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Firebase non configure.\n'
                  'Verifie la configuration ${widget.target.name} '
                  '(`flutterfire configure`) puis relance l app.\n\n'
                  'Erreur: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return FcmNotificationLinkBinder(child: widget.child);
      },
    );
  }
}
