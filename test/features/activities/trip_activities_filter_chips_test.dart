import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/features/activities/presentation/trip_activities_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';

Widget _app({required double width, required bool withItinerary}) {
  return MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: TripActivitiesFilterChips(
            activeFilters: const {},
            filterLabels: {
              ActivityFilterGroup.repas: 'Repas',
              if (withItinerary) ActivityFilterGroup.nuits: 'Nuits',
              ActivityFilterGroup.loisirs: 'Loisirs',
              if (withItinerary) ActivityFilterGroup.trajets: 'Trajets',
            },
            onToggle: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  // The test font draws every letter as a square, wider than the app's.
  testWidgets('chips that fit share the whole width', (tester) async {
    await tester.pumpWidget(_app(width: 600, withItinerary: false));

    expect(find.byType(ListView), findsNothing);
    final chips = find.byType(TripCategoryFilterChip);
    expect(chips, findsNWidgets(3));
    // From the left padding to the right one.
    expect(tester.getTopLeft(chips.first).dx, moreOrLessEquals(16));
    expect(tester.getTopRight(chips.last).dx, moreOrLessEquals(600 - 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chips that do not fit scroll', (tester) async {
    await tester.pumpWidget(_app(width: 400, withItinerary: true));

    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
