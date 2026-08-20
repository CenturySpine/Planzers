import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/cupidon/data/cupidon_repository.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/invite_join_widgets.dart';
import 'package:planerz/features/trips/presentation/trip_create_creator_name_dialog.dart';
import 'package:planerz/features/trips/presentation/trip_member_preferences_ui.dart';
import 'package:planerz/features/trips/presentation/trip_member_stay_options_editor.dart';
import 'package:planerz/features/trips/presentation/traveler_modules_toggle_list.dart';
import 'package:planerz/features/trips/presentation/trip_participant_name_dialog.dart';
import 'package:planerz/features/trips/presentation/trip_stay_form_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

class _PreferencesSnapshot {
  const _PreferencesSnapshot({
    required this.stay,
    required this.cupidonEnabled,
    required this.phoneVisibility,
    required this.name,
  });

  final TripMemberStay stay;
  final bool cupidonEnabled;
  final TripMemberPhoneVisibility? phoneVisibility;
  final TripParticipantNameDialogResult name;

  bool equalsDraft({
    required TripMemberStay stay,
    required bool cupidonEnabled,
    required TripMemberPhoneVisibility? phoneVisibility,
    required TripParticipantNameDialogResult name,
  }) {
    return this.stay == stay &&
        this.cupidonEnabled == cupidonEnabled &&
        this.phoneVisibility == phoneVisibility &&
        this.name.name == name.name &&
        this.name.useProfileName == name.useProfileName &&
        this.name.isChild == name.isChild;
  }
}

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
  bool _isLeavingTrip = false;
  bool _isSaving = false;
  bool _draftReady = false;

  TripMemberStay? _stayDraft;
  bool _cupidonDraft = false;
  TripMemberPhoneVisibility? _phoneVisibilityDraft;
  TripParticipantNameDialogResult? _nameDraft;
  _PreferencesSnapshot? _savedSnapshot;

  static String _messageForLeaveError(Object error) {
    if (error is FirebaseFunctionsException) {
      final String? message = error.message;
      if (message != null && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return error.toString();
  }

  bool get _dirty {
    final snapshot = _savedSnapshot;
    final name = _nameDraft;
    final stay = _stayDraft;
    if (!_draftReady || snapshot == null || name == null || stay == null) {
      return false;
    }
    return !snapshot.equalsDraft(
      stay: stay,
      cupidonEnabled: _cupidonDraft,
      phoneVisibility: _phoneVisibilityDraft,
      name: name,
    );
  }

  void _seedDraftIfNeeded({
    required TripMemberStay stay,
    required bool cupidonEnabled,
    required TripMemberPhoneVisibility? phoneVisibility,
    required TripParticipantNameDialogResult name,
  }) {
    if (_draftReady) return;
    _stayDraft = stay;
    _cupidonDraft = cupidonEnabled;
    _phoneVisibilityDraft = phoneVisibility;
    _nameDraft = name;
    _savedSnapshot = _PreferencesSnapshot(
      stay: stay,
      cupidonEnabled: cupidonEnabled,
      phoneVisibility: phoneVisibility,
      name: name,
    );
    _draftReady = true;
  }

  Future<void> _openNameDialog({required String? profileName}) async {
    final current = _nameDraft;
    if (current == null) return;
    final result = await showTripCreateCreatorNameDialog(
      context: context,
      initialCustomName: current.useProfileName ? '' : current.name,
      initialUseProfileName: current.useProfileName,
      profileName: profileName,
    );
    if (!mounted || result == null) return;
    setState(() {
      _nameDraft = TripParticipantNameDialogResult(
        name: result.name,
        useProfileName: result.useProfileName,
        isChild: current.isChild,
      );
    });
  }

  Future<void> _saveAll() async {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = _savedSnapshot;
    final stay = _stayDraft;
    final name = _nameDraft;
    if (!_dirty || _isSaving || snapshot == null || stay == null || name == null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final myParticipant =
          ref.read(myTripMemberStreamProvider(widget.tripId)).asData?.value;
      if (myParticipant == null) throw StateError('Participant introuvable');

      final futures = <Future<void>>[];

      if (snapshot.stay != stay) {
        futures.add(
          ref.read(tripMembersRepositoryProvider).updateParticipantProfile(
                tripId: widget.tripId,
                participantId: myParticipant.id,
                stay: stay,
              ),
        );
      }

      if (snapshot.cupidonEnabled != _cupidonDraft) {
        futures.add(
          ref.read(cupidonRepositoryProvider).setMyTripCupidonEnabled(
                tripId: widget.tripId,
                enabled: _cupidonDraft,
              ),
        );
      }

      if (snapshot.phoneVisibility != _phoneVisibilityDraft &&
          _phoneVisibilityDraft != null) {
        futures.add(
          ref.read(tripMembersRepositoryProvider).updateParticipantProfile(
                tripId: widget.tripId,
                participantId: myParticipant.id,
                phoneVisibility: _phoneVisibilityDraft,
              ),
        );
      }

      final nameChanged = snapshot.name.name != name.name ||
          snapshot.name.useProfileName != name.useProfileName ||
          snapshot.name.isChild != name.isChild;
      if (nameChanged) {
        if (name.name.isEmpty && !name.useProfileName) {
          throw StateError('Nom invalide');
        }
        futures.add(
          ref.read(tripsRepositoryProvider).updateTripParticipantName(
                tripId: widget.tripId,
                participantId: myParticipant.id,
                participantName: name.name,
                useProfileName: name.useProfileName,
                isChild: name.isChild,
              ),
        );
      }

      await Future.wait(futures);

      if (!mounted) return;
      setState(() {
        _savedSnapshot = _PreferencesSnapshot(
          stay: stay,
          cupidonEnabled: _cupidonDraft,
          phoneVisibility: _phoneVisibilityDraft,
          name: name,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripUserPreferencesSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
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

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n) {
    return AppBar(
      toolbarHeight: 52,
      title: Text(l10n.tripUserPreferencesTitle),
      leading: IconButton(
        onPressed: () => context.go('/trips/${widget.tripId}/overview'),
        icon: const Icon(Icons.arrow_back),
        tooltip: l10n.tripBackToTrip,
      ),
    );
  }

  Widget _buildScaffold({
    required AppLocalizations l10n,
    required Widget body,
    Widget? bottomBar,
  }) {
    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        appBar: _buildAppBar(l10n),
        body: body,
        bottomNavigationBar: bottomBar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));
    final stayAsync = ref.watch(tripMemberStayStreamProvider(widget.tripId));
    final myCupidonEnabledAsync =
        ref.watch(myTripCupidonEnabledProvider(widget.tripId));
    final myPhoneNumberAsync = ref.watch(myPhoneNumberProvider);
    final myPhoneVisibilityAsync =
        ref.watch(tripMemberPhoneVisibilityStreamProvider(widget.tripId));
    final myParticipantAsync = ref.watch(myTripMemberStreamProvider(widget.tripId));
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return _buildScaffold(
            l10n: l10n,
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
        final isTripMember =
            myUid.isNotEmpty && trip.memberUserIds.contains(myUid);
        final isTripOwner = myUid.isNotEmpty && trip.ownerId.trim() == myUid;
        if (!isTripMember) {
          return _buildScaffold(
            l10n: l10n,
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
        if (myParticipant == null ||
            stayAsync.isLoading ||
            myCupidonEnabledAsync.isLoading ||
            myPhoneVisibilityAsync.isLoading) {
          return _buildScaffold(
            l10n: l10n,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final currentStay =
            stayAsync.asData?.value ?? TripMemberStay.defaultForTrip(trip);
        final myCupidonEnabled = myCupidonEnabledAsync.asData?.value ?? false;
        final myPhoneNumber = myPhoneNumberAsync.asData?.value;
        final currentPhoneVisibility =
            myPhoneVisibilityAsync.asData?.value ?? TripMemberPhoneVisibility.nobody;

        _seedDraftIfNeeded(
          stay: currentStay,
          cupidonEnabled: myCupidonEnabled,
          phoneVisibility: myPhoneNumber == null ? null : currentPhoneVisibility,
          name: TripParticipantNameDialogResult(
            name: myParticipant.participantName,
            useProfileName: myParticipant.useProfileName,
            isChild: myParticipant.isChild,
          ),
        );

        final stayDraft = _stayDraft!;
        final nameDraft = _nameDraft!;

        return _buildScaffold(
          l10n: l10n,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    TripMemberPreferencesHead(tripName: trip.title),
                    StreamBuilder(
                      stream: ref
                          .read(accountRepositoryProvider)
                          .watchMyUserDocument(),
                      builder: (context, snapshot) {
                        final profileName =
                            profileNameFromData(snapshot.data?.data());
                        final displayName = resolveTripParticipantDisplayName(
                              result: nameDraft,
                              profileName: profileName,
                            ) ??
                            myParticipant.participantName;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TripNeonSectionHeader(
                              icon: Icons.badge_outlined,
                              label: l10n.tripUserPreferencesProfileSection,
                            ),
                            TripNeonPrefGroup(
                              children: [
                                TripMemberPreferencesNameRow(
                                  displayName: displayName,
                                  onEdit: () => _openNameDialog(
                                    profileName: profileName,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    TripMemberStayOptionsEditor(
                      mode: TripMemberStayOptionsEditorMode.draft,
                      grouped: true,
                      tripStartDate: trip.startDate,
                      tripEndDate: trip.endDate,
                      trip: trip,
                      showStayDates: !trip.isDayTrip,
                      isCupidonModeEnabled: trip.cupidonModeEnabled,
                      initialStay: stayDraft,
                      initialCupidonEnabled: _cupidonDraft,
                      initialPhoneVisibility: myPhoneNumber == null
                          ? null
                          : _phoneVisibilityDraft,
                      onDraftChanged: (draft) => setState(() {
                        _stayDraft = draft.stay;
                        _cupidonDraft = draft.cupidonEnabled;
                        _phoneVisibilityDraft = draft.phoneVisibility;
                      }),
                      cupidonTitle: l10n.cupidonModeTitle,
                      phoneVisibilityTitle: l10n.tripPhoneVisibilityTitle,
                    ),
                    TripNeonSectionHeader(
                      icon: Icons.widgets_outlined,
                      label: l10n.tripTravelerModulesSectionTitle,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TravelerModulesToggleList(
                        tripId: widget.tripId,
                      ),
                    ),
                    if (!isTripOwner) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NeonPalette.accent,
                            side: BorderSide(
                              color: NeonPalette.participantsDangerBorder,
                            ),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed:
                              _isLeavingTrip ? null : _confirmAndLeaveTrip,
                          child: _isLeavingTrip
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.tripOverviewLeaveTripCardTitle),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          bottomBar: InviteJoinDualCtaBar(
            secondaryLabel: l10n.commonCancel,
            primaryLabel: l10n.commonSave,
            secondaryEnabled: !_isSaving && !_isLeavingTrip,
            primaryEnabled: _dirty && !_isSaving && !_isLeavingTrip,
            busy: _isSaving,
            onSecondary: () =>
                context.go('/trips/${widget.tripId}/overview'),
            onPrimary: _saveAll,
          ),
        );
      },
      loading: () => _buildScaffold(
        l10n: l10n,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _buildScaffold(
        l10n: l10n,
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
