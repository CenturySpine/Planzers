import 'package:flutter/material.dart';
import 'package:planzers/app/app.dart';
import 'package:planzers/core/firebase/firebase_target.dart';
import 'package:planzers/core/intl/intl_locale_setup.dart';
import 'package:planzers/core/platform/url_strategy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureUrlStrategyIfWeb();
  await initializeAppDateFormatting();
  runApp(const PlanzersApp(firebaseTarget: FirebaseTarget.preview));
}
