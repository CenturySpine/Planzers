import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/meals/data/meals_repository.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/activities/presentation/trip_activities_ui.dart';
import 'package:planerz/features/meals/presentation/trip_meal_card.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripMealsPage extends ConsumerWidget {
  const TripMealsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = TripScope.of(context);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid.trim();
    final canCreateMeal = canCreateMealForTrip(
      trip: trip,
      userId: currentUserId,
    );
    final mealsAsync = ref.watch(tripMealsStreamProvider(trip.id));
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(trip.id));

    return mealsAsync.when(
      data: (meals) => _MealsList(
        tripId: trip.id,
        meals: meals,
        memberLabels: memberLabels,
        canCreateMeal: canCreateMeal,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppLocalizations.of(context)!.commonErrorWithDetails(e.toString()),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _MealsList extends StatelessWidget {
  const _MealsList({
    required this.tripId,
    required this.meals,
    required this.memberLabels,
    required this.canCreateMeal,
  });

  final String tripId;
  final List<TripMeal> meals;
  final Map<String, String> memberLabels;
  final bool canCreateMeal;

  /// Group meals by date key.
  Map<String, List<TripMeal>> _groupMealsByDate() {
    final grouped = <String, List<TripMeal>>{};
    for (final meal in meals) {
      grouped.putIfAbsent(meal.mealDateKey, () => []).add(meal);
    }
    return grouped;
  }

  String _dateKeyToLabel(BuildContext context, String dateKey) {
    final dt = TripMeal(
      id: '',
      mealDateKey: dateKey,
      mealDayPart: TripDayPart.morning,
      mealTimeHHMM: TripMeal.defaultTimeHHMMForDayPart(TripDayPart.morning),
      participantIds: const [],
      createdBy: '',
      createdAt: DateTime.now(),
    ).mealDateAsDateTime;
    final formatter = DateFormat.yMMMMEEEEd(
      Localizations.localeOf(context).toString(),
    );
    return formatter.format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (meals.isEmpty)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.restaurant_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.mealsNoMeal,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.mealsPressPlusToPlan,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          )
        else ...[
          Builder(
            builder: (context) {
              final grouped = _groupMealsByDate();
              final trip = TripScope.of(context);
              final dayKeys = <String>{...grouped.keys};
              final start = trip.startDate;
              final end = trip.endDate;
              if (start != null &&
                  end != null &&
                  !end.isBefore(start) &&
                  end.difference(start).inDays <= 60) {
                for (var d = DateUtils.dateOnly(start);
                    !d.isAfter(DateUtils.dateOnly(end));
                    d = d.add(const Duration(days: 1))) {
                  dayKeys.add(DateFormat('yyyy-MM-dd').format(d));
                }
              }
              final sortedDateKeys = dayKeys.toList()..sort();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 88),
                itemCount: sortedDateKeys.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final dateKey = sortedDateKeys[index];
                  final mealsForDate = grouped[dateKey] ?? [];
                  return _MealDateSection(
                    dateKey: dateKey,
                    dateLabel: _dateKeyToLabel(context, dateKey),
                    meals: mealsForDate,
                    tripId: tripId,
                    memberLabels: memberLabels,
                  );
                },
              );
            },
          ),
        ],
        if (canCreateMeal)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'add_meal',
              onPressed: () => context.push(
                '/trips/$tripId/meals/new',
              ),
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}

/// One day of the meal board: a slot per day part (morning / midday /
/// evening). Empty slots stay visible so missing meals stand out.
class _MealDateSection extends StatelessWidget {
  const _MealDateSection({
    required this.dateKey,
    required this.dateLabel,
    required this.meals,
    required this.tripId,
    required this.memberLabels,
  });

  final String dateKey;
  final String dateLabel;
  final List<TripMeal> meals;
  final String tripId;
  final Map<String, String> memberLabels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String partLabel(TripDayPart part) => switch (part) {
          TripDayPart.morning => l10n.dayPartMorning,
          TripDayPart.midday => l10n.dayPartMidday,
          TripDayPart.evening => l10n.dayPartEvening,
        };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TripActivityDaySeparatorRail(label: dateLabel),
          ),
          for (final part in TripDayPart.values) ...[
            if (meals.any((m) => m.mealDayPart == part))
              for (final meal in meals.where((m) => m.mealDayPart == part))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TripMealCard(
                    tripId: tripId,
                    meal: meal,
                    memberLabels: memberLabels,
                  ),
                )
            else
              _EmptyMealSlot(label: partLabel(part)),
          ],
        ],
      ),
    );
  }
}

class _EmptyMealSlot extends StatelessWidget {
  const _EmptyMealSlot({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(
            Icons.restaurant_rounded,
            size: 16,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const Spacer(),
          Text(
            AppLocalizations.of(context)!.commonDash,
            style: TextStyle(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
