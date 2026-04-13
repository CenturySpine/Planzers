import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/auth/data/users_repository.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trip_placeholder_member.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';

/// Trip member list: placeholders (voyageurs prévus) and participants who have
/// already joined (profile labels). Invite flow still lists only `ph_*` rows
/// via [getInviteJoinContext].
class TripParticipantsPage extends ConsumerStatefulWidget {
  const TripParticipantsPage({super.key, required this.tripId});

  final String tripId;

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
      final label = displayLabel.trim().isEmpty ? 'Ce participant' : displayLabel;
      final message = wasAdmin
          ? 'Rôle administrateur retiré ($label).'
          : '$label est administrateur.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
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

  @override
  Widget build(BuildContext context) {
    final asyncTrip = ref.watch(tripStreamProvider(widget.tripId));
    final myUid = FirebaseAuth.instance.currentUser?.uid;

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
            final rows = _participantRowsForTrip(trip, userDataById, myUid);
            final iamAdmin = trip.isTripAdmin(myUid);

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
                        if (iamAdmin)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Text(
                              'Clique sur l’icône à gauche d’un participant '
                              'pour lui donner ou retirer le rôle administrateur '
                              '(sauf le créateur).',
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
                        Expanded(
                          child: ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              iamAdmin ? 8 : 16,
                              16,
                              16,
                            ),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final isOwnerRow =
                                  row.memberId.trim() == trip.ownerId.trim();
                              final canRemoveMember = !row.isPlaceholder &&
                                  !isOwnerRow &&
                                  row.memberId.trim() != (myUid ?? '').trim();

                              final isRemoving = _removingMemberIds
                                  .contains(row.memberId.trim());
                              final isCycling = _cyclingMemberIds
                                  .contains(row.memberId.trim());
                              final scheme = Theme.of(context).colorScheme;
                              final canCycleRole =
                                  iamAdmin && !row.isPlaceholder && !isOwnerRow;

                              return Card(
                                child: ListTile(
                                  leading: _participantRoleLeading(
                                    scheme: scheme,
                                    row: row,
                                    isOwnerRow: isOwnerRow,
                                    showAdminIcon: row.isAdmin,
                                    canCycleRole: canCycleRole,
                                    isCycling: isCycling,
                                    onCycle: canCycleRole && !isCycling
                                        ? () => _cycleMemberAdminRole(
                                              memberId: row.memberId,
                                              displayLabel: row.displayLabel,
                                              wasAdmin: row.isAdmin,
                                            )
                                        : null,
                                  ),
                                  title: Text(row.displayLabel),
                                  trailing: row.isPlaceholder
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Modifier',
                                              icon: const Icon(
                                                  Icons.edit_outlined),
                                              onPressed: () =>
                                                  _openEditPlaceholderDialog(
                                                placeholderId: row.memberId,
                                                currentName: row.displayLabel,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Retirer',
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              onPressed: () =>
                                                  _confirmRemovePlaceholder(
                                                placeholderId: row.memberId,
                                                label: row.displayLabel,
                                              ),
                                            ),
                                          ],
                                        )
                                      : canRemoveMember
                                          ? IconButton(
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
                                                  : const Icon(
                                                      Icons.delete_outline),
                                              onPressed: isRemoving
                                                  ? null
                                                  : () => _confirmRemoveMember(
                                                        memberId: row.memberId,
                                                        label:
                                                            row.displayLabel,
                                                      ),
                                            )
                                          : null,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
              floatingActionButton: FloatingActionButton(
                onPressed: _openAddDialog,
                tooltip: 'Ajouter un voyageur prévu',
                child: const Icon(Icons.add),
              ),
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
  String? myUid,
) {
  final labels = trip.memberPublicLabels;
  return trip.memberIds
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
            isAdmin: false,
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
        );
      })
      .toList();
}

/// Same box for every row so [ListTile.leading] lines up (plain [Icon] vs
/// default [IconButton] padding was shifting “joined” members vs placeholders).
const double _kParticipantRoleLeadingExtent = 48;

Widget _participantRoleLeading({
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

  if (row.isPlaceholder) {
    return inFixedBox(
      Icon(
        Icons.person_outline,
        color: scheme.outline,
      ),
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
      : (isOwnerRow
          ? 'Créateur'
          : (showAdminIcon ? 'Administrateur' : null));

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
      icon: Icon(
        showAdminIcon
            ? Icons.admin_panel_settings_outlined
            : Icons.person_outline,
        color: showAdminIcon ? scheme.primary : scheme.onSurfaceVariant,
      ),
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
  });

  final String memberId;
  final bool isPlaceholder;
  final String displayLabel;
  final bool isAdmin;
}
