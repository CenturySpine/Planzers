import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/data/traveler_modules_repository.dart';
import 'package:planerz/features/trips/presentation/trip_stay_form_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Shared "add/remove my personal modules" list, used both from the trip
/// overview "+" bottom sheet and from the trip preferences screen. Any
/// participant can toggle these for themselves, independent of the
/// trip-wide module configuration set by the trip admin.
class TravelerModulesToggleList extends ConsumerWidget {
  const TravelerModulesToggleList({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final modules =
        ref.watch(myTravelerModulesStreamProvider(tripId)).asData?.value ??
            const TravelerModules();
    final repository = ref.read(travelerModulesRepositoryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TravelerModuleToggleRow(
          icon: Icons.backpack_outlined,
          iconColor: ActivityFilterGroup.loisirs.filterInkColor,
          iconBackground: ActivityFilterGroup.loisirs.filterLightBgColor,
          label: l10n.tripTravelerModulesRidgegearLabel,
          value: modules.ridgegearEnabled,
          onChanged: (value) => repository.setModuleEnabled(
            tripId: tripId,
            ridgegearEnabled: value,
          ),
        ),
        const SizedBox(height: 10),
        _TravelerModuleToggleRow(
          icon: Icons.folder_special_outlined,
          iconColor: ActivityFilterGroup.trajets.filterInkColor,
          iconBackground: ActivityFilterGroup.trajets.filterLightBgColor,
          label: l10n.tripTravelerModulesWalletLabel,
          value: modules.walletEnabled,
          onChanged: (value) => repository.setModuleEnabled(
            tripId: tripId,
            walletEnabled: value,
          ),
        ),
      ],
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
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

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
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: NeonPalette.deep,
                ),
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
