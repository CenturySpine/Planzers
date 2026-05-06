import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/cupidon/data/cupidon_repository.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member_profile_repository.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/trip_member_stay_options_editor.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripMemberPreferencesPage extends ConsumerStatefulWidget {
  const TripMemberPreferencesPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  ConsumerState<TripMemberPreferencesPage> createState() =>
      _TripMemberPreferencesPageState();
}

class _TripMemberPreferencesPageState
    extends ConsumerState<TripMemberPreferencesPage> {
  bool _isSavingCupidon = false;
  bool _isLeavingTrip = false;

  static String _messageForLeaveError(Object error) {
    if (error is FirebaseFunctionsException) {
      final String? message = error.message;
      if (message != null && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return error.toString();
  }

  Future<void> _toggleCupidon({
    required bool enabled,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSavingCupidon) return;
    setState(() => _isSavingCupidon = true);
    try {
      await ref.read(cupidonRepositoryProvider).setMyTripCupidonEnabled(
            tripId: widget.tripId,
            enabled: enabled,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? l10n.cupidonEnabled : l10n.cupidonDisabled),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewCupidonToggleError(e.toString()))),
      );
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _isSavingCupidon = false);
      }
    }
  }

  Future<void> _updateStayLive({
    required TripMemberStay stay,
    required Trip trip,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (!TripMemberStay.isChronological(stay)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripStayInvalidRange)),
      );
      throw Exception('Stay validation failed: not chronological');
    }
    if (!TripMemberStay.withinTripCalendarBounds(stay: stay, trip: trip)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripStayOutOfTripBounds)),
      );
      throw Exception('Stay validation failed: out of trip bounds');
    }
    try {
      await ref.read(tripMemberProfileRepositoryProvider).upsertMyStay(
            tripId: widget.tripId,
            stay: stay,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripStayUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
      rethrow;
    }
  }

  Future<void> _updatePhoneVisibilityLive({
    required TripMemberPhoneVisibility visibility,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref.read(tripMemberProfileRepositoryProvider).setMyPhoneVisibility(
            tripId: widget.tripId,
            visibility: visibility,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripPhoneVisibilityUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripPhoneVisibilityUpdateError(e.toString()))),
      );
      rethrow;
    }
  }

  Future<void> _confirmAndLeaveTrip() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isLeavingTrip) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.tripOverviewLeaveTripTitle),
        content: Text(l10n.tripOverviewLeaveTripDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.tripOverviewLeaveAction),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }

    setState(() => _isLeavingTrip = true);
    try {
      await ref.read(tripsRepositoryProvider).leaveTripAsMember(
            tripId: widget.tripId,
          );
      if (!mounted) return;
      context.go('/trips');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForLeaveError(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _isLeavingTrip = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));
    final stayAsync = ref.watch(tripMemberStayStreamProvider(widget.tripId));
    final myCupidonEnabledAsync =
        ref.watch(myTripCupidonEnabledProvider(widget.tripId));
    final myPhoneNumberAsync = ref.watch(myPhoneNumberProvider);
    final myPhoneVisibilityAsync = ref.watch(tripMemberPhoneVisibilityStreamProvider(widget.tripId));
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.tripUserPreferencesTitle),
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
        final isTripMember = myUid.isNotEmpty && trip.memberIds.contains(myUid);
        final isTripOwner = myUid.isNotEmpty && trip.ownerId.trim() == myUid;
        if (!isTripMember) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.tripUserPreferencesTitle),
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

        final currentStay = stayAsync.asData?.value ?? TripMemberStay.defaultForTrip(trip);
        final myCupidonEnabled = myCupidonEnabledAsync.asData?.value ?? false;
        final myPhoneNumber = myPhoneNumberAsync.asData?.value;
        final currentPhoneVisibility =
            myPhoneVisibilityAsync.asData?.value ?? TripMemberPhoneVisibility.nobody;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.tripUserPreferencesTitle),
            leading: IconButton(
              onPressed: () => context.go('/trips/${widget.tripId}/overview'),
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.tripBackToTrip,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TripMemberStayOptionsEditor(
                mode: TripMemberStayOptionsEditorMode.live,
                tripStartDate: trip.startDate,
                tripEndDate: trip.endDate,
                isCupidonModeEnabled: trip.cupidonModeEnabled,
                initialStay: currentStay,
                initialCupidonEnabled: myCupidonEnabled,
                initialPhoneVisibility:
                    myPhoneNumber == null ? null : currentPhoneVisibility,
                onLiveStayChanged: (value) => _updateStayLive(
                  stay: value,
                  trip: trip,
                ),
                onLiveCupidonChanged: (enabled) =>
                    _toggleCupidon(enabled: enabled),
                cupidonTitle: l10n.cupidonModeTitle,
                onLivePhoneVisibilityChanged: myPhoneNumber == null
                    ? null
                    : (value) => _updatePhoneVisibilityLive(
                          visibility: value,
                        ),
                phoneVisibilityTitle: l10n.tripPhoneVisibilityTitle,
              ),
              if (!isTripOwner) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: _isLeavingTrip ? null : _confirmAndLeaveTrip,
                  child: _isLeavingTrip
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.tripOverviewLeaveTripCardTitle),
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
          title: Text(l10n.tripUserPreferencesTitle),
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
