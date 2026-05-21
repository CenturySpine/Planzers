import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/cupidon/data/cupidon_repository.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
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

class _TripParticipantsPageState extends ConsumerState<TripParticipantsPage> {
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tripParticipantsAddPlannedTravelerTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.commonName,
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
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
    );
    final name = ok == true ? controller.text.trim() : '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (ok != true || !mounted) return;
    if (name.isEmpty) return;
    try {
      await ref.read(tripsRepositoryProvider).addTripParticipant(
            tripId: widget.tripId,
            participantName: name,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripParticipantsPlannedTravelerAdded)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(context, e))),
      );
    }
  }

  Future<void> _openEditParticipantDialog({
    required String participantId,
    required String currentName,
    required bool currentUseProfileName,
    required bool isClaimed,
    Map<String, dynamic>? profileData,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final profileName = profileNameFromData(profileData);

    final result = await showDialog<_EditParticipantNameDialogResult>(
      context: context,
      builder: (ctx) => _EditParticipantNameDialog(
        initialName: currentName,
        initialUseProfileName: currentUseProfileName,
        isClaimed: isClaimed,
        profileName: profileName,
      ),
    );

    if (result == null || !mounted) return;
    final name = result.name;
    final savedUseProfileName = result.useProfileName;
    if (name.isEmpty && !savedUseProfileName) return;
    try {
      await ref.read(tripsRepositoryProvider).updateTripParticipantName(
            tripId: widget.tripId,
            participantId: participantId,
            participantName: name,
            useProfileName: savedUseProfileName,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripParticipantsNameUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(context, e))),
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
        SnackBar(content: Text(_messageForError(context, e))),
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
        SnackBar(content: Text(_messageForError(context, e))),
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
        SnackBar(content: Text(_messageForError(context, e))),
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
    final asyncTrip = ref.watch(tripStreamProvider(widget.tripId));
    final asyncParticipants =
        ref.watch(tripParticipantsStreamProvider(widget.tripId));
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final cupidonEnabledAsync =
        ref.watch(tripCupidonEnabledMemberIdsProvider(widget.tripId));
    final myLikesAsync =
        ref.watch(myCupidonLikedTargetIdsProvider(widget.tripId));

    return asyncTrip.when(
      data: (trip) {
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.tripParticipantsTitle)),
            body: Center(child: Text(l10n.tripNotFound)),
          );
        }
        return asyncParticipants.when(
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
                  trip: trip,
                  userId: myUid,
                );
                final rows = _participantRowsForTrip(
                  trip,
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
                final currentRole = resolveTripPermissionRole(
                  trip: trip,
                  userId: myUid,
                );
                final canManageParticipants = isTripRoleAllowed(
                  currentRole: currentRole,
                  minRole: trip.participantsPermissions.manageParticipantsMinRole,
                );
                final canToggleAdminRole = isTripRoleAllowed(
                  currentRole: currentRole,
                  minRole: trip.participantsPermissions.toggleAdminRoleMinRole,
                );
                final myCupidonEnabled = enabledCupidonMemberIds
                    .contains((myUid ?? '').trim());
                final searchQuery = _participantSearchController.text;
                final visibleRows = rows
                    .where(
                      (r) => displayNameMatchesNameSearch(
                          r.displayLabel, searchQuery),
                    )
                    .toList();

                return Scaffold(
                  appBar: AppBar(
                    title: Text(
                        '${l10n.tripParticipantsTitle} (${rows.length})'),
                  ),
                  body: rows.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              l10n.tripParticipantsEmpty,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (canManageParticipants)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                child: Text(
                                  l10n.tripParticipantsAdminHint,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                canManageParticipants ? 8 : 12,
                                16,
                                8,
                              ),
                              child: NameListSearchTextField(
                                controller: _participantSearchController,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
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
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 16),
                                      itemCount: visibleRows.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final row = visibleRows[index];
                                        final isOwnerRow =
                                            row.userId?.trim() ==
                                                trip.ownerId.trim();
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
                                            canManageParticipants &&
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
                                                if (canManageParticipants ||
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
                        ),
                  floatingActionButton: canManageParticipants
                      ? FloatingActionButton(
                          onPressed: _openAddDialog,
                          tooltip:
                              l10n.tripParticipantsAddPlannedTravelerTitle,
                          child: const Icon(Icons.add),
                        )
                      : null,
                );
              },
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

class _EditParticipantNameDialogResult {
  const _EditParticipantNameDialogResult({
    required this.name,
    required this.useProfileName,
  });

  final String name;
  final bool useProfileName;
}

class _EditParticipantNameDialog extends StatefulWidget {
  const _EditParticipantNameDialog({
    required this.initialName,
    required this.initialUseProfileName,
    required this.isClaimed,
    required this.profileName,
  });

  final String initialName;
  final bool initialUseProfileName;
  final bool isClaimed;
  final String? profileName;

  @override
  State<_EditParticipantNameDialog> createState() =>
      _EditParticipantNameDialogState();
}

class _EditParticipantNameDialogState extends State<_EditParticipantNameDialog> {
  late final TextEditingController _nameController;
  late bool _useProfileName;

  bool get _profileOptionEnabled =>
      widget.isClaimed && widget.profileName != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _useProfileName = widget.initialUseProfileName && _profileOptionEnabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? get _profileOptionSubtitle {
    final l10n = AppLocalizations.of(context)!;
    if (!widget.isClaimed) {
      return l10n.tripParticipantsEditNameProfileRequiresClaim;
    }
    if (widget.profileName != null) {
      return l10n.tripParticipantsProfileNameDisplay(widget.profileName!);
    }
    return l10n.tripParticipantsNoProfileNameHint;
  }

  void _save() {
    Navigator.of(context).pop(
      _EditParticipantNameDialogResult(
        name: _nameController.text.trim(),
        useProfileName: _useProfileName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final useCustomName = !_useProfileName;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      contentPadding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(l10n.tripParticipantsEditNameTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<bool>(
              groupValue: _useProfileName,
              onChanged: (value) {
                if (value == null) return;
                if (value && !_profileOptionEnabled) return;
                setState(() => _useProfileName = value);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ParticipantNameSourceOption(
                    title: l10n.tripParticipantsEditNameModeCustom,
                    icon: Icons.edit_outlined,
                    value: false,
                    selected: !_useProfileName,
                    onTap: () => setState(() => _useProfileName = false),
                  ),
                  const SizedBox(height: 12),
                  _ParticipantNameSourceOption(
                    title: l10n.tripParticipantsEditNameModeProfile,
                    icon: Icons.badge_outlined,
                    value: true,
                    selected: _useProfileName,
                    enabled: _profileOptionEnabled,
                    subtitle: _profileOptionSubtitle,
                    onTap: _profileOptionEnabled
                        ? () => setState(() => _useProfileName = true)
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (useCustomName)
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.commonName,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 22,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.profileName ?? '',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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
          onPressed: _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

class _ParticipantNameSourceOption extends StatelessWidget {
  const _ParticipantNameSourceOption({
    required this.title,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final IconData icon;
  final bool value;
  final bool selected;
  final VoidCallback? onTap;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveOnTap = enabled ? onTap : null;
    final borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    final foreground = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: effectiveOnTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 22,
                color: enabled ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: enabled
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Radio<bool>(
                value: value,
                enabled: enabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantRow {
  const _ParticipantRow({
    required this.participantId,
    required this.userId,
    required this.isClaimed,
    required this.rawParticipantName,
    required this.useProfileName,
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
  final String displayLabel;
  final bool isAdmin;
  final bool likedByMe;
  final Map<String, dynamic>? profileData;
  final String? phoneUri;
}
