import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripMealCard extends ConsumerWidget {
  const TripMealCard({
    super.key,
    required this.tripId,
    required this.meal,
    required this.memberLabels,
  });

  final String tripId;
  final TripMeal meal;
  final Map<String, String> memberLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dayPartLabel = _dayPartLabel(context, meal.mealDayPart);
    final mealPreviewLabel = _mealPreviewLabel(context, meal);
    final chefId = meal.chefParticipantId?.trim();
    final hasChef =
        meal.mealMode == MealMode.cooked && chefId != null && chefId.isNotEmpty;
    final chefLabel = hasChef ? (memberLabels[chefId] ?? l10n.commonUnknown) : '';
    final participantCount = meal.participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;

    final repasColor = ActivityFilterGroup.repas.filterColor;
    final surface = Theme.of(context).colorScheme.surface;
    final cardBg = Color.lerp(surface, repasColor, 0.08)!;

    return Card(
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      color: cardBg,
      child: InkWell(
        onTap: () => context.push('/trips/$tripId/meals/${meal.id}'),
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: repasColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      _MealModeBadge(mealMode: meal.mealMode),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  meal.mealTimeHHMM,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: repasColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    dayPartLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              mealPreviewLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
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
                                userData: null,
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
                                    color:
                                        Theme.of(context).colorScheme.surface,
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
                        label: Text(participantCount.toString()),
                        child: const Icon(Icons.people_outline),
                      ),
                    ],
                  ),
                ),
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
  final name = meal.restaurantName.trim();
  if (name.isNotEmpty) return name;
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
    final color = ActivityFilterGroup.repas.filterColor;
    return SizedBox(
      width: 18,
      height: 18,
      child: SvgPicture.asset(
        asset,
        width: 18,
        height: 18,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
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
