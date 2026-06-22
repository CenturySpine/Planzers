import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/administration/data/maintenance_repository.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/invite_join_widgets.dart';
import 'package:planerz/features/trips/presentation/trip_create_creator_name_dialog.dart';
import 'package:planerz/features/trips/presentation/trip_member_preferences_ui.dart';
import 'package:planerz/features/trips/presentation/trip_member_stay_options_editor.dart';
import 'package:planerz/features/trips/presentation/trip_participant_name_dialog.dart';
import 'package:planerz/features/trips/presentation/trip_stay_form_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

class _TravelInfoSnapshot {
  const _TravelInfoSnapshot({
    required this.stay,
    required this.name,
  });

  final TripMemberStay stay;
  final TripParticipantNameDialogResult name;

  bool equalsDraft({
    required TripMemberStay stay,
    required TripParticipantNameDialogResult name,
  }) {
    return this.stay == stay &&
        this.name.name == name.name &&
        this.name.useProfileName == name.useProfileName &&
        this.name.isChild == name.isChild;
  }
}

class TripParticipantTravelInfoPage extends ConsumerStatefulWidget {
  const TripParticipantTravelInfoPage({
    super.key,
    required this.tripId,
    required this.participantId,
  });

  final String tripId;
  final String participantId;

  @override
  ConsumerState<TripParticipantTravelInfoPage> createState() =>
      _TripParticipantTravelInfoPageState();
}

class _TripParticipantTravelInfoPageState
    extends ConsumerState<TripParticipantTravelInfoPage> {
  bool _isSaving = false;
  bool _draftReady = false;

  TripMemberStay? _stayDraft;
  TripParticipantNameDialogResult? _nameDraft;
  _TravelInfoSnapshot? _savedSnapshot;

  static String _messageForError(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is FirebaseFunctionsException) {
      final message = error.message;
      if (message != null && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return l10n.commonErrorWithDetails(error.toString());
  }

  bool get _dirty {
    final snapshot = _savedSnapshot;
    final name = _nameDraft;
    final stay = _stayDraft;
    if (!_draftReady || snapshot == null || name == null || stay == null) {
      return false;
    }
    return !snapshot.equalsDraft(stay: stay, name: name);
  }

  void _seedDraftIfNeeded({
    required TripMemberStay stay,
    required TripParticipantNameDialogResult name,
  }) {
    if (_draftReady) return;
    _stayDraft = stay;
    _nameDraft = name;
    _savedSnapshot = _TravelInfoSnapshot(stay: stay, name: name);
    _draftReady = true;
  }

  @override
  void didUpdateWidget(covariant TripParticipantTravelInfoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.participantId != widget.participantId ||
        oldWidget.tripId != widget.tripId) {
      _draftReady = false;
      _savedSnapshot = null;
      _stayDraft = null;
      _nameDraft = null;
    }
  }

  Future<void> _openNameDialog({
    required TripMember participant,
    required String? profileName,
  }) async {
    final current = _nameDraft;
    if (current == null) return;

    final TripParticipantNameDialogResult? result;
    if (participant.isClaimed) {
      result = await showTripCreateCreatorNameDialog(
        context: context,
        initialCustomName: current.useProfileName ? '' : current.name,
        initialUseProfileName: current.useProfileName,
        profileName: profileName,
      );
    } else {
      result = await showDialog<TripParticipantNameDialogResult>(
        context: context,
        builder: (dialogContext) => TripParticipantNameDialog(
          initialName: current.name,
          initialUseProfileName: current.useProfileName,
          initialIsChild: current.isChild,
          isClaimed: false,
          profileName: profileName,
        ),
      );
    }

    if (!mounted || result == null) return;
    setState(() => _nameDraft = result);
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
      final futures = <Future<void>>[];

      if (snapshot.stay != stay) {
        futures.add(
          ref.read(tripMembersRepositoryProvider).updateParticipantProfile(
                tripId: widget.tripId,
                participantId: widget.participantId,
                stay: stay,
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
                participantId: widget.participantId,
                participantName: name.name,
                useProfileName: name.useProfileName,
                isChild: name.isChild,
              ),
        );
      }

      await Future.wait(futures);

      if (!mounted) return;
      setState(() {
        _savedSnapshot = _TravelInfoSnapshot(stay: stay, name: name);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripParticipantTravelInfoSaved)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(context, error))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n) {
    return AppBar(
      toolbarHeight: 52,
      title: Text(l10n.tripParticipantTravelInfoTitle),
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back),
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

  Widget _scaffoldWithMessage({
    required AppLocalizations l10n,
    required String message,
  }) {
    return _buildScaffold(
      l10n: l10n,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));
    final participant = ref.watch(
      tripParticipantByIdProvider(
        (tripId: widget.tripId, participantId: widget.participantId),
      ),
    );
    final participantsAsync =
        ref.watch(tripParticipantsStreamProvider(widget.tripId));

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return _scaffoldWithMessage(
            l10n: l10n,
            message: l10n.tripNotFoundOrNoAccess,
          );
        }

        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final isApplicationOwner =
            ref.watch(isApplicationOwnerProvider).asData?.value ?? false;
        final canManageParticipants = canManageTripParticipantsForUser(
          trip: trip,
          userId: myUid,
          isApplicationOwner: isApplicationOwner,
        );
        if (!canManageParticipants) {
          return _scaffoldWithMessage(
            l10n: l10n,
            message: l10n.tripNotFoundOrNoAccess,
          );
        }

        if (participantsAsync.isLoading && participant == null) {
          return _buildScaffold(
            l10n: l10n,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (participant == null) {
          return _scaffoldWithMessage(
            l10n: l10n,
            message: l10n.tripParticipantNotFound,
          );
        }

        final userId = participant.userId;
        final usersDataById = userId != null
            ? ref
                .watch(
                  usersDataByIdsKeyStreamProvider(
                    stableUsersIdsKey([userId]),
                  ),
                )
                .asData
                ?.value
            : null;
        Map<String, dynamic>? profileData;
        if (participant.isClaimed && userId != null && usersDataById != null) {
          profileData = usersDataById[userId];
        }
        final profileName = profileNameFromData(profileData);
        final displayLabel = resolveTripMemberDisplayLabel(
          participant,
          profileData: profileData,
        );
        final currentStay =
            participant.stay ?? TripMemberStay.defaultForTrip(trip);

        _seedDraftIfNeeded(
          stay: currentStay,
          name: TripParticipantNameDialogResult(
            name: participant.participantName,
            useProfileName: participant.useProfileName,
            isChild: participant.isChild,
          ),
        );

        final stayDraft = _stayDraft!;
        final nameDraft = _nameDraft!;
        final resolvedDisplayName = resolveTripParticipantDisplayName(
              result: nameDraft,
              profileName: profileName,
            ) ??
            displayLabel;

        return _buildScaffold(
          l10n: l10n,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    TripNeonPrefsScreenHead(
                      kicker: l10n.tripParticipantTravelInfoHeadKicker,
                      centerTitle: resolvedDisplayName,
                      subtitle: l10n.tripParticipantTravelInfoHeadSubtitle,
                      icon: Icons.badge_outlined,
                    ),
                    TripNeonSectionHeader(
                      icon: Icons.badge_outlined,
                      label: l10n.tripParticipantTravelInfoProfileSection,
                    ),
                    TripNeonPrefGroup(
                      children: [
                        TripNeonPrefsNameRow(
                          leadLabel: l10n.tripParticipantTravelInfoParticipatingAs,
                          displayName: resolvedDisplayName,
                          onEdit: () => _openNameDialog(
                            participant: participant,
                            profileName: profileName,
                          ),
                        ),
                      ],
                    ),
                    if (!trip.isDayTrip)
                      TripMemberStayOptionsEditor(
                        mode: TripMemberStayOptionsEditorMode.draft,
                        grouped: true,
                        showOptionsSection: false,
                        staySectionLabel:
                            l10n.tripParticipantTravelInfoStaySection,
                        tripStartDate: trip.startDate,
                        tripEndDate: trip.endDate,
                        trip: trip,
                        showStayDates: true,
                        isCupidonModeEnabled: false,
                        initialStay: stayDraft,
                        initialCupidonEnabled: false,
                        onDraftChanged: (draft) => setState(() {
                          _stayDraft = draft.stay;
                        }),
                        cupidonTitle: l10n.cupidonModeTitle,
                      ),
                  ],
                ),
              ),
            ],
          ),
          bottomBar: InviteJoinDualCtaBar(
            secondaryLabel: l10n.commonCancel,
            primaryLabel: l10n.commonSave,
            secondaryEnabled: !_isSaving,
            primaryEnabled: _dirty && !_isSaving,
            busy: _isSaving,
            onSecondary: () => context.pop(),
            onPrimary: _saveAll,
          ),
        );
      },
      loading: () => _buildScaffold(
        l10n: l10n,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _scaffoldWithMessage(
        l10n: l10n,
        message: l10n.commonErrorWithDetails(error.toString()),
      ),
    );
  }
}
