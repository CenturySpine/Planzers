import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/meals/data/meals_repository.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';

class TripMealsPage extends ConsumerWidget {
  const TripMealsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = TripScope.of(context);
    final mealsAsync = ref.watch(tripMealsStreamProvider(trip.id));

    return mealsAsync.when(
      data: (meals) => _MealsList(tripId: trip.id, meals: meals),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erreur: $e', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _MealsList extends StatelessWidget {
  const _MealsList({
    required this.tripId,
    required this.meals,
  });

  final String tripId;
  final List<TripMeal> meals;

  /// Group meals by date key.
  Map<String, List<TripMeal>> _groupMealsByDate() {
    final grouped = <String, List<TripMeal>>{};
    for (final meal in meals) {
      grouped.putIfAbsent(meal.mealDateKey, () => []).add(meal);
    }
    return grouped;
  }

  String _dateKeyToFrenchLabel(String dateKey) {
    final dt = TripMeal(
      id: '',
      name: '',
      mealDateKey: dateKey,
      mealDayPart: TripDayPart.morning,
      participantIds: const [],
      createdBy: '',
      createdAt: DateTime.now(),
    ).mealDateAsDateTime;
    final formatter = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
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
                  'Aucun repas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Appuyez sur + pour planifier un repas.',
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
                    dateLabel: _dateKeyToFrenchLabel(dateKey),
                    meals: mealsForDate,
                    tripId: tripId,
                  );
                },
              );
            },
          ),
        ],
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
  });

  final String dateKey;
  final String dateLabel;
  final List<TripMeal> meals;
  final String tripId;

  @override
  Widget build(BuildContext context) {
    // Already sorted by day part within date, thanks to repository
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
          ...meals.map((meal) => _MealCard(
                tripId: tripId,
                meal: meal,
              )),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.tripId,
    required this.meal,
  });

  final String tripId;
  final TripMeal meal;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => context.push(
          '/trips/$tripId/meals/${meal.id}',
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.name.isEmpty ? 'Sans titre' : meal.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meal.dayPartLabelFr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Badge(
                label: Text(meal.participantCount.toString()),
                child: const Icon(Icons.people_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
