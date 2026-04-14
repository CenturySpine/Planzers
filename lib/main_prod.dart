import 'package:flutter/material.dart';
import 'package:planzers/app/app.dart';
import 'package:planzers/core/firebase/firebase_target.dart';
import 'package:planzers/core/intl/intl_locale_setup.dart';
import 'package:planzers/core/platform/url_strategy.dart';
import 'package:planzers/core/push/fcm_background_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategyIfWeb();
  configureFcmBackgroundHandling();
  await initializeAppDateFormatting();
  runApp(const PlanzersApp(firebaseTarget: FirebaseTarget.prod));
}
