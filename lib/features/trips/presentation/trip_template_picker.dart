import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/trips/data/trip_templates.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// The kinds of trip to start from, one card each: its title and tagline,
/// then, once chosen, what it offers and the modules it switches on.
class TripTemplatePicker extends StatelessWidget {
  const TripTemplatePicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TripTemplate? selected;
  final ValueChanged<TripTemplate> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            l10n.tripTemplateSectionLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTokens.text700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        for (final template in TripTemplate.values) ...[
          _TripTemplateCard(
            template: template,
            selected: template == selected,
            onTap: () => onSelected(template),
          ),
          const SizedBox(height: 10),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                PhosphorIconsRegular.info,
                size: 14,
                color: AppTokens.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.tripTemplateFooter,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppTokens.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the card of a [TripTemplate] shows.
extension TripTemplatePresentation on TripTemplate {
  IconData get icon => switch (this) {
        TripTemplate.friendsStay => PhosphorIconsRegular.house,
        TripTemplate.roadTrip => PhosphorIconsRegular.signpost,
        TripTemplate.guidedTrip => PhosphorIconsRegular.flag,
        TripTemplate.dayOuting => PhosphorIconsRegular.sun,
      };

  String title(AppLocalizations l10n) => switch (this) {
        TripTemplate.friendsStay => l10n.tripTemplateFriendsStayTitle,
        TripTemplate.roadTrip => l10n.tripTemplateRoadTripTitle,
        TripTemplate.guidedTrip => l10n.tripTemplateGuidedTripTitle,
        TripTemplate.dayOuting => l10n.tripTemplateDayOutingTitle,
      };

  String tagline(AppLocalizations l10n) => switch (this) {
        TripTemplate.friendsStay => l10n.tripTemplateFriendsStayTagline,
        TripTemplate.roadTrip => l10n.tripTemplateRoadTripTagline,
        TripTemplate.guidedTrip => l10n.tripTemplateGuidedTripTagline,
        TripTemplate.dayOuting => l10n.tripTemplateDayOutingTagline,
      };

  List<String> points(AppLocalizations l10n) => switch (this) {
        TripTemplate.friendsStay => [
            l10n.tripTemplateFriendsStayPoint1,
            l10n.tripTemplateFriendsStayPoint2,
            l10n.tripTemplateFriendsStayPoint3,
            l10n.tripTemplateFriendsStayPoint4,
          ],
        TripTemplate.roadTrip => [
            l10n.tripTemplateRoadTripPoint1,
            l10n.tripTemplateRoadTripPoint2,
            l10n.tripTemplateRoadTripPoint3,
            l10n.tripTemplateRoadTripPoint4,
          ],
        TripTemplate.guidedTrip => [
            l10n.tripTemplateGuidedTripPoint1,
            l10n.tripTemplateGuidedTripPoint2,
            l10n.tripTemplateGuidedTripPoint3,
            l10n.tripTemplateGuidedTripPoint4,
            l10n.tripTemplateGuidedTripPoint5,
          ],
        TripTemplate.dayOuting => [
            l10n.tripTemplateDayOutingPoint1,
            l10n.tripTemplateDayOutingPoint2,
            l10n.tripTemplateDayOutingPoint3,
            l10n.tripTemplateDayOutingPoint4,
          ],
      };

  /// The optional modules the template switches on, with their icons.
  List<({IconData icon, String label})> modules(AppLocalizations l10n) {
    final s = settings;
    return [
      if (s.journeyModuleEnabled)
        (
          icon: PhosphorIconsRegular.mapTrifold,
          label: l10n.tripModuleJourneyLabel,
        ),
      if (s.homeMealsModuleEnabled)
        (
          icon: PhosphorIconsRegular.cookingPot,
          label: l10n.tripModuleHomeMealsLabel,
        ),
      if (s.shoppingModuleEnabled)
        (
          icon: PhosphorIconsRegular.shoppingCartSimple,
          label: l10n.tripTabShopping,
        ),
      if (s.roomsModuleEnabled)
        (icon: PhosphorIconsRegular.bed, label: l10n.tripOverviewTileRooms),
      if (s.carpoolModuleEnabled)
        (icon: PhosphorIconsRegular.car, label: l10n.tripOverviewTileCarpool),
      if (s.gamesModuleEnabled)
        (
          icon: PhosphorIconsRegular.diceFive,
          label: l10n.tripOverviewTileGames,
        ),
    ];
  }
}

class _TripTemplateCard extends StatelessWidget {
  const _TripTemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final TripTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppTokens.dayTripBackgroundActive : AppTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AppTokens.dayTripBorderActive : AppTokens.divider,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTokens.dayTripIconBackgroundActive
                            : AppTokens.dayTripIconBackgroundRest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          template.icon,
                          size: 20,
                          color: selected
                              ? AppTokens.primary
                              : AppTokens.dayTripIconColorRest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            template.title(l10n),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.deep,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            template.tagline(l10n),
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                              color: AppTokens.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      selected
                          ? PhosphorIconsFill.checkCircle
                          : PhosphorIconsRegular.circle,
                      size: 22,
                      color: selected ? AppTokens.primary : AppTokens.outline,
                    ),
                  ],
                ),
                if (selected) ...[
                  const SizedBox(height: 12),
                  for (final point in template.points(l10n))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              PhosphorIconsRegular.check,
                              size: 14,
                              color: AppTokens.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              point,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: AppTokens.text700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final module in template.modules(l10n))
                        _TripTemplateModulePill(
                          icon: module.icon,
                          label: module.label,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TripTemplateModulePill extends StatelessWidget {
  const _TripTemplateModulePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTokens.dayTripBorderActive),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTokens.primary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTokens.deep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
