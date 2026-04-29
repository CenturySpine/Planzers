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
      mealDateKey: dateKey,
      mealDayPart: TripDayPart.morning,
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
    final dayPartLabel = _dayPartLabel(context, meal.mealDayPart);
    final mealPreviewLabel = _mealPreviewLabel(context, meal);
    final chefId = meal.chefParticipantId?.trim();
    final hasChef =
        meal.mealMode == MealMode.cooked && chefId != null && chefId.isNotEmpty;
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
              _MealModeBadge(mealMode: meal.mealMode),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayPartLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        mealPreviewLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
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
                const SizedBox(width: 12),
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

String _mealPreviewLabel(BuildContext context, TripMeal meal) {
  final l10n = AppLocalizations.of(context)!;
  return switch (meal.mealMode) {
    MealMode.cooked => _cookedMealPreviewLabel(meal, l10n),
    MealMode.potluck => l10n.mealModePotluckLabel,
    MealMode.restaurant => _restaurantMealPreviewLabel(meal, l10n),
  };
}

String _cookedMealPreviewLabel(TripMeal meal, AppLocalizations l10n) {
  final componentTitles = meal.components
      .map((component) => component.title.trim())
      .where((title) => title.isNotEmpty)
      .toList(growable: false);
  if (componentTitles.isEmpty) {
    return l10n.mealModeCookedLabel;
  }
  return componentTitles.join(' • ');
}

String _restaurantMealPreviewLabel(TripMeal meal, AppLocalizations l10n) {
  final previewTitle =
      (meal.restaurantLinkPreview['title'] as String? ?? '').trim();
  if (previewTitle.isNotEmpty) {
    return previewTitle;
  }
  final restaurantUrl = meal.restaurantUrl.trim();
  if (restaurantUrl.isNotEmpty) {
    return restaurantUrl;
  }
  return l10n.mealModeRestaurantLabel;
}

class _MealModeBadge extends StatelessWidget {
  const _MealModeBadge({required this.mealMode});

  final MealMode mealMode;

  @override
  Widget build(BuildContext context) {
    final asset = switch (mealMode) {
      MealMode.cooked => 'assets/images/chef_hat.svg',
      MealMode.restaurant => 'assets/images/hand_meal.svg',
      MealMode.potluck => 'assets/images/tapas.svg',
    };
    return SizedBox(
      width: 18,
      height: 18,
      child: SvgPicture.asset(
        asset,
        width: 18,
        height: 18,
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
