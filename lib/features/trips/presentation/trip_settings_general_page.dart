import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripSettingsGeneralPage extends ConsumerStatefulWidget {
  const TripSettingsGeneralPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  ConsumerState<TripSettingsGeneralPage> createState() =>
      _TripSettingsGeneralPageState();
}

class _TripSettingsGeneralPageState extends ConsumerState<TripSettingsGeneralPage> {
  final TextEditingController _linkController = TextEditingController();
  bool _cupidonModeEnabled = true;
  bool _initialized = false;
  bool _isSaving = false;
  String _initialLinkUrl = '';
  bool _initialCupidonModeEnabled = true;

  bool get _hasUnsavedChanges {
    return _linkController.text.trim() != _initialLinkUrl ||
        _cupidonModeEnabled != _initialCupidonModeEnabled;
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _saveGeneralSettings() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(tripsRepositoryProvider).updateTripGeneralSettings(
            tripId: widget.tripId,
            photosStorageUrl: _linkController.text,
            cupidonModeEnabled: _cupidonModeEnabled,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewUpdated)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewUpdateError(error.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.tripSettingsGeneralSectionTitle),
              leading: IconButton(
                onPressed: () => context.go('/trips/${widget.tripId}/settings'),
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.tripBackToTrip,
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.tripNotFoundOrNoAccess,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final currentUserId = FirebaseAuth.instance.currentUser?.uid.trim();
        final currentRole =
            resolveTripPermissionRole(trip: trip, userId: currentUserId);
        final canAccessTripSettings = isTripRoleAllowed(
          currentRole: currentRole,
          minRole: TripPermissionRole.admin,
        );
        if (!canAccessTripSettings) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.tripSettingsGeneralSectionTitle),
              leading: IconButton(
                onPressed: () => context.go('/trips/${widget.tripId}/settings'),
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.tripBackToTrip,
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.tripNotFoundOrNoAccess,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (!_initialized) {
          _initialized = true;
          _linkController.text = trip.photosStorageUrl;
          _cupidonModeEnabled = trip.cupidonModeEnabled;
          _initialLinkUrl = trip.photosStorageUrl.trim();
          _initialCupidonModeEnabled = trip.cupidonModeEnabled;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.tripSettingsGeneralSectionTitle),
            leading: IconButton(
              onPressed: () => context.go('/trips/${widget.tripId}/settings'),
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.tripBackToTrip,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tripSettingsGeneralSectionTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tripSettingsGeneralSectionDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.photo_library_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.tripSettingsGeneralPhotosStorageTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.tripSettingsGeneralPhotosStorageDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _linkController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: l10n.tripSettingsGeneralPhotosStorageFieldLabel,
                          hintText: l10n.tripSettingsGeneralPhotosStorageFieldHint,
                          prefixIcon: const Icon(Icons.link_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SwitchListTile.adaptive(
                    value: _cupidonModeEnabled,
                    onChanged: _isSaving
                        ? null
                        : (enabled) =>
                            setState(() => _cupidonModeEnabled = enabled),
                    secondary: const Icon(Icons.favorite_outline),
                    title: Text(l10n.cupidonModeTitle),
                    subtitle: Text(
                      l10n.tripSettingsGeneralCupidonModeDescription,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_isSaving || !_hasUnsavedChanges)
                          ? null
                          : _saveGeneralSettings,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(l10n.commonSave),
                    ),
                  ),
                ],
              ),
              if (!_hasUnsavedChanges) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.commonUnsaved,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (_hasUnsavedChanges) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.commonUnsavedChangesTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(
          title: Text(l10n.tripSettingsGeneralSectionTitle),
          leading: IconButton(
            onPressed: () => context.go('/trips/${widget.tripId}/settings'),
            icon: const Icon(Icons.arrow_back),
            tooltip: l10n.tripBackToTrip,
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.commonErrorWithDetails(error.toString()),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
