import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/cupidon/data/cupidon_repository.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/trip_member_stay_options_editor.dart';
import 'package:planerz/features/trips/presentation/trip_participant_name_editor.dart';
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
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final myParticipant =
          ref.read(myTripMemberStreamProvider(widget.tripId)).asData?.value;
      if (myParticipant == null) throw StateError('Participant introuvable');
      await ref.read(tripMembersRepositoryProvider).updateParticipantProfile(
            tripId: widget.tripId,
            participantId: myParticipant.id,
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

  Future<void> _saveParticipantName(
    TripParticipantNameDialogResult result,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final myParticipant =
        ref.read(myTripMemberStreamProvider(widget.tripId)).asData?.value;
    if (myParticipant == null) throw StateError('Participant introuvable');
    if (result.name.isEmpty && !result.useProfileName) return;
    try {
      await ref.read(tripsRepositoryProvider).updateTripParticipantName(
            tripId: widget.tripId,
            participantId: myParticipant.id,
            participantName: result.name,
            useProfileName: result.useProfileName,
            isChild: result.isChild,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripParticipantsNameUpdated)),
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
      final myParticipant =
          ref.read(myTripMemberStreamProvider(widget.tripId)).asData?.value;
      if (myParticipant == null) throw StateError('Participant introuvable');
      await ref.read(tripMembersRepositoryProvider).updateParticipantProfile(
            tripId: widget.tripId,
            participantId: myParticipant.id,
            phoneVisibility: visibility,
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
    final myParticipantAsync = ref.watch(myTripMemberStreamProvider(widget.tripId));
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
        final isTripMember = myUid.isNotEmpty && trip.memberUserIds.contains(myUid);
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

        final myParticipant = myParticipantAsync.asData?.value;
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
              if (myParticipant != null)
                StreamBuilder(
                  stream: ref
                      .read(accountRepositoryProvider)
                      .watchMyUserDocument(),
                  builder: (context, snapshot) {
                    final profileName =
                        profileNameFromData(snapshot.data?.data());
                    return TripParticipantNameEditor(
                      key: ValueKey(
                        '${myParticipant.id}_'
                        '${myParticipant.participantName}_'
                        '${myParticipant.useProfileName}_'
                        '${myParticipant.isChild}',
                      ),
                      initialName: myParticipant.participantName,
                      initialUseProfileName: myParticipant.useProfileName,
                      initialIsChild: myParticipant.isChild,
                      isClaimed: true,
                      profileName: profileName,
                      onSave: _saveParticipantName,
                    );
                  },
                ),
              if (myParticipant != null) const SizedBox(height: 12),
              TripMemberStayOptionsEditor(
                mode: TripMemberStayOptionsEditorMode.live,
                tripStartDate: trip.startDate,
                tripEndDate: trip.endDate,
                trip: trip,
                showStayDates: !trip.isDayTrip,
                isCupidonModeEnabled: trip.cupidonModeEnabled,
                initialStay: currentStay,
                initialCupidonEnabled: myCupidonEnabled,
                initialPhoneVisibility:
                    myPhoneNumber == null ? null : currentPhoneVisibility,
                onLiveStayChanged: trip.isDayTrip
                    ? null
                    : (value) => _updateStayLive(stay: value),
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
