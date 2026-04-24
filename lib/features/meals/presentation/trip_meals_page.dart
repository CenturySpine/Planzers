import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/meals/data/meal_component_risks.dart';
import 'package:planerz/features/meals/data/meals_repository.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripMealsPage extends ConsumerWidget {
  const TripMealsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = TripScope.of(context);
    final mealsAsync = ref.watch(tripMealsStreamProvider(trip.id));

    return mealsAsync.when(
      data: (meals) => _MealsList(
        tripId: trip.id,
        meals: meals,
        memberPublicLabels: trip.memberPublicLabels,
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
    required this.memberPublicLabels,
  });

  final String tripId;
  final List<TripMeal> meals;
  final Map<String, String> memberPublicLabels;

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
      name: '',
      mealDateKey: dateKey,
      mealDayPart: TripDayPart.morning,
      participantIds: const [],
      createdBy: '',
      createdAt: DateTime.now(),
    ).mealDateAsDateTime;
    final formatter = DateFormat(
      'EEEE d MMMM yyyy',
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
                    memberPublicLabels: memberPublicLabels,
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
    required this.memberPublicLabels,
  });

  final String dateKey;
  final String dateLabel;
  final List<TripMeal> meals;
  final String tripId;
  final Map<String, String> memberPublicLabels;

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
                memberPublicLabels: memberPublicLabels,
              )),
        ],
      ),
    );
  }
}

class _MealCard extends ConsumerWidget {
  const _MealCard({
    required this.tripId,
    required this.meal,
    required this.memberPublicLabels,
  });

  final String tripId;
  final TripMeal meal;
  final Map<String, String> memberPublicLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final chefId = meal.chefParticipantId?.trim();
    final hasChef = chefId != null && chefId.isNotEmpty;
    final chefUsersAsync = hasChef
        ? ref.watch(usersDataByIdsProvider(chefId))
        : const AsyncValue<Map<String, Map<String, dynamic>>>.data({});
    final chefUserData = hasChef ? chefUsersAsync.asData?.value[chefId] : null;
    final chefLabel = hasChef
        ? resolveTripMemberDisplayLabel(
            memberId: chefId,
            userData: chefUserData,
            tripMemberPublicLabels: memberPublicLabels,
            emptyFallback: l10n.roleParticipant,
          )
        : '';

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
                      meal.name.isEmpty
                          ? AppLocalizations.of(context)!.activitiesUntitled
                          : meal.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dayPartLabel(context, meal.mealDayPart),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (hasChef) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      buildProfileBadge(
                        context: context,
                        displayLabel: chefLabel,
                        userData: chefUserData,
                        size: 24,
                      ),
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          width: 12,
                          height: 12,
                          padding: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                          ),
                          child: SvgPicture.asset(
                            'assets/images/chef_hat.svg',
                            width: 10,
                            height: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
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

String _dayPartLabel(BuildContext context, TripDayPart dayPart) {
  final l10n = AppLocalizations.of(context)!;
  return switch (dayPart) {
    TripDayPart.morning => l10n.dayPartMorning,
    TripDayPart.midday => l10n.dayPartMidday,
    TripDayPart.evening => l10n.dayPartEvening,
  };
}
