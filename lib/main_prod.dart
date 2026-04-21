import 'package:flutter/material.dart';
import 'package:planerz/app/app.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/intl/intl_locale_setup.dart';
import 'package:planerz/core/platform/url_strategy.dart';
import 'package:planerz/core/push/fcm_background_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategyIfWeb();
  configureFcmBackgroundHandling();
  await initializeAppDateFormatting();
  runApp(const PlanzersApp(firebaseTarget: FirebaseTarget.prod));
}
