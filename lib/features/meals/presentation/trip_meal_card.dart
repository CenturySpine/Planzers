import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/neon_palette.dart';
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
          Text(
            meal.mealTimeHHMM,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: repasColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dayPartLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: NeonPalette.deep,
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
                        color: NeonPalette.surface,
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
}

IconData _mealModeIcon(MealMode mealMode) => switch (mealMode) {
      MealMode.cooked => Icons.restaurant_outlined,
      MealMode.restaurant => Icons.storefront_outlined,
      MealMode.potluck => Icons.tapas_outlined,
    };

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

String _dayPartLabel(BuildContext context, TripDayPart dayPart) {
  final l10n = AppLocalizations.of(context)!;
  return switch (dayPart) {
    TripDayPart.morning => l10n.dayPartMorning,
    TripDayPart.midday => l10n.dayPartMidday,
    TripDayPart.evening => l10n.dayPartEvening,
  };
}
