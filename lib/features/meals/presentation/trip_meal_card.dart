import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/meals/data/meal_component_risks.dart';
import 'package:planerz/features/meals/data/trip_meal.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripMealCard extends ConsumerWidget {
  const TripMealCard({
    super.key,
    required this.tripId,
    required this.meal,
    required this.memberPublicLabels,
    required this.tripMemberIds,
  });

  final String tripId;
  final TripMeal meal;
  final Map<String, String> memberPublicLabels;
  final Set<String> tripMemberIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid.trim();
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
            currentUserId: currentUserId,
            emptyFallback: l10n.commonUnknown,
          )
        : '';
    final participantCount = meal.participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && tripMemberIds.contains(id))
        .toSet()
        .length;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => context.push('/trips/$tripId/meals/${meal.id}'),
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
                label: Text(participantCount.toString()),
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
