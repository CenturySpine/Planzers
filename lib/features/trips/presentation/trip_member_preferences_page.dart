import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
      return;
    }
    if (!TripMemberStay.withinTripCalendarBounds(stay: stay, trip: trip)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripStayOutOfTripBounds)),
      );
      return;
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TripMemberStayOptionsEditor(
                        mode: TripMemberStayOptionsEditorMode.live,
                        tripStartDate: trip.startDate,
                        tripEndDate: trip.endDate,
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
                        cupidonTitle: myCupidonEnabled
                            ? l10n.cupidonDisableAction
                            : l10n.cupidonEnableAction,
                        onLivePhoneVisibilityChanged: myPhoneNumber == null
                            ? null
                            : (value) => _updatePhoneVisibilityLive(
                                  visibility: value,
                                ),
                        phoneVisibilityTitle: myPhoneNumber == null
                            ? null
                            : l10n.tripPhoneVisibilityTitle,
                      ),
                    ],
                  ),
                ),
              ),
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
