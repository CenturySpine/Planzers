import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/meals/data/meals_repository.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
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
    final participants =
        ref.watch(tripParticipantsStreamProvider(trip.id)).asData?.value ?? [];
    final memberLabels = <String, String>{
      for (final m in participants) ...<String, String>{
        m.id: m.participantName,
        if (m.userId != null) m.userId!: m.participantName,
      },
    };

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
              final sortedDateKeys = grouped.keys.toList()..sort();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 88),
                itemCount: sortedDateKeys.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Text(
              dateLabel,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          ...meals.map((meal) => TripMealCard(
                tripId: tripId,
                meal: meal,
                memberLabels: memberLabels,
              )),
        ],
      ),
    );
  }
}
