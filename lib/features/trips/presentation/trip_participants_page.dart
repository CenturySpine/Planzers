import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/auth/presentation/profile_badge.dart';
import 'package:planzers/features/cupidon/data/cupidon_repository.dart';
import 'package:planzers/features/auth/data/users_repository.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trip_placeholder_member.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';
import 'package:planzers/features/trips/presentation/name_list_search.dart';

/// Trip member list: placeholders (voyageurs prévus) and participants who have
/// already joined (profile labels). Invite flow still lists only `ph_*` rows
/// via [getInviteJoinContext].
class TripParticipantsPage extends ConsumerStatefulWidget {
  const TripParticipantsPage({
    super.key,
    required this.tripId,
    this.readOnly = false,
  });

  final String tripId;
  final bool readOnly;

  @override
  ConsumerState<TripParticipantsPage> createState() =>
      _TripParticipantsPageState();
}

class _TripParticipantsPageState extends ConsumerState<TripParticipantsPage> {
  static String _messageForError(Object e) {
    if (e is FirebaseFunctionsException) {
      final m = e.message;
      if (m != null && m.trim().isNotEmpty) {
        return m.trim();
      }
    }
    return e.toString();
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
    final cleanId = memberId.trim();
    if (cleanId.isEmpty || _cyclingMemberIds.contains(cleanId)) return;

    setState(() => _cyclingMemberIds.add(cleanId));
    try {
      await ref.read(tripsRepositoryProvider).cycleTripMemberAdminRole(
            tripId: widget.tripId,
            memberId: cleanId,
          );
      if (!mounted) return;
      final label =
          displayLabel.trim().isEmpty ? 'Ce participant' : displayLabel;
      final message = wasAdmin
          ? 'Rôle administrateur retiré ($label).'
          : '$label est administrateur.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’enregistrer ce like pour le moment.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cyclingMemberIds.remove(cleanId));
      }
    }
  }

  Future<void> _openAddDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter un voyageur prévu'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
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
        const SnackBar(content: Text('Voyageur prévu ajouté')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
      );
    }
  }

  Future<void> _openEditPlaceholderDialog({
    required String placeholderId,
    required String currentName,
  }) async {
    final controller = TextEditingController(text: currentName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le nom'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
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
        const SnackBar(content: Text('Nom mis à jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
      );
    }
  }

  Future<void> _confirmRemovePlaceholder({
    required String placeholderId,
    required String label,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer ce voyageur prévu ?'),
        content: Text('« $label » sera retiré des participants.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer'),
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
        const SnackBar(content: Text('Voyageur prévu retiré')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
      );
    }
  }

  Future<void> _confirmRemoveMember({
    required String memberId,
    required String label,
  }) async {
    final cleanId = memberId.trim();
    if (cleanId.isEmpty || _removingMemberIds.contains(cleanId)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer ce participant ?'),
        content: Text('Retirer « $label » du voyage ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer'),
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
        const SnackBar(content: Text('Participant retiré du voyage')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
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
        SnackBar(content: Text(_messageForError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _likingMemberIds.remove(cleanId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            appBar: AppBar(title: const Text('Participants')),
            body: const Center(child: Text('Voyage introuvable')),
          );
        }
        final usersStream = _usersDataStreamFor(trip);
        return StreamBuilder<Map<String, Map<String, dynamic>>>(
          stream: usersStream,
          builder: (context, userSnap) {
            final userDataById = userSnap.data ?? const {};
            final enabledCupidonMemberIds =
                cupidonEnabledAsync.asData?.value ?? const <String>{};
            final likedByMe = myLikesAsync.asData?.value ?? const <String>{};
            final rows = _participantRowsForTrip(
              trip,
              userDataById,
              myUid,
              enabledCupidonMemberIds: enabledCupidonMemberIds,
              likedByMe: likedByMe,
            );
            final iamAdmin = trip.isTripAdmin(myUid);
            final canManageParticipants = iamAdmin && !widget.readOnly;
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
              appBar: AppBar(title: const Text('Participants')),
              body: rows.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aucun participant.',
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
                              'Clique sur l’icône à gauche d’un voyageur '
                              '(prévu ou inscrit) pour lui donner ou retirer '
                              'le rôle administrateur (sauf le créateur).',
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
                                      kNameListSearchEmptyMessage,
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
                                        canManageParticipants &&
                                            !row.isPlaceholder &&
                                            !isOwnerRow &&
                                            row.memberId.trim() !=
                                                (myUid ?? '').trim();

                                    final isRemoving = _removingMemberIds
                                        .contains(row.memberId.trim());
                                    final isCycling = _cyclingMemberIds
                                        .contains(row.memberId.trim());
                                    final scheme =
                                        Theme.of(context).colorScheme;
                                    final canCycleRole =
                                        canManageParticipants && !isOwnerRow;

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
                                                canManageParticipants
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    tooltip: 'Modifier',
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
                                                  IconButton(
                                                    tooltip: 'Retirer',
                                                    icon: const Icon(
                                                        Icons.delete_outline),
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
                                                  if (!row.isPlaceholder &&
                                                      row.memberId.trim() !=
                                                          (myUid ?? '')
                                                              .trim() &&
                                                      myCupidonEnabled)
                                                    IconButton(
                                                      tooltip: row.likedByMe
                                                          ? 'Retirer le like'
                                                          : 'Liker',
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
                                                      tooltip: 'Retirer',
                                                      icon: isRemoving
                                                          ? const SizedBox(
                                                              width: 22,
                                                              height: 22,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                            )
                                                          : const Icon(Icons
                                                              .delete_outline),
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
              floatingActionButton: canManageParticipants
                  ? FloatingActionButton(
                      onPressed: _openAddDialog,
                      tooltip: 'Ajouter un voyageur prévu',
                      child: const Icon(Icons.add),
                    )
                  : null,
            );
          },
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Participants')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Participants')),
        body: Center(child: Text('$e')),
      ),
    );
  }
}

List<_ParticipantRow> _participantRowsForTrip(
  Trip trip,
  Map<String, Map<String, dynamic>> userDataById,
  String? myUid, {
  required Set<String> enabledCupidonMemberIds,
  required Set<String> likedByMe,
}) {
  final labels = trip.memberPublicLabels;
  final rows = trip.memberIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .map((id) {
    if (isTripPlaceholderMemberId(id)) {
      final label = (labels[id]?.trim().isNotEmpty ?? false)
          ? labels[id]!.trim()
          : 'Voyageur';
      return _ParticipantRow(
        memberId: id,
        isPlaceholder: true,
        displayLabel: label,
        isAdmin: trip.memberHasAdminRole(id),
        likedByMe: false,
      );
    }
    final label = resolveTripMemberDisplayLabel(
      memberId: id,
      userData: userDataById[id],
      tripMemberPublicLabels: labels,
      currentUserId: myUid,
      emptyFallback: 'Utilisateur',
    );
    return _ParticipantRow(
      memberId: id,
      isPlaceholder: false,
      displayLabel: label,
      isAdmin: trip.memberHasAdminRole(id),
      likedByMe: likedByMe.contains(id),
      profileData: userDataById[id],
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
      ? 'Changer le rôle'
      : (isOwnerRow ? 'Créateur' : (showAdminIcon ? 'Administrateur' : null));

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
      onPressed: onCycle,
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
  });

  final String memberId;
  final bool isPlaceholder;
  final String displayLabel;
  final bool isAdmin;
  final bool likedByMe;
  final Map<String, dynamic>? profileData;
}
