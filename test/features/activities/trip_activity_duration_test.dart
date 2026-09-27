import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activities_ui.dart';
import 'package:planerz/features/activities/presentation/trip_activity_duration.dart';
import 'package:planerz/l10n/app_localizations.dart';

TripActivity _activity({
  TripActivityCategory category = TripActivityCategory.visit,
  DateTime? plannedAt,
  int? durationMinutes,
}) {
  return TripActivity(
    id: 'a',
    label: 'Activité',
    category: category,
    linkUrl: '',
    address: '',
    freeComments: '',
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
    plannedAt: plannedAt,
    durationMinutes: durationMinutes,
  );
}

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('default durations', () {
    test('a night for accommodation, two hours otherwise', () {
      expect(
        _activity(category: TripActivityCategory.accommodation)
            .effectiveDuration,
        const Duration(hours: 8),
      );
      expect(
        _activity(category: TripActivityCategory.transport).effectiveDuration,
        const Duration(hours: 2),
      );
      expect(
        _activity(category: TripActivityCategory.museum).effectiveDuration,
        const Duration(hours: 2),
      );
    });

    test('custom duration wins over the default', () {
      final activity = _activity(
        category: TripActivityCategory.accommodation,
        plannedAt: DateTime(2026, 7, 1, 10),
        durationMinutes: 90,
      );
      expect(activity.plannedEndAt, DateTime(2026, 7, 1, 11, 30));
    });
  });

  testWidgets('formats durations and end times', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      captured = context;
      return const SizedBox();
    })));
    final l10n = AppLocalizations.of(captured)!;
    expect(formatTripActivityDuration(const Duration(hours: 2), l10n), '2 h');
    expect(
      formatTripActivityDuration(const Duration(minutes: 90), l10n),
      '1 h 30',
    );
    expect(
      formatTripActivityDuration(const Duration(minutes: 45), l10n),
      '45 min',
    );

    final night = tripActivityEndTime(
      captured,
      _activity(
        category: TripActivityCategory.accommodation,
        plannedAt: DateTime(2026, 7, 1, 22),
      ),
    );
    expect(night?.time, '06:00');
    expect(night?.dayOffset, 1);
    expect(tripActivityEndTime(captured, _activity()), isNull);
  });

  testWidgets('timeline row shows start and end times', (tester) async {
    await tester.pumpWidget(_app(const TripAgendaTimelineRow(
      timeLabel: '22:00',
      endTimeLabel: '06:00',
      endDayOffset: 1,
      color: Colors.teal,
      isFirst: true,
      isLast: true,
      child: SizedBox(height: 80),
    )));
    expect(find.text('22:00'), findsOneWidget);
    expect(find.textContaining('06:00'), findsOneWidget);
    expect(find.textContaining('+1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
