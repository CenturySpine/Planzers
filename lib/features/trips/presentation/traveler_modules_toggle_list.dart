import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/account/data/connected_external_providers_repository.dart';
import 'package:planerz/features/oauth/data/external_connection_repository.dart';
import 'package:planerz/features/trips/data/traveler_modules_repository.dart';
import 'package:planerz/features/trips/presentation/ridgegear_project_picker.dart';
import 'package:planerz/features/trips/presentation/trip_stay_form_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Shared "add/remove my personal modules" list, used both from the trip
/// overview "+" bottom sheet and from the trip preferences screen. Any
/// participant can toggle these for themselves, independent of the
/// trip-wide module configuration set by the trip admin.
class TravelerModulesToggleList extends ConsumerWidget {
  const TravelerModulesToggleList({super.key, required this.tripId});

  final String tripId;

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

    // A cached provider value (myConnectedExternalProvidersStreamProvider)
    // can still be empty right after this sheet opens, before its first
    // snapshot arrives — race the toggle against a fresh one-shot read
    // instead of trusting whatever's cached at this exact moment.
    final connected = await ref
        .read(connectedExternalProvidersRepositoryProvider)
        .watchMyConnectedProviders()
        .first;
    final isConnected =
        connected.any((c) => c.providerId == kRidgegearProviderId);

    if (isConnected) {
      if (context.mounted) {
        await showRidgegearProjectPicker(context, tripId: tripId);
      }
      return;
    }

    // Not connected yet: trigger the OAuth handshake inline, tagged with a
    // resumeContext so the callback lands straight back on this trip's
    // project picker instead of the generic connected-apps screen.
    final redirectUri = '${Uri.base.origin}/external/callback';
    final authorizeUrl =
        await ref.read(externalConnectionRepositoryProvider).beginConnection(
              providerId: kRidgegearProviderId,
              redirectUri: redirectUri,
              resumeContext: {'tripId': tripId, 'module': kRidgegearProviderId},
            );
    if (authorizeUrl.isEmpty) return;
    await launchUrl(
      Uri.parse(authorizeUrl),
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_self',
    );
  }

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
          value: modules.walletEnabled,
          onChanged: (value) => repository.setWalletEnabled(
            tripId: tripId,
            enabled: value,
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
