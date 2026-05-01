import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';

TripMeal _meal({
  required String id,
  required String dateKey,
  required TripDayPart part,
}) {
  return TripMeal(
    id: id,
    mealDateKey: dateKey,
    mealDayPart: part,
    participantIds: const [],
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  test('sortedChronological sorts by date then day part', () {
    final meals = [
      _meal(id: 'c', dateKey: '2026-08-10', part: TripDayPart.evening),
      _meal(id: 'a', dateKey: '2026-08-09', part: TripDayPart.midday),
      _meal(id: 'b', dateKey: '2026-08-10', part: TripDayPart.morning),
    ];

    final sorted = TripMeal.sortedChronological(meals);
    expect(sorted.map((m) => m.id).toList(), ['a', 'b', 'c']);
  });

  test('mealDateAsDateTime parses valid date key', () {
    final meal = _meal(
      id: 'x',
      dateKey: '2026-08-09',
      part: TripDayPart.midday,
    );
    final parsed = meal.mealDateAsDateTime;
    expect(parsed.year, 2026);
    expect(parsed.month, 8);
    expect(parsed.day, 9);
  });
}
