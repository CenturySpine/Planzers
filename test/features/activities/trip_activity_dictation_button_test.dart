import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/activities/presentation/trip_activity_dictation_button.dart';
import 'package:planerz/l10n/app_localizations.dart';

void main() {
  testWidgets('shows the dictation button on mobile without asking anything',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TripActivityDictationButton(
            controller: controller,
            maxLength: 1000,
            onListeningChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Dicter'), findsOneWidget);
  });
}
