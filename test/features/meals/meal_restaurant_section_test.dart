import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/meals/presentation/meal_restaurant_section.dart';
import 'package:planerz/l10n/app_localizations.dart';

TripActivity _activity(
  String id,
  String label, {
  TripActivityCategory category = TripActivityCategory.restaurant,
  List<String> votes = const [],
}) {
  return TripActivity(
    id: id,
    label: label,
    category: category,
    linkUrl: '',
    address: '',
    freeComments: '',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
    votes: votes,
  );
}

final _activities = [
  _activity('r1', 'Chez Paul'),
  _activity('r2', 'La Mer', votes: ['u1', 'u2']),
  _activity('v1', 'Musée', category: TripActivityCategory.museum),
];

Future<void> _pump(
  WidgetTester tester, {
  String restaurantActivityId = '',
  bool canChoose = true,
  bool canCreateRestaurant = true,
  void Function(String id, String name)? onChosen,
  VoidCallback? onRemoved,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripActivitiesStreamProvider('t1')
            .overrideWith((ref) => Stream.value(_activities)),
      ],
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MealRestaurantSection(
            tripId: 't1',
            restaurantActivityId: restaurantActivityId,
            memberLabels: const {},
            canChoose: canChoose,
            canCreateRestaurant: canCreateRestaurant,
            busy: false,
            onChosen: onChosen ?? (_, __) {},
            onRemoved: onRemoved ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('chooses a restaurant from the sheet, most voted first',
      (tester) async {
    String? chosenId;
    String? chosenName;
    await _pump(
      tester,
      onChosen: (id, name) {
        chosenId = id;
        chosenName = name;
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choisir un restaurant'));
    await tester.pumpAndSettle();

    expect(find.text('Nouveau restaurant'), findsOneWidget);
    expect(find.text('Musée'), findsNothing);
    expect(
      tester.getTopLeft(find.text('La Mer')).dy,
      lessThan(tester.getTopLeft(find.text('Chez Paul')).dy),
    );

    await tester.tap(find.text('Chez Paul'));
    await tester.pumpAndSettle();

    expect(chosenId, 'r1');
    expect(chosenName, 'Chez Paul');
  });

  testWidgets('shows the chosen restaurant with change and remove',
      (tester) async {
    var removed = false;
    await _pump(
      tester,
      restaurantActivityId: 'r2',
      onRemoved: () => removed = true,
    );
    await tester.pumpAndSettle();

    expect(find.text('La Mer'), findsOneWidget);
    expect(find.text('Changer'), findsOneWidget);

    await tester.tap(find.text('Retirer'));
    expect(removed, isTrue);
  });

  testWidgets('shows a deleted restaurant as not chosen', (tester) async {
    await _pump(tester, restaurantActivityId: 'gone');
    await tester.pumpAndSettle();

    expect(find.text('Choisir un restaurant'), findsOneWidget);
  });

  testWidgets('only shows the choice to members who may not change it',
      (tester) async {
    await _pump(tester, restaurantActivityId: 'r2', canChoose: false);
    await tester.pumpAndSettle();

    expect(find.text('La Mer'), findsOneWidget);
    expect(find.text('Changer'), findsNothing);
    expect(find.text('Retirer'), findsNothing);

    await _pump(tester, canChoose: false);
    await tester.pumpAndSettle();

    expect(find.text('Restaurant à choisir'), findsOneWidget);
    expect(find.text('Choisir un restaurant'), findsNothing);
  });
}
