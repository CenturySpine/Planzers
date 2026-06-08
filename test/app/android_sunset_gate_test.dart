import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/app/android_sunset_gate.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/l10n/app_localizations.dart';

Widget _wrap(Widget child, {FirebaseTarget target = FirebaseTarget.preview}) {
  return ProviderScope(
    overrides: [
      firebaseTargetProvider.overrideWithValue(target),
    ],
    child: MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  testWidgets(
    'AndroidSunsetGate shows sunset screen and hides child on Android',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          AndroidSunsetGate(
            isAndroidCheck: () => true,
            child: const Scaffold(body: Text('child content')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text("L'application Android n'est plus disponible"), findsOneWidget);
      expect(find.text('child content'), findsNothing);
    },
  );

  testWidgets(
    'AndroidSunsetGate passes through child on non-Android',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          AndroidSunsetGate(
            isAndroidCheck: () => false,
            child: const Scaffold(body: Text('child content')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('child content'), findsOneWidget);
      expect(find.text("L'application Android n'est plus disponible"), findsNothing);
    },
  );
}
