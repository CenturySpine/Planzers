import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/trips/presentation/trip_create_page.dart';
import 'package:planerz/l10n/app_localizations.dart';

void main() {
  testWidgets('day trip toggle preserves the previous rooms module choice', (
    tester,
  ) async {
    const dayTripSwitchKey = ValueKey('trip-create-day-trip-switch');
    const roomsModuleSwitchKey = ValueKey('trip-create-rooms-module-switch');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountRepositoryProvider.overrideWithValue(_FakeAccountRepository()),
        ],
        child: const MaterialApp(
          locale: Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TripCreatePage(),
        ),
      ),
    );
    await tester.pump();

    final formScrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(roomsModuleSwitchKey),
      500,
      scrollable: formScrollable,
    );
    await tester.tap(find.byKey(roomsModuleSwitchKey));
    await tester.pumpAndSettle();
    expect(_roomsModuleSwitchToggled(tester), isTrue);

    await tester.scrollUntilVisible(
      find.byKey(dayTripSwitchKey),
      -500,
      scrollable: formScrollable,
    );
    await tester.tap(find.byKey(dayTripSwitchKey));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(roomsModuleSwitchKey),
      500,
      scrollable: formScrollable,
    );
    expect(_roomsModuleSwitchToggled(tester), isFalse);

    await tester.scrollUntilVisible(
      find.byKey(dayTripSwitchKey),
      -500,
      scrollable: formScrollable,
    );
    await tester.tap(find.byKey(dayTripSwitchKey));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(roomsModuleSwitchKey),
      500,
      scrollable: formScrollable,
    );
    expect(_roomsModuleSwitchToggled(tester), isTrue);
  });
}

bool _roomsModuleSwitchToggled(WidgetTester tester) {
  final semantics = tester.widget<Semantics>(
    find.descendant(
      of: find.byKey(const ValueKey('trip-create-rooms-module-switch')),
      matching: find.byType(Semantics),
    ),
  );
  return semantics.properties.toggled ?? false;
}

class _FakeAccountRepository implements AccountRepository {
  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMyUserDocument() {
    return Stream.value(_FakeUserSnapshot());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeUserSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  Map<String, dynamic>? data() {
    return const {
      'account': {'name': 'Bruno'},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
