import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_card.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Restaurant of a meal at the restaurant: the chosen one, which can be
/// changed or removed, or a button to choose one among the trip's
/// restaurants (or a new one).
class MealRestaurantSection extends ConsumerWidget {
  const MealRestaurantSection({
    super.key,
    required this.tripId,
    required this.restaurantActivityId,
    required this.memberLabels,
    required this.canChoose,
    required this.canCreateRestaurant,
    required this.busy,
    required this.onChosen,
    required this.onRemoved,
  });

  final String tripId;
  final String restaurantActivityId;
  final Map<String, String> memberLabels;

  /// Whether the user may choose, change or remove the restaurant.
  final bool canChoose;

  /// Whether the user may add a restaurant to the trip.
  final bool canCreateRestaurant;
  final bool busy;
  final void Function(String activityId, String restaurantName) onChosen;
  final VoidCallback onRemoved;

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    List<TripActivity> activities,
  ) async {
    final restaurants = activities
        .where((a) => a.category == TripActivityCategory.restaurant)
        .toList()
      ..sort((a, b) {
        final byVotes = b.votes.length.compareTo(a.votes.length);
        if (byVotes != 0) return byVotes;
        return a.displayLabel
            .toLowerCase()
            .compareTo(b.displayLabel.toLowerCase());
      });
    final pick = await _showRestaurantPicker(
      context,
      restaurants: restaurants,
      chosenId: restaurantActivityId.trim(),
      canCreateRestaurant: canCreateRestaurant,
    );
    if (pick == null || !context.mounted) return;
    final picked = pick.activity;
    if (picked != null) {
      onChosen(picked.id, picked.displayLabel);
      return;
    }
    final newId = await context.push<String>(
      '/trips/$tripId/activities/new?initialCategory='
      '${TripActivityCategory.restaurant.firestoreValue}',
    );
    if (newId == null || !context.mounted) return;
    final created = ref
        .read(tripActivitiesStreamProvider(tripId))
        .asData
        ?.value
        .where((a) => a.id == newId)
        .firstOrNull;
    onChosen(newId, created?.displayLabel ?? '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return ref.watch(tripActivitiesStreamProvider(tripId)).when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(l10n.commonErrorWithDetails(e.toString())),
          data: (activities) {
            final chosenId = restaurantActivityId.trim();
            // A deleted restaurant shows as not chosen.
            final chosen = chosenId.isEmpty
                ? null
                : activities.where((a) => a.id == chosenId).firstOrNull;
            if (chosen == null) {
              if (!canChoose) {
                return Text(
                  l10n.mealRestaurantToChoose,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                );
              }
              return OutlinedButton.icon(
                onPressed:
                    busy ? null : () => _choose(context, ref, activities),
                icon: const Icon(PhosphorIconsRegular.storefront),
                label: Text(l10n.mealRestaurantChoose),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TripActivityCard(
                  tripId: tripId,
                  activity: chosen,
                  tripMemberPublicLabels: memberLabels,
                ),
                if (canChoose)
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => _choose(context, ref, activities),
                        icon: const Icon(PhosphorIconsRegular.arrowsLeftRight),
                        label: Text(l10n.mealRestaurantChange),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : onRemoved,
                        icon: const Icon(PhosphorIconsRegular.x),
                        label: Text(l10n.mealRestaurantRemove),
                      ),
                    ],
                  ),
              ],
            );
          },
        );
  }
}

/// What the restaurant picker was closed with: a restaurant of the trip, or
/// none to create a new one.
class _RestaurantPick {
  const _RestaurantPick(this.activity);

  final TripActivity? activity;
}

Future<_RestaurantPick?> _showRestaurantPicker(
  BuildContext context, {
  required List<TripActivity> restaurants,
  required String chosenId,
  required bool canCreateRestaurant,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<_RestaurantPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              l10n.mealRestaurantChoose,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (canCreateRestaurant)
            ListTile(
              leading: const _RestaurantAvatar(icon: PhosphorIconsRegular.plus),
              title: Text(l10n.mealRestaurantNew),
              onTap: () =>
                  Navigator.of(sheetContext).pop(const _RestaurantPick(null)),
            ),
          if (restaurants.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.mealRestaurantPickerEmpty),
            ),
          for (final restaurant in restaurants)
            _RestaurantPickerTile(
              restaurant: restaurant,
              chosen: restaurant.id == chosenId,
              onTap: () =>
                  Navigator.of(sheetContext).pop(_RestaurantPick(restaurant)),
            ),
        ],
      ),
    ),
  );
}

/// One restaurant of the picker, with its vote count so the group's
/// favourite stands out.
class _RestaurantPickerTile extends StatelessWidget {
  const _RestaurantPickerTile({
    required this.restaurant,
    required this.chosen,
    required this.onTap,
  });

  final TripActivity restaurant;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final label = restaurant.displayLabel;
    final address = restaurant.address.trim();
    final imageUrl =
        ((restaurant.linkPreview['imageUrl'] as String?) ?? '').trim();
    final votes = restaurant.votes.length;
    return ListTile(
      selected: chosen,
      leading: imageUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              child: LinkPreviewThumbnail(
                preview: restaurant.linkPreview,
                size: 36,
              ),
            )
          : _RestaurantAvatar(
              icon: TripActivityCategory.restaurant.categoryIcon,
            ),
      title: Text(
        label.isEmpty ? l10n.activitiesUntitled : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: address.isEmpty
          ? null
          : Text(address, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (votes > 0) ...[
            Icon(
              PhosphorIconsRegular.thumbsUp,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              '$votes',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
          if (chosen) ...[
            const SizedBox(width: 12),
            Icon(PhosphorIconsFill.checkCircle, color: colorScheme.primary),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

class _RestaurantAvatar extends StatelessWidget {
  const _RestaurantAvatar({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final group = ActivityFilterGroup.repas;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: group.filterLightBgColor,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Icon(icon, size: 20, color: group.filterColor),
    );
  }
}
