import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/cupidon/data/cupidon_repository.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_member_profile_repository.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trip_placeholder_member.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
import 'package:url_launcher/url_launcher.dart';

/// Trip member list: placeholders (voyageurs prévus) and participants who have
/// already joined (profile labels). Invite flow still lists only `ph_*` rows
/// via [getInviteJoinContext].
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

  Stream<Map<String, Map<String, dynamic>>> _usersDataStreamFor(Trip trip) {
    final realIds = trip.memberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .where((id) => !isTripPlaceholderMemberId(id))
        .toList();
    final sorted = [...realIds]..sort();
    final key = sorted.join('\x1e');
    if (_usersDataStreamKey == key && _usersDataStreamCache != null) {
      return _usersDataStreamCache!;
    }
    _usersDataStreamKey = key;
    _usersDataStreamCache =
        ref.read(usersRepositoryProvider).watchUsersDataByIds(realIds);
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
      await ref.read(tripsRepositoryProvider).addTripPlaceholderMember(
            tripId: widget.tripId,
            displayName: name,
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

  Future<void> _openEditPlaceholderDialog({
    required String placeholderId,
    required String currentName,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tripParticipantsEditNameTitle),
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
            child: Text(l10n.commonSave),
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
      await ref.read(tripsRepositoryProvider).updateTripPlaceholderMemberName(
            tripId: widget.tripId,
            placeholderId: placeholderId,
            displayName: name,
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

  Future<void> _confirmRemovePlaceholder({
    required String placeholderId,
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
      await ref.read(tripsRepositoryProvider).removeTripPlaceholderMember(
            tripId: widget.tripId,
            placeholderId: placeholderId,
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
        final membersPhoneVisibilityAsync =
            ref.watch(tripMembersPhoneVisibilityStreamProvider(widget.tripId));
        final usersStream = _usersDataStreamFor(trip);
        return StreamBuilder<Map<String, Map<String, dynamic>>>(
          stream: usersStream,
          builder: (context, userSnap) {
            final userDataById = userSnap.data ?? const {};
            final enabledCupidonMemberIds =
                cupidonEnabledAsync.asData?.value ?? const <String>{};
            final likedByMe = myLikesAsync.asData?.value ?? const <String>{};
            final membersPhoneVisibility =
                membersPhoneVisibilityAsync.asData?.value ?? const {};
            final currentUserRole = resolveTripPermissionRole(
              trip: trip,
              userId: myUid,
            );
            final rows = _participantRowsForTrip(
              trip,
              userDataById,
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
            final canCreateParticipant = isTripRoleAllowed(
              currentRole: currentRole,
              minRole: trip.participantsPermissions.createParticipantMinRole,
            );
            final canDeletePlaceholderParticipant = isTripRoleAllowed(
              currentRole: currentRole,
              minRole:
                  trip.participantsPermissions.deletePlaceholderParticipantMinRole,
            );
            final canEditPlaceholderParticipant = isTripRoleAllowed(
              currentRole: currentRole,
              minRole: trip.participantsPermissions.editPlaceholderParticipantMinRole,
            );
            final canDeleteRegisteredParticipant = isTripRoleAllowed(
              currentRole: currentRole,
              minRole:
                  trip.participantsPermissions.deleteRegisteredParticipantMinRole,
            );
            final canToggleAdminRole = isTripRoleAllowed(
              currentRole: currentRole,
              minRole: trip.participantsPermissions.toggleAdminRoleMinRole,
            );
            final canManageParticipants = canCreateParticipant ||
                canEditPlaceholderParticipant ||
                canDeletePlaceholderParticipant ||
                canDeleteRegisteredParticipant ||
                canToggleAdminRole;
            final myCupidonEnabled =
                enabledCupidonMemberIds.contains((myUid ?? '').trim());
            final searchQuery = _participantSearchController.text;
            final visibleRows = rows
                .where(
                  (r) =>
                      displayNameMatchesNameSearch(r.displayLabel, searchQuery),
                )
                .toList();

            return Scaffold(
              appBar: AppBar(title: Text(l10n.tripParticipantsTitle)),
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
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  itemCount: visibleRows.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final row = visibleRows[index];
                                    final isOwnerRow = row.memberId.trim() ==
                                        trip.ownerId.trim();
                                    final canRemoveMember =
                                        canDeleteRegisteredParticipant &&
                                            !row.isPlaceholder &&
                                            !isOwnerRow &&
                                            row.memberId.trim() != myUidTrim;

                                    final isRemoving = _removingMemberIds
                                        .contains(row.memberId.trim());
                                    final isCycling = _cyclingMemberIds
                                        .contains(row.memberId.trim());
                                    final scheme =
                                        Theme.of(context).colorScheme;
                                    final canCycleRole =
                                        canToggleAdminRole && !isOwnerRow;

                                    return Card(
                                      child: ListTile(
                                        leading: _participantRoleLeading(
                                          context: context,
                                          scheme: scheme,
                                          row: row,
                                          isOwnerRow: isOwnerRow,
                                          showAdminIcon: row.isAdmin,
                                          canCycleRole: canCycleRole,
                                          isCycling: isCycling,
                                          onCycle: canCycleRole && !isCycling
                                              ? () => _cycleMemberAdminRole(
                                                    memberId: row.memberId,
                                                    displayLabel:
                                                        row.displayLabel,
                                                    wasAdmin: row.isAdmin,
                                                  )
                                              : null,
                                        ),
                                        title: Text(row.displayLabel),
                                        trailing: row.isPlaceholder &&
                                                (canCreateParticipant ||
                                                    canEditPlaceholderParticipant ||
                                                    canDeletePlaceholderParticipant)
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (canEditPlaceholderParticipant)
                                                    IconButton(
                                                      tooltip: l10n.commonEdit,
                                                      icon: const Icon(
                                                          Icons.edit_outlined),
                                                      onPressed: () =>
                                                          _openEditPlaceholderDialog(
                                                        placeholderId:
                                                            row.memberId,
                                                        currentName:
                                                            row.displayLabel,
                                                      ),
                                                    ),
                                                  if (canDeletePlaceholderParticipant)
                                                    IconButton(
                                                      tooltip: l10n.tripParticipantsRemoveAction,
                                                      icon: Icon(Icons.delete,
                                                          color: Theme.of(context).colorScheme.error),
                                                      onPressed: () =>
                                                          _confirmRemovePlaceholder(
                                                        placeholderId:
                                                            row.memberId,
                                                        label: row.displayLabel,
                                                      ),
                                                    ),
                                                ],
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (row.phoneUri != null)
                                                    IconButton(
                                                      tooltip: l10n.tripParticipantsOpenDialer,
                                                      icon: const Icon(Icons.phone_outlined),
                                                      onPressed: () => launchUrl(
                                                        Uri.parse(row.phoneUri!),
                                                      ),
                                                    ),
                                                  if (!row.isPlaceholder &&
                                                      row.memberId.trim() !=
                                                          myUidTrim &&
                                                      myCupidonEnabled)
                                                    IconButton(
                                                      tooltip: row.likedByMe
                                                          ? l10n.tripParticipantsUnlike
                                                          : l10n.tripParticipantsLike,
                                                      onPressed: _likingMemberIds
                                                              .contains(row
                                                                  .memberId
                                                                  .trim())
                                                          ? null
                                                          : () =>
                                                              _toggleCupidonLike(
                                                                targetMemberId:
                                                                    row.memberId,
                                                                currentlyLiked:
                                                                    row.likedByMe,
                                                              ),
                                                      icon: _likingMemberIds
                                                              .contains(row
                                                                  .memberId
                                                                  .trim())
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
                                                                  ? Icons
                                                                      .favorite
                                                                  : Icons
                                                                      .favorite_border,
                                                              color: Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .error,
                                                            ),
                                                    ),
                                                  if (canRemoveMember)
                                                    IconButton(
                                                      tooltip: l10n.tripParticipantsRemoveAction,
                                                      icon: isRemoving
                                                          ? const SizedBox(
                                                              width: 22,
                                                              height: 22,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                            )
                                                          : Icon(Icons.delete,
                                                              color: Theme.of(context).colorScheme.error),
                                                      onPressed: isRemoving
                                                          ? null
                                                          : () =>
                                                              _confirmRemoveMember(
                                                                memberId: row
                                                                    .memberId,
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
              floatingActionButton: canCreateParticipant
                  ? FloatingActionButton(
                      onPressed: _openAddDialog,
                      tooltip: l10n.tripParticipantsAddPlannedTravelerTitle,
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
        body: Center(child: Text(l10n.commonErrorWithDetails(e.toString()))),
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
  final account = (profileData['account'] as Map<String, dynamic>?) ?? const {};
  final code = (account['phoneCountryCode'] as String?)?.trim() ?? '';
  final number = (account['phoneNumber'] as String?)?.trim() ?? '';
  if (number.isEmpty) return null;
  return 'tel:$code${number.replaceAll(' ', '')}';
}

List<_ParticipantRow> _participantRowsForTrip(
  Trip trip,
  Map<String, Map<String, dynamic>> userDataById,
  String? myUid, {
  required AppLocalizations l10n,
  required Set<String> enabledCupidonMemberIds,
  required Set<String> likedByMe,
  required Map<String, TripMemberPhoneVisibility> membersPhoneVisibility,
  required TripPermissionRole currentUserRole,
}) {
  final labels = trip.memberPublicLabels;
  final rows = trip.memberIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .map((id) {
    if (isTripPlaceholderMemberId(id)) {
      final label = (labels[id]?.trim().isNotEmpty ?? false)
          ? labels[id]!.trim()
          : l10n.tripParticipantsTraveler;
      return _ParticipantRow(
        memberId: id,
        isPlaceholder: true,
        displayLabel: label,
        isAdmin: trip.memberHasAdminRole(id),
        likedByMe: false,
      );
    }
    final profileData = userDataById[id];
    final label = resolveTripMemberDisplayLabel(
      memberId: id,
      userData: profileData,
      tripMemberPublicLabels: labels,
      currentUserId: myUid,
      emptyFallback: l10n.tripParticipantsUser,
    );
    final phoneUri = id == (myUid ?? '').trim()
        ? null
        : _phoneUriForMember(
            profileData: profileData,
            visibility: membersPhoneVisibility[id],
            currentUserRole: currentUserRole,
          );
    return _ParticipantRow(
      memberId: id,
      isPlaceholder: false,
      displayLabel: label,
      isAdmin: trip.memberHasAdminRole(id),
      likedByMe: likedByMe.contains(id),
      profileData: profileData,
      phoneUri: phoneUri,
    );
  }).toList();
  rows.sort(
    (a, b) => compareDisplayNamesForSort(a.displayLabel, b.displayLabel),
  );
  return rows;
}

/// Same box for every row so [ListTile.leading] lines up (plain [Icon] vs
/// default [IconButton] padding was shifting “joined” members vs placeholders).
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
            : (showAdminIcon ? AppLocalizations.of(context)!.roleAdmin : null));

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

  return SizedBox(
    width: _kParticipantRoleLeadingExtent,
    height: _kParticipantRoleLeadingExtent,
    child: GestureDetector(
      onLongPress: onCycle,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: _kParticipantRoleLeadingExtent,
          height: _kParticipantRoleLeadingExtent,
        ),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: icon,
        tooltip: tooltip,
        onPressed: null,
      ),
    ),
  );
}

class _ParticipantRow {
  const _ParticipantRow({
    required this.memberId,
    required this.isPlaceholder,
    required this.displayLabel,
    required this.isAdmin,
    required this.likedByMe,
    this.profileData,
    this.phoneUri,
  });

  final String memberId;
  final bool isPlaceholder;
  final String displayLabel;
  final bool isAdmin;
  final bool likedByMe;
  final Map<String, dynamic>? profileData;
  final String? phoneUri;
}
