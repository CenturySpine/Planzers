import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/presentation/trip_activities_ui.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripMealCard extends ConsumerWidget {
  const TripMealCard({
    super.key,
    required this.tripId,
    required this.meal,
    required this.memberLabels,
    this.showTime = true,
  });

  final String tripId;
  final TripMeal meal;
  final Map<String, String> memberLabels;

  /// False when the time is already shown outside the card (agenda gutter).
  final bool showTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dayPartLabel = _dayPartLabel(context, meal.mealDayPart);
    final mealPreviewLabel = switch (meal.mealMode) {
      MealMode.cooked => _cookedMealPreviewLabel(meal, l10n),
      MealMode.potluck => l10n.mealModePotluckLabel,
      MealMode.restaurant =>
        _restaurantName(ref) ?? l10n.mealRestaurantToChoose,
    };
    final chefId = meal.chefParticipantId?.trim();
    final hasChef =
        meal.mealMode == MealMode.cooked && chefId != null && chefId.isNotEmpty;
    final chefLabel =
        hasChef ? (memberLabels[chefId] ?? l10n.commonUnknown) : '';
    final participants =
        ref.watch(tripParticipantsStreamProvider(tripId)).asData?.value ?? [];
    final chefIsChild =
        hasChef && participants.any((m) => m.id == chefId && m.isChild);
    final participantCount = meal.participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;

    final repasGroup = ActivityFilterGroup.repas;
    final repasColor = repasGroup.filterColor;
    final repasLightBg = repasGroup.filterLightBgColor;
    final repasInk = repasGroup.filterInkColor;

    return TripPlanningListCardShell(
      categoryColor: repasColor,
      categoryLightBg: repasLightBg,
      leadingIcon: _mealModeIcon(meal.mealMode),
      subtitle: mealPreviewLabel,
      subtitleItalic: false,
      onTap: () => context.push('/trips/$tripId/meals/${meal.id}'),
      titleRow: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (showTime) ...[
            Text(
              meal.mealTimeHHMM,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTokens.deep,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              dayPartLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTokens.deep,
              ),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                    isChild: chefIsChild,
                  ),
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      width: 12,
                      height: 12,
                      padding: const EdgeInsets.all(1),
                      decoration: const BoxDecoration(
                        color: AppTokens.surface,
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
            const SizedBox(width: 8),
          ],
          TripPlanningParticipantCountPill(
            count: participantCount,
            categoryLightBg: repasLightBg,
            categoryInk: repasInk,
          ),
        ],
      ),
    );
  }

  /// Current name of the chosen restaurant, or null when none is chosen (or
  /// it was deleted). The name saved with the meal covers the loading time.
  String? _restaurantName(WidgetRef ref) {
    final activityId = meal.restaurantActivityId.trim();
    if (activityId.isEmpty) return null;
    final activities =
        ref.watch(tripActivitiesStreamProvider(tripId)).asData?.value;
    if (activities == null) {
      final savedName = meal.restaurantName.trim();
      return savedName.isEmpty ? null : savedName;
    }
    final restaurant = activities.where((a) => a.id == activityId).firstOrNull;
    if (restaurant == null) return null;
    return restaurant.label.trim();
  }
}

IconData _mealModeIcon(MealMode mealMode) => switch (mealMode) {
      MealMode.cooked => PhosphorIconsRegular.forkKnife,
      MealMode.restaurant => PhosphorIconsRegular.storefront,
      MealMode.potluck => PhosphorIconsRegular.bowlFood,
    };

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

String _dayPartLabel(BuildContext context, TripDayPart dayPart) {
  final l10n = AppLocalizations.of(context)!;
  return switch (dayPart) {
    TripDayPart.morning => l10n.dayPartMorning,
    TripDayPart.midday => l10n.dayPartMidday,
    TripDayPart.evening => l10n.dayPartEvening,
  };
}
