import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/features/account/data/connected_external_providers_repository.dart';
import 'package:planerz/features/oauth/data/external_connection_repository.dart';
import 'package:planerz/features/trips/data/traveler_modules_repository.dart';
import 'package:planerz/features/trips/presentation/ridgegear_project_picker.dart';
import 'package:planerz/features/trips/presentation/trip_overview_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Real pack weight for a Ridgegear project, in grams — fetched through the
/// generic authenticated proxy (`callExternalProviderApi`), never directly.
final ridgegearProjectWeightProvider =
    FutureProvider.autoDispose.family<int, String>((ref, projectId) async {
  final data = await ref.watch(externalConnectionRepositoryProvider).callProviderApi(
        providerId: kRidgegearProviderId,
        path: '/v1/projects/$projectId/weight',
      );
  return (data['totalWeightGrams'] as num?)?.toInt() ?? 0;
});

String _formatKg(int grams) {
  final kg = grams / 1000;
  return kg.toStringAsFixed(1).replaceAll('.', ',');
}

/// The Ridgegear traveler-module cartouche — mirrors [TripOverviewModuleCard]
/// but owns its own real-data fetching (weight) instead of taking it as a
/// hardcoded parameter, since that fetch is async and provider-specific.
class RidgegearModuleCard extends ConsumerWidget {
  const RidgegearModuleCard({
    super.key,
    required this.tripId,
    required this.ridgegear,
  });

  final String tripId;
  final RidgegearModuleConfig ridgegear;

  /// Not connected yet: tapping the cartouche triggers the OAuth handshake
  /// (if needed) then the project picker — the module itself was already
  /// added to the trip without either of these happening.
  Future<void> _handleConnectAndPick(BuildContext context, WidgetRef ref) async {
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
    final projectId = ridgegear.projectId;

    if (projectId == null || projectId.isEmpty) {
      return TripOverviewModuleCard(
        label: l10n.tripOverviewTileRidgegear,
        icon: Icons.backpack_outlined,
        count: 0,
        showCount: false,
        tileColor: ActivityFilterGroup.loisirs.filterLightBgColor,
        inkColor: ActivityFilterGroup.loisirs.filterInkColor,
        statusText: l10n.ridgegearConnectPrompt,
        trailingIcon: Icons.link,
        onTap: () => _handleConnectAndPick(context, ref),
      );
    }

    final weightAsync = ref.watch(ridgegearProjectWeightProvider(projectId));

    return TripOverviewModuleCard(
      label: l10n.tripOverviewTileRidgegear,
      icon: Icons.backpack_outlined,
      count: 0,
      showCount: false,
      tileColor: ActivityFilterGroup.loisirs.filterLightBgColor,
      inkColor: ActivityFilterGroup.loisirs.filterInkColor,
      statusText: weightAsync.when(
        data: (grams) => l10n.tripOverviewRidgegearPackWeight(_formatKg(grams)),
        loading: () => l10n.ridgegearLoadingWeight,
        error: (error, _) => l10n.commonErrorWithDetails(error.toString()),
      ),
      onTap: () => launchUrl(
        Uri.parse('https://ridgegear.centuryspine.org/projects/$projectId'),
        mode: LaunchMode.platformDefault,
      ),
    );
  }
}
