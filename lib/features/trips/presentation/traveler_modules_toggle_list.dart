import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/packing/data/packing_repository.dart';
import 'package:planerz/features/trips/data/traveler_modules_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/ridgegear_project_picker.dart';
import 'package:planerz/features/trips/presentation/trip_stay_form_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Shared "add/remove modules" list, used both from the trip overview "+"
/// bottom sheet and from the trip preferences screen.
///
/// The "personal" modules (Ridgegear, personal documents) can be toggled by
/// any participant for themselves, independent of the trip-wide module
/// configuration. When [showGenericModules] and [canManageGenericModules]
/// are both true, the list also exposes the trip-wide "generic" modules
/// (carpool, rooms, games) so an organiser can switch them on/off inline.
class TravelerModulesToggleList extends ConsumerWidget {
  const TravelerModulesToggleList({
    super.key,
    required this.tripId,
    this.showGenericModules = false,
    this.canManageGenericModules = false,
  });

  final String tripId;
  final bool showGenericModules;
  final bool canManageGenericModules;

  Future<void> _handleRidgegearToggle(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final repository = ref.read(travelerModulesRepositoryProvider);
    if (!value) {
      await repository.disableRidgegear(tripId);
      return;
    }

    // Adding the module just enables it in the trip — connecting to
    // Ridgegear and picking a project happens later, on demand, when the
    // traveler taps the module cartouche on the trip overview.
    await repository.setRidgegearEnabled(tripId: tripId, enabled: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final modules =
        ref.watch(myTravelerModulesStreamProvider(tripId)).asData?.value ??
            const TravelerModules();
    final packingParticipantId =
        ref.watch(myPackingParticipantIdProvider(tripId));
    final packingVisible = ref
            .watch(myPackingListConfigStreamProvider(tripId))
            .asData
            ?.value
            .isVisible ??
        false;
    final repository = ref.read(travelerModulesRepositoryProvider);
    final tripsRepository = ref.read(tripsRepositoryProvider);
    final trip = ref.watch(tripStreamProvider(tripId)).asData?.value;

    final showGenericSection =
        showGenericModules && canManageGenericModules && trip != null;
    final showGroupHeaders = showGenericSection;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showGroupHeaders) ...[
          _ModuleGroupHeader(
            label: l10n.tripTravelerModulesPersonalGroupLabel,
          ),
          const SizedBox(height: 10),
        ],
        _TravelerModuleToggleRow(
          icon: Icons.backpack_outlined,
          iconColor: ActivityFilterGroup.loisirs.filterInkColor,
          iconBackground: ActivityFilterGroup.loisirs.filterLightBgColor,
          label: l10n.tripTravelerModulesRidgegearLabel,
          description: l10n.tripTravelerModulesRidgegearSubtitle,
          subtitle: modules.ridgegear.enabled
              ? modules.ridgegear.projectName
              : null,
          value: modules.ridgegear.enabled,
          onChanged: (value) => _handleRidgegearToggle(context, ref, value),
          onSubtitleTap: modules.ridgegear.enabled
              ? () => showRidgegearProjectPicker(context, tripId: tripId)
              : null,
          subtitleActionLabel: l10n.ridgegearChangeProject,
        ),
        const SizedBox(height: 10),
        _TravelerModuleToggleRow(
          icon: Icons.folder_special_outlined,
          iconColor: ActivityFilterGroup.trajets.filterInkColor,
          iconBackground: ActivityFilterGroup.trajets.filterLightBgColor,
          label: l10n.tripTravelerModulesWalletLabel,
          description: l10n.tripTravelerModulesWalletSubtitle,
          value: modules.walletEnabled,
          onChanged: (value) => repository.setWalletEnabled(
            tripId: tripId,
            enabled: value,
          ),
        ),
        if (packingParticipantId != null) ...[
          const SizedBox(height: 10),
          _TravelerModuleToggleRow(
            icon: Icons.luggage_outlined,
            iconColor: ActivityFilterGroup.nuits.filterInkColor,
            iconBackground: ActivityFilterGroup.nuits.filterLightBgColor,
            label: l10n.tripTravelerModulesPackingLabel,
            description: l10n.tripTravelerModulesPackingSubtitle,
            value: packingVisible,
            onChanged: (value) => ref
                .read(packingRepositoryProvider)
                .setEnabled(
                  tripId: tripId,
                  participantId: packingParticipantId,
                  enabled: value,
                ),
          ),
        ],
        if (showGenericSection) ...[
          const SizedBox(height: 18),
          _ModuleGroupHeader(
            label: l10n.tripTravelerModulesGenericGroupLabel,
          ),
          const SizedBox(height: 10),
          _TravelerModuleToggleRow(
            icon: Icons.directions_car_outlined,
            iconColor: ActivityFilterGroup.trajets.filterInkColor,
            iconBackground: ActivityFilterGroup.trajets.filterLightBgColor,
            label: l10n.tripOverviewTileCarpool,
            description: l10n.tripCreateModuleCarpoolSubtitle,
            value: trip.carpoolModuleEnabled,
            onChanged: (value) => tripsRepository.setTripModuleEnabled(
              tripId: tripId,
              module: TripGenericModule.carpool,
              enabled: value,
            ),
          ),
          if (!trip.isDayTrip) ...[
            const SizedBox(height: 10),
            _TravelerModuleToggleRow(
              icon: Icons.king_bed_outlined,
              iconColor: ActivityFilterGroup.nuits.filterInkColor,
              iconBackground: ActivityFilterGroup.nuits.filterLightBgColor,
              label: l10n.tripOverviewTileRooms,
              description: l10n.tripCreateModuleRoomsSubtitle,
              value: trip.roomsModuleEnabled,
              onChanged: (value) => tripsRepository.setTripModuleEnabled(
                tripId: tripId,
                module: TripGenericModule.rooms,
                enabled: value,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _TravelerModuleToggleRow(
            icon: Icons.casino_outlined,
            iconColor: ActivityFilterGroup.loisirs.filterInkColor,
            iconBackground: ActivityFilterGroup.loisirs.filterLightBgColor,
            label: l10n.tripOverviewTileGames,
            description: l10n.tripCreateModuleGamesSubtitle,
            value: trip.gamesModuleEnabled,
            onChanged: (value) => tripsRepository.setTripModuleEnabled(
              tripId: tripId,
              module: TripGenericModule.games,
              enabled: value,
            ),
          ),
        ],
      ],
    );
  }
}

class _ModuleGroupHeader extends StatelessWidget {
  const _ModuleGroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: NeonPalette.text700,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _TravelerModuleToggleRow extends StatelessWidget {
  const _TravelerModuleToggleRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.subtitle,
    this.onSubtitleTap,
    this.subtitleActionLabel,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Short static explanation of what the module does, shown under the
  /// label — mirrors the module list on the trip create/edit screen.
  final String? description;
  final String? subtitle;
  final VoidCallback? onSubtitleTap;
  final String? subtitleActionLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NeonPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NeonPalette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: NeonPalette.deep,
                    ),
                  ),
                  if (description != null && description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description!,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: NeonPalette.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    GestureDetector(
                      onTap: onSubtitleTap,
                      child: Text(
                        onSubtitleTap != null
                            ? '${subtitle!} · ${subtitleActionLabel ?? ''}'
                            : subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: onSubtitleTap != null
                              ? NeonPalette.primary
                              : NeonPalette.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TripNeonSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
