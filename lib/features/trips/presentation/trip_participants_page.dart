import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/cupidon/data/cupidon_repository.dart';
import 'package:planerz/features/administration/data/maintenance_repository.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/trips/data/participant_group.dart';
import 'package:planerz/features/trips/data/participant_groups_repository.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/core/presentation/planerz_info_callout.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
import 'package:planerz/features/trips/presentation/trip_participant_name_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class TripParticipantsPage extends ConsumerStatefulWidget {
  const TripParticipantsPage({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  ConsumerState<TripParticipantsPage> createState() =>
      _TripParticipantsPageState();
}

class _TripParticipantsPageState extends ConsumerState<TripParticipantsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static String _messageForError(BuildContext context, Object e) {
    final l10n = AppLocalizations.of(context)!;
    if (e is FirebaseFunctionsException) {
      final m = e.message;
      if (m != null && m.trim().isNotEmpty) {
        return m.trim();
      }
    }
    return l10n.commonErrorWithDetails(e.toString());
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final asyncTrip = ref.watch(tripStreamProvider(widget.tripId));

    return asyncTrip.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.tripParticipantsTitle)),
            body: Center(child: Text(l10n.tripNotFound)),
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

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.tripParticipantsTitle),
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: l10n.tripSectionParticipants),
                Tab(text: l10n.participantGroupsTabLabel),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _ParticipantsTab(
                tripId: widget.tripId,
                trip: trip,
                canManageParticipants: canManageParticipants,
                myUid: myUid,
                isApplicationOwner: isApplicationOwner,
                messageForError: _messageForError,
              ),
              _GroupsTab(
                tripId: widget.tripId,
                trip: trip,
                canManageParticipants: canManageParticipants,
                messageForError: _messageForError,
              ),
            ],
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.tripParticipantsTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(l10n.tripParticipantsTitle)),
        body:
            Center(child: Text(l10n.commonErrorWithDetails(e.toString()))),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Participants tab (existing logic extracted)
// ---------------------------------------------------------------------------

class _ParticipantsTab extends ConsumerStatefulWidget {
  const _ParticipantsTab({
    required this.tripId,
    required this.trip,
    required this.canManageParticipants,
    required this.myUid,
    required this.isApplicationOwner,
    required this.messageForError,
  });

  final String tripId;
  final Trip trip;
  final bool canManageParticipants;
  final String? myUid;
  final bool isApplicationOwner;
  final String Function(BuildContext, Object) messageForError;

  @override
  ConsumerState<_ParticipantsTab> createState() => _ParticipantsTabState();
}

class _ParticipantsTabState extends ConsumerState<_ParticipantsTab> {
  Stream<Map<String, Map<String, dynamic>>>? _usersDataStreamCache;
  String? _usersDataStreamKey;

  Stream<Map<String, Map<String, dynamic>>> _usersDataStreamFor(
    List<TripMember> participants,
  ) {
    final claimedUids = participants
        .where((m) => m.isClaimed)
        .map((m) => m.userId!)
        .toList();
    final sorted = [...claimedUids]..sort();
    final key = sorted.join('\x1e');
    if (_usersDataStreamKey == key && _usersDataStreamCache != null) {
      return _usersDataStreamCache!;
    }
    _usersDataStreamKey = key;
    _usersDataStreamCache =
        ref.read(usersRepositoryProvider).watchUsersDataByIds(claimedUids);
    return _usersDataStreamCache!;
  }

  final Set<String> _removingMemberIds = <String>{};
  final Set<String> _cyclingMemberIds = <String>{};
  final Set<String> _likingMemberIds = <String>{};
  final TextEditingController _participantSearchController =
      TextEditingController();

  @override
  void dispose() {
    _participantSearchController.dispose();
    super.dispose();
  }

  Future<void> _cycleMemberAdminRole({
    required String memberId,
    required String displayLabel,
    required bool wasAdmin,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final cleanId = memberId.trim();
    if (cleanId.isEmpty || _cyclingMemberIds.contains(cleanId)) return;

    setState(() => _cyclingMemberIds.add(cleanId));
    try {
      await ref.read(tripsRepositoryProvider).cycleTripMemberAdminRole(
            tripId: widget.tripId,
            memberId: cleanId,
          );
      if (!mounted) return;
      final label = displayLabel.trim().isEmpty
          ? l10n.tripParticipantsThisParticipant
          : displayLabel;
      final message = wasAdmin
          ? l10n.tripParticipantsAdminRemoved(label)
          : l10n.tripParticipantsAdminGranted(label);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripParticipantsLikeSaveError)),
      );
    } finally {
      if (mounted) {
        setState(() => _cyclingMemberIds.remove(cleanId));
      }
    }
  }

  Future<void> _openAddDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    var isChild = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.tripParticipantsAddPlannedTravelerTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.commonName,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Text(
                  tripMemberChildLabelEmoji,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                title: Text(l10n.tripParticipantsIsChildLabel),
                subtitle: Text(l10n.tripParticipantsIsChildSubtitle),
                value: isChild,
                onChanged: (value) => setDialogState(() => isChild = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.commonAdd),
            ),
          ],
        ),
      ),
    );
    final name = ok == true ? controller.text.trim() : '';
    final savedIsChild = ok == true && isChild;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (ok != true || !mounted) return;
    if (name.isEmpty) return;
    try {
      await ref.read(tripsRepositoryProvider).addTripParticipant(
            tripId: widget.tripId,
            participantName: name,
            isChild: savedIsChild,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripParticipantsPlannedTravelerAdded)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.messageForError(context, e))),
      );
    }
  }

  Future<void> _openEditParticipantDialog({
    required String participantId,
    required String currentName,
    required bool currentUseProfileName,
    required bool currentIsChild,
    required bool isClaimed,
    Map<String, dynamic>? profileData,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final profileName = profileNameFromData(profileData);

    final result = await showDialog<TripParticipantNameDialogResult>(
      context: context,
      builder: (ctx) => TripParticipantNameDialog(
        initialName: currentName,
        initialUseProfileName: currentUseProfileName,
        initialIsChild: currentIsChild,
        isClaimed: isClaimed,
        profileName: profileName,
      ),
    );

    if (result == null || !mounted) return;
    final name = result.name;
    final savedUseProfileName = result.useProfileName;
    final savedIsChild = result.isChild;
    if (name.isEmpty && !savedUseProfileName) return;
    try {
      await ref.read(tripsRepositoryProvider).updateTripParticipantName(
            tripId: widget.tripId,
            participantId: participantId,
            participantName: name,
            useProfileName: savedUseProfileName,
            isChild: savedIsChild,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripParticipantsNameUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.messageForError(context, e))),
      );
    }
  }

  Future<void> _confirmRemoveParticipant({
    required String participantId,
    required String label,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tripParticipantsRemovePlannedTravelerTitle),
        content: Text(l10n.tripParticipantsRemovePlannedTravelerBody(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tripParticipantsRemoveAction),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(tripsRepositoryProvider).removeTripParticipant(
            tripId: widget.tripId,
            participantId: participantId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripParticipantsPlannedTravelerRemoved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.messageForError(context, e))),
      );
    }
  }

  Future<void> _confirmRemoveMember({
    required String memberId,
    required String label,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final cleanId = memberId.trim();
    if (cleanId.isEmpty || _removingMemberIds.contains(cleanId)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tripParticipantsRemoveParticipantTitle),
        content: Text(l10n.tripParticipantsRemoveParticipantBody(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tripParticipantsRemoveAction),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _removingMemberIds.add(cleanId));
    try {
      await ref.read(tripsRepositoryProvider).removeMemberFromTrip(
            tripId: widget.tripId,
            memberId: cleanId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripParticipantsRemovedFromTrip)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.messageForError(context, e))),
      );
    } finally {
      if (mounted) {
        setState(() => _removingMemberIds.remove(cleanId));
      }
    }
  }

  Future<void> _toggleCupidonLike({
    required String targetMemberId,
    required bool currentlyLiked,
  }) async {
    final cleanId = targetMemberId.trim();
    if (cleanId.isEmpty || _likingMemberIds.contains(cleanId)) return;
    setState(() => _likingMemberIds.add(cleanId));
    try {
      await ref.read(cupidonRepositoryProvider).setLike(
            tripId: widget.tripId,
            targetMemberId: cleanId,
            isLiked: !currentlyLiked,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.messageForError(context, e))),
      );
    } finally {
      if (mounted) {
        setState(() => _likingMemberIds.remove(cleanId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final asyncParticipants =
        ref.watch(tripParticipantsStreamProvider(widget.tripId));
    final myUid = widget.myUid;
    final cupidonEnabledAsync =
        ref.watch(tripCupidonEnabledMemberIdsProvider(widget.tripId));
    final myLikesAsync =
        ref.watch(myCupidonLikedTargetIdsProvider(widget.tripId));

    return Stack(
      children: [
        Positioned.fill(
          child: asyncParticipants.when(
            data: (participants) {
        final membersPhoneVisibilityAsync = ref
            .watch(tripMembersPhoneVisibilityStreamProvider(widget.tripId));
        final usersStream = _usersDataStreamFor(participants);
        return StreamBuilder<Map<String, Map<String, dynamic>>>(
          stream: usersStream,
          builder: (context, userSnap) {
            final userDataByUid = userSnap.data ?? const {};
            final enabledCupidonMemberIds =
                cupidonEnabledAsync.asData?.value ?? const <String>{};
            final likedByMe =
                myLikesAsync.asData?.value ?? const <String>{};
            final membersPhoneVisibility =
                membersPhoneVisibilityAsync.asData?.value ?? const {};
            final currentUserRole = resolveTripPermissionRole(
              trip: widget.trip,
              userId: myUid,
            );
            final canToggleAdminRole =
                canToggleTripParticipantAdminRoleForUser(
              trip: widget.trip,
              userId: myUid,
              isApplicationOwner: widget.isApplicationOwner,
            );
            final rows = _participantRowsForTrip(
              widget.trip,
              participants,
              userDataByUid,
              myUid,
              l10n: l10n,
              enabledCupidonMemberIds: enabledCupidonMemberIds,
              likedByMe: likedByMe,
              membersPhoneVisibility: membersPhoneVisibility,
              currentUserRole: currentUserRole,
            );
            final myUidTrim = (myUid ?? '').trim();
            final myCupidonEnabled = enabledCupidonMemberIds
                .contains((myUid ?? '').trim());
            final searchQuery = _participantSearchController.text;
            final visibleRows = rows
                .where(
                  (r) => displayNameMatchesNameSearch(
                      r.displayLabel, searchQuery),
                )
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.canManageParticipants)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: PlanerzInfoCallout(
                      message: l10n.tripParticipantsAdminHint,
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    widget.canManageParticipants ? 8 : 12,
                    16,
                    8,
                  ),
                  child: NameListSearchTextField(
                    controller: _participantSearchController,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (rows.isEmpty)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.tripParticipantsEmpty,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: visibleRows.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                nameListSearchEmptyMessage(context),
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: visibleRows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = visibleRows[index];
                              final isOwnerRow =
                                  row.userId?.trim() ==
                                      widget.trip.ownerId.trim();
                              final isRemoving =
                                  _removingMemberIds.contains(
                                      row.participantId.trim());
                              final isCycling =
                                  _cyclingMemberIds.contains(
                                      row.participantId.trim());
                              final scheme =
                                  Theme.of(context).colorScheme;
                              final canCycleRole =
                                  canToggleAdminRole && !isOwnerRow && row.isClaimed;
                              final canDeleteThisRow =
                                  widget.canManageParticipants &&
                                      !isOwnerRow &&
                                      row.userId?.trim() != myUidTrim;

                              return Card(
                                child: ListTile(
                                  onTap: row.isClaimed &&
                                          row.userId != null
                                      ? () => context.push(
                                            '/users/${row.userId}/profile?label=${Uri.encodeComponent(row.displayLabel)}',
                                          )
                                      : null,
                                  leading:
                                      _participantRoleLeading(
                                    context: context,
                                    scheme: scheme,
                                    row: row,
                                    isOwnerRow: isOwnerRow,
                                    showAdminIcon: row.isAdmin,
                                    canCycleRole: canCycleRole,
                                    isCycling: isCycling,
                                    onCycle: canCycleRole &&
                                            !isCycling &&
                                            row.userId != null
                                        ? () =>
                                            _cycleMemberAdminRole(
                                              memberId: row.userId!,
                                              displayLabel:
                                                  row.displayLabel,
                                              wasAdmin: row.isAdmin,
                                            )
                                        : null,
                                  ),
                                  title: Text(row.displayLabel),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (row.phoneUri != null)
                                        IconButton(
                                          tooltip: l10n
                                              .tripParticipantsOpenDialer,
                                          icon: const Icon(
                                              Icons.phone_outlined),
                                          onPressed: () =>
                                              launchUrl(Uri.parse(
                                                  row.phoneUri!)),
                                        ),
                                      if (row.isClaimed &&
                                          row.userId?.trim() !=
                                              myUidTrim &&
                                          myCupidonEnabled)
                                        IconButton(
                                          tooltip: row.likedByMe
                                              ? l10n
                                                  .tripParticipantsUnlike
                                              : l10n
                                                  .tripParticipantsLike,
                                          onPressed: _likingMemberIds
                                                  .contains(
                                                      row.userId
                                                          ?.trim() ?? '')
                                              ? null
                                              : () =>
                                                  _toggleCupidonLike(
                                                    targetMemberId:
                                                        row.userId!,
                                                    currentlyLiked:
                                                        row.likedByMe,
                                                  ),
                                          icon: _likingMemberIds
                                                  .contains(row
                                                      .userId
                                                      ?.trim() ?? '')
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : Icon(
                                                  row.likedByMe
                                                      ? Icons.favorite
                                                      : Icons
                                                          .favorite_border,
                                                  color: Theme.of(
                                                          context)
                                                      .colorScheme
                                                      .error,
                                                ),
                                        ),
                                      if (widget.canManageParticipants ||
                                          row.userId?.trim() ==
                                              myUidTrim)
                                        IconButton(
                                          tooltip: l10n.commonEdit,
                                          icon: const Icon(
                                              Icons.edit_outlined),
                                          onPressed: () =>
                                              _openEditParticipantDialog(
                                            participantId:
                                                row.participantId,
                                            currentName:
                                                row.rawParticipantName,
                                            currentUseProfileName:
                                                row.useProfileName,
                                            currentIsChild: row.isChild,
                                            isClaimed: row.isClaimed,
                                            profileData:
                                                row.profileData,
                                          ),
                                        ),
                                      if (canDeleteThisRow)
                                        IconButton(
                                          tooltip: l10n
                                              .tripParticipantsRemoveAction,
                                          icon: row.isClaimed &&
                                                  isRemoving
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.delete_outline,
                                                  color: scheme.error,
                                                ),
                                          onPressed: row.isClaimed &&
                                                  isRemoving
                                              ? null
                                              : () => row.isClaimed
                                                  ? _confirmRemoveMember(
                                                      memberId:
                                                          row.userId!,
                                                      label: row
                                                          .displayLabel,
                                                    )
                                                  : _confirmRemoveParticipant(
                                                      participantId:
                                                          row.participantId,
                                                      label: row
                                                          .displayLabel,
                                                    ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
              ],
            );
          },
        );
      },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Center(child: Text(l10n.commonErrorWithDetails(e.toString()))),
        ),
      ),
      if (widget.canManageParticipants)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'add_participant',
            onPressed: _openAddDialog,
            tooltip: l10n.tripParticipantsAddPlannedTravelerTitle,
            child: const Icon(Icons.add),
          ),
        ),
    ],
  );
}
}

// ---------------------------------------------------------------------------
// Groups tab
// ---------------------------------------------------------------------------

class _GroupsTab extends ConsumerStatefulWidget {
  const _GroupsTab({
    required this.tripId,
    required this.trip,
    required this.canManageParticipants,
    required this.messageForError,
  });

  final String tripId;
  final Trip trip;
  final bool canManageParticipants;
  final String Function(BuildContext, Object) messageForError;

  @override
  ConsumerState<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends ConsumerState<_GroupsTab> {
  final Set<String> _deletingGroupIds = {};

  Future<void> _openGroupEditor({ParticipantGroup? existing}) async {
    final l10n = AppLocalizations.of(context)!;
    final participants =
        ref.read(tripParticipantsStreamProvider(widget.tripId)).asData?.value ??
            [];
    final memberLabels = ref.read(tripMemberResolvedLabelsProvider(widget.tripId));
    final groups =
        ref.read(tripParticipantGroupsStreamProvider(widget.tripId)).asData?.value ??
            [];

    if (existing != null) {
      final isUsed = await ref
          .read(participantGroupsRepositoryProvider)
          .isGroupReferencedInExpenses(
            tripId: widget.tripId,
            groupId: existing.id,
          );
      if (!mounted) return;
      if (isUsed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.participantGroupsUsedInExpenses),
          ),
        );
        return;
      }
    }

    final result = await showDialog<_GroupEditorResult>(
      context: context,
      builder: (ctx) => _GroupEditorDialog(
        tripId: widget.tripId,
        existing: existing,
        participants: participants,
        memberLabels: memberLabels,
        groups: groups,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final repo = ref.read(participantGroupsRepositoryProvider);
      if (existing == null) {
        await repo.createGroup(
          tripId: widget.tripId,
          label: result.label,
          memberIds: result.memberIds,
          parts: result.parts,
        );
      } else {
        await repo.updateGroup(
          tripId: widget.tripId,
          groupId: existing.id,
          label: result.label,
          memberIds: result.memberIds,
          parts: result.parts,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.participantGroupsSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.messageForError(context, e))),
      );
    }
  }

  Future<void> _confirmDelete(ParticipantGroup group) async {
    final l10n = AppLocalizations.of(context)!;
    if (_deletingGroupIds.contains(group.id)) return;

    final isUsed = await ref
        .read(participantGroupsRepositoryProvider)
        .isGroupReferencedInExpenses(
          tripId: widget.tripId,
          groupId: group.id,
        );
    if (!mounted) return;
    if (isUsed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.participantGroupsUsedInExpenses)),
      );
      return;
    }

    final label = group.label.isNotEmpty ? group.label : group.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.participantGroupsDeleteTitle),
        content: Text(l10n.participantGroupsDeleteBody(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deletingGroupIds.add(group.id));
    try {
      await ref
          .read(participantGroupsRepositoryProvider)
          .deleteGroup(tripId: widget.tripId, groupId: group.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.participantGroupsDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.messageForError(context, e))),
      );
    } finally {
      if (mounted) setState(() => _deletingGroupIds.remove(group.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final groupsAsync =
        ref.watch(tripParticipantGroupsStreamProvider(widget.tripId));
    final memberLabels =
        ref.watch(tripMemberResolvedLabelsProvider(widget.tripId));

    return groupsAsync.when(
      data: (groups) {
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: PlanerzInfoCallout(
                    message: l10n.participantGroupsTabHint,
                  ),
                ),
                Expanded(
                  child: groups.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              l10n.participantGroupsEmpty,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                          itemCount: groups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      final memberNames = group.memberIds
                          .map((id) =>
                              memberLabels[id] ??
                              l10n.tripParticipantsTraveler)
                          .join(', ');
                      final partsLabel =
                          group.parts == group.parts.truncateToDouble()
                              ? group.parts.toInt().toString()
                              : group.parts.toStringAsFixed(1);
                      final subtitle = l10n.participantGroupsMemberCount(
                        group.memberIds.length,
                        partsLabel,
                      );
                      final isDeleting =
                          _deletingGroupIds.contains(group.id);
                      return Card(
                        child: ListTile(
                          title: Text(
                            group.label.isNotEmpty
                                ? group.label
                                : group.id,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(subtitle),
                              if (memberNames.isNotEmpty)
                                Text(
                                  memberNames,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                          isThreeLine: memberNames.isNotEmpty,
                          trailing: widget.canManageParticipants
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: l10n.commonEdit,
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: isDeleting
                                          ? null
                                          : () => _openGroupEditor(
                                              existing: group),
                                    ),
                                    IconButton(
                                      tooltip:
                                          l10n.tripParticipantsRemoveAction,
                                      icon: isDeleting
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth: 2),
                                            )
                                          : Icon(Icons.delete_outline,
                                              color: cs.error),
                                      onPressed: isDeleting
                                          ? null
                                          : () => _confirmDelete(group),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      );
                    },
                        ),
                ),
              ],
            ),
            if (widget.canManageParticipants)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'add_participant_group',
                  tooltip: l10n.participantGroupsAddTitle,
                  onPressed: () => _openGroupEditor(),
                  child: const Icon(Icons.add),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(l10n.commonErrorWithDetails(e.toString()))),
    );
  }
}

// ---------------------------------------------------------------------------
// Group editor dialog
// ---------------------------------------------------------------------------

class _GroupEditorResult {
  const _GroupEditorResult({
    required this.label,
    required this.memberIds,
    required this.parts,
  });

  final String label;
  final List<String> memberIds;
  final double parts;
}

class _GroupEditorDialog extends ConsumerStatefulWidget {
  const _GroupEditorDialog({
    required this.tripId,
    required this.existing,
    required this.participants,
    required this.memberLabels,
    required this.groups,
  });

  final String tripId;
  final ParticipantGroup? existing;
  final List<TripMember> participants;
  final Map<String, String> memberLabels;
  final List<ParticipantGroup> groups;

  @override
  ConsumerState<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends ConsumerState<_GroupEditorDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _partsController;
  late final Set<String> _selectedMemberIds;

  Map<String, TripMember> get _membersById =>
      {for (final m in widget.participants) m.id: m};

  String _formatParts(double value) =>
      value == value.truncateToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(1);

  bool _partsEqual(double a, double b) => (a - b).abs() < 0.001;

  double _suggestedPartsFor(Set<String> memberIds) =>
      suggestedParticipantGroupParts(memberIds, _membersById);

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.existing?.label ?? '');
    final defaultParts = widget.existing?.parts ??
        (widget.existing != null
            ? _suggestedPartsFor(widget.existing!.memberIds.toSet())
            : 2.0);
    _partsController = TextEditingController(
      text: _formatParts(defaultParts),
    );
    _selectedMemberIds = {...(widget.existing?.memberIds ?? [])};
  }

  @override
  void dispose() {
    _labelController.dispose();
    _partsController.dispose();
    super.dispose();
  }

  String? _groupOwnerOf(String memberId) {
    for (final g in widget.groups) {
      if (g.id == widget.existing?.id) continue;
      if (g.memberIds.contains(memberId)) return g.label.isNotEmpty ? g.label : g.id;
    }
    return null;
  }

  void _onMemberToggled(String memberId, bool selected) {
    setState(() {
      final previousIds = Set<String>.from(_selectedMemberIds);
      if (selected) {
        _selectedMemberIds.add(memberId);
      } else {
        _selectedMemberIds.remove(memberId);
      }
      if (_selectedMemberIds.isNotEmpty) {
        final currentParts =
            double.tryParse(_partsController.text.replaceAll(',', '.'));
        final oldSuggested = _suggestedPartsFor(previousIds);
        if (currentParts != null && _partsEqual(currentParts, oldSuggested)) {
          _partsController.text =
              _formatParts(_suggestedPartsFor(_selectedMemberIds));
        }
      }
    });
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.participantGroupsLabelRequired)),
      );
      return;
    }
    if (_selectedMemberIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.participantGroupsMembersMinTwo)),
      );
      return;
    }
    final partsRaw = double.tryParse(
      _partsController.text.trim().replaceAll(',', '.'),
    );
    if (partsRaw == null || partsRaw <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.participantGroupsPartsInvalid)),
      );
      return;
    }
    Navigator.of(context).pop(
      _GroupEditorResult(
        label: label,
        memberIds: _selectedMemberIds.toList(),
        parts: partsRaw,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final title = widget.existing == null
        ? l10n.participantGroupsAddTitle
        : l10n.participantGroupsEditTitle;

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _labelController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.participantGroupsLabelField,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.participantGroupsMembersField,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final m in widget.participants)
              Builder(builder: (context) {
                final ownerGroup = _groupOwnerOf(m.id);
                final alreadyInOtherGroup =
                    ownerGroup != null && !_selectedMemberIds.contains(m.id);
                final label = widget.memberLabels[m.id] ??
                    l10n.tripParticipantsTraveler;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    label,
                    style: alreadyInOtherGroup
                        ? TextStyle(color: cs.onSurfaceVariant)
                        : null,
                  ),
                  subtitle: alreadyInOtherGroup
                      ? Text(
                          l10n.participantGroupsAlreadyInGroup(
                              label, ownerGroup),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.error),
                        )
                      : null,
                  value: _selectedMemberIds.contains(m.id),
                  onChanged: alreadyInOtherGroup
                      ? null
                      : (v) => _onMemberToggled(m.id, v == true),
                );
              }),
            const SizedBox(height: 16),
            TextField(
              controller: _partsController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.participantGroupsPartsField,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers (unchanged from original file)
// ---------------------------------------------------------------------------

TripPermissionRole? _minRoleForPhoneVisibility(TripMemberPhoneVisibility vis) {
  return switch (vis) {
    TripMemberPhoneVisibility.nobody => null,
    TripMemberPhoneVisibility.owner => TripPermissionRole.owner,
    TripMemberPhoneVisibility.admin => TripPermissionRole.admin,
    TripMemberPhoneVisibility.participant => TripPermissionRole.participant,
  };
}

String? _phoneUriForMember({
  required Map<String, dynamic>? profileData,
  required TripMemberPhoneVisibility? visibility,
  required TripPermissionRole currentUserRole,
}) {
  if (visibility == null) return null;
  final minRole = _minRoleForPhoneVisibility(visibility);
  if (minRole == null) return null;
  if (!currentUserRole.allows(minRole)) return null;
  if (profileData == null) return null;
  final account =
      (profileData['account'] as Map<String, dynamic>?) ?? const {};
  final code = (account['phoneCountryCode'] as String?)?.trim() ?? '';
  final number = (account['phoneNumber'] as String?)?.trim() ?? '';
  if (number.isEmpty) return null;
  return 'tel:$code${number.replaceAll(' ', '')}';
}

List<_ParticipantRow> _participantRowsForTrip(
  Trip trip,
  List<TripMember> participants,
  Map<String, Map<String, dynamic>> userDataByUid,
  String? myUid, {
  required AppLocalizations l10n,
  required Set<String> enabledCupidonMemberIds,
  required Set<String> likedByMe,
  required Map<String, TripMemberPhoneVisibility> membersPhoneVisibility,
  required TripPermissionRole currentUserRole,
}) {
  final rows = participants.map((member) {
    final profileData =
        member.userId != null ? userDataByUid[member.userId] : null;
    final phoneUri = member.userId == (myUid ?? '').trim()
        ? null
        : _phoneUriForMember(
            profileData: profileData,
            visibility: member.userId != null
                ? membersPhoneVisibility[member.userId]
                : null,
            currentUserRole: currentUserRole,
          );
    return _ParticipantRow(
      participantId: member.id,
      userId: member.userId,
      isClaimed: member.isClaimed,
      rawParticipantName: member.participantName,
      useProfileName: member.useProfileName,
      isChild: member.isChild,
      displayLabel: resolveTripMemberDisplayLabel(member, profileData: profileData),
      isAdmin: member.userId != null
          ? trip.memberHasAdminRole(member.userId!)
          : false,
      likedByMe: member.userId != null
          ? likedByMe.contains(member.userId)
          : false,
      profileData: profileData,
      phoneUri: phoneUri,
    );
  }).toList();
  rows.sort(
    (a, b) => compareDisplayNamesForSort(a.displayLabel, b.displayLabel),
  );
  return rows;
}

const double _kParticipantRoleLeadingExtent = 48;

Widget _participantRoleLeading({
  required BuildContext context,
  required ColorScheme scheme,
  required _ParticipantRow row,
  required bool isOwnerRow,
  required bool showAdminIcon,
  required bool canCycleRole,
  required bool isCycling,
  required VoidCallback? onCycle,
}) {
  Widget inFixedBox(Widget child) {
    return SizedBox(
      width: _kParticipantRoleLeadingExtent,
      height: _kParticipantRoleLeadingExtent,
      child: Center(child: child),
    );
  }

  if (isCycling) {
    return inFixedBox(
      const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  final tooltip = canCycleRole
      ? AppLocalizations.of(context)!.tripParticipantsChangeRole
      : (isOwnerRow
          ? AppLocalizations.of(context)!.roleOwner
          : (showAdminIcon
              ? AppLocalizations.of(context)!.roleAdmin
              : null));

  final baseBadge = buildProfileBadge(
    context: context,
    displayLabel: row.displayLabel,
    userData: row.profileData,
    size: 28,
    isChild: row.isChild,
  );

  final icon = showAdminIcon
      ? Stack(
          clipBehavior: Clip.none,
          children: [
            baseBadge,
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surface,
                  border: Border.all(color: scheme.primary, width: 1),
                ),
                child: Icon(
                  Icons.verified_user,
                  size: 10,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        )
      : baseBadge;

  if (!canCycleRole) {
    final fixed = inFixedBox(icon);
    if (tooltip == null || tooltip.trim().isEmpty) {
      return fixed;
    }
    return Tooltip(message: tooltip, child: fixed);
  }

  return Tooltip(
    message: tooltip ?? '',
    child: SizedBox(
      width: _kParticipantRoleLeadingExtent,
      height: _kParticipantRoleLeadingExtent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onLongPress: onCycle,
        child: Center(child: icon),
      ),
    ),
  );
}

class _ParticipantRow {
  const _ParticipantRow({
    required this.participantId,
    required this.userId,
    required this.isClaimed,
    required this.rawParticipantName,
    required this.useProfileName,
    required this.isChild,
    required this.displayLabel,
    required this.isAdmin,
    required this.likedByMe,
    this.profileData,
    this.phoneUri,
  });

  final String participantId;
  final String? userId;
  final bool isClaimed;
  final String rawParticipantName;
  final bool useProfileName;
  final bool isChild;
  final String displayLabel;
  final bool isAdmin;
  final bool likedByMe;
  final Map<String, dynamic>? profileData;
  final String? phoneUri;
}
