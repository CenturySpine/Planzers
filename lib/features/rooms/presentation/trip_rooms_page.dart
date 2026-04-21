import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/rooms/data/rooms_repository.dart';
import 'package:planerz/features/rooms/data/trip_room.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';

class TripRoomsPage extends ConsumerWidget {
  const TripRoomsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = TripScope.of(context);
    final roomsAsync = ref.watch(tripRoomsStreamProvider(trip.id));

    return Scaffold(
      body: roomsAsync.when(
        data: (rooms) => _TripRoomsBody(
          tripId: trip.id,
          memberIds: trip.memberIds,
          memberPublicLabels: trip.memberPublicLabels,
          rooms: rooms,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erreur: $error', textAlign: TextAlign.center),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'trip_rooms_add',
        tooltip: 'Créer',
        onPressed: () => _openCreateRoomSheet(
          context,
          ref,
          tripId: trip.id,
          memberIds: trip.memberIds,
          memberPublicLabels: trip.memberPublicLabels,
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TripRoomsBody extends StatelessWidget {
  const _TripRoomsBody({
    required this.tripId,
    required this.memberIds,
    required this.memberPublicLabels,
    required this.rooms,
  });

  final String tripId;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final List<TripRoom> rooms;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return const SizedBox.shrink();
    }
    final cleanMemberIds =
        memberIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toList();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: cleanMemberIds.isEmpty
          ? null
          : FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: cleanMemberIds)
              .snapshots(),
      builder: (context, snapshot) {
        final labels = tripMemberLabelsFromUserQuerySnapshot(
          snapshot.data,
          cleanMemberIds,
          tripMemberPublicLabels: memberPublicLabels,
          currentUserId: FirebaseAuth.instance.currentUser?.uid,
          emptyFallback: 'Voyageur',
        );

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rooms.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final room = rooms[index];
            final assignedNames = room.assignedMemberIds
                .map((id) => labels[id] ?? 'Voyageur')
                .join(', ');
            return Card(
              child: ListTile(
                title: Text(room.name.isEmpty ? 'Chambre sans nom' : room.name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(assignedNames.isEmpty ? '-' : assignedNames),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _TripRoomDetailPage(
                        tripId: tripId,
                        roomId: room.id,
                        memberIds: memberIds,
                        memberPublicLabels: memberPublicLabels,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _TripRoomDetailPage extends ConsumerStatefulWidget {
  const _TripRoomDetailPage({
    required this.tripId,
    required this.roomId,
    required this.memberIds,
    required this.memberPublicLabels,
  });

  final String tripId;
  final String roomId;
  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;

  @override
  ConsumerState<_TripRoomDetailPage> createState() => _TripRoomDetailPageState();
}

class _TripRoomDetailPageState extends ConsumerState<_TripRoomDetailPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final Map<String, _OtherRoomDraft> _otherRoomDraftsById = <String, _OtherRoomDraft>{};
  List<_EditableBed> _beds = <_EditableBed>[];
  bool _editing = false;
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _setupEditorState(TripRoom room, List<TripRoom> allRooms) {
    _nameController.text = room.name;
    _beds = room.beds
        .map(
          (b) => _EditableBed(
            type: b.type,
            kind: b.kind,
            assignedMemberIds: b.assignedMemberIds.toSet(),
          ),
        )
        .toList();
    _otherRoomDraftsById.clear();
    for (final otherRoom in allRooms) {
      if (otherRoom.id == room.id) continue;
      _otherRoomDraftsById[otherRoom.id] = _OtherRoomDraft(
        roomId: otherRoom.id,
        roomName: otherRoom.name,
        originalBeds: otherRoom.beds,
      );
    }
    _initialized = true;
  }

  void _removeMemberFromAllBeds(String memberId) {
    for (final bed in _beds) {
      bed.assignedMemberIds.remove(memberId);
    }
  }

  void _removeMemberFromOtherRooms(String memberId) {
    for (final draft in _otherRoomDraftsById.values) {
      var changed = false;
      for (final bed in draft.editableBeds) {
        if (bed.assignedMemberIds.remove(memberId)) changed = true;
      }
      if (changed) draft.changed = true;
    }
  }

  bool _isAssignedElsewhereInCurrentRoom(String memberId, int currentBedIndex) {
    for (var i = 0; i < _beds.length; i++) {
      if (i == currentBedIndex) continue;
      if (_beds[i].assignedMemberIds.contains(memberId)) return true;
    }
    return false;
  }

  String? _assignedOtherRoomName(String memberId) {
    for (final draft in _otherRoomDraftsById.values) {
      for (final bed in draft.editableBeds) {
        if (bed.assignedMemberIds.contains(memberId)) {
          return draft.roomName.isEmpty ? 'Sans nom' : draft.roomName;
        }
      }
    }
    return null;
  }

  List<String> _orderedMemberIdsForBed(List<String> ids, int bedIndex) {
    final primary = <String>[];
    final secondary = <String>[];
    for (final id in ids) {
      final assignedCurrentBed = _beds[bedIndex].assignedMemberIds.contains(id);
      final assignedCurrentRoom = _beds.any((bed) => bed.assignedMemberIds.contains(id));
      final assignedOtherRoom = _assignedOtherRoomName(id) != null;
      if (assignedCurrentBed || assignedCurrentRoom || !assignedOtherRoom) {
        primary.add(id);
      } else {
        secondary.add(id);
      }
    }
    return [...primary, ...secondary];
  }

  Future<void> _save(TripRoom room) async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;
    if (_beds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute au moins un lit')),
      );
      return;
    }
    for (final bed in _beds) {
      if (bed.assignedMemberIds.length > bed.capacity) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capacité d un lit dépassée')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await ref.read(roomsRepositoryProvider).updateRoom(
            tripId: widget.tripId,
            roomId: room.id,
            name: _nameController.text.trim(),
            beds: _beds
                .map(
                  (bed) => TripRoomBed(
                    type: bed.type,
                    kind: bed.kind,
                    assignedMemberIds: bed.assignedMemberIds.toList(),
                  ),
                )
                .toList(),
          );
      for (final draft in _otherRoomDraftsById.values) {
        if (!draft.changed) continue;
        await ref.read(roomsRepositoryProvider).updateRoom(
              tripId: widget.tripId,
              roomId: draft.roomId,
              name: draft.roomName,
              beds: draft.editableBeds
                  .map(
                    (bed) => TripRoomBed(
                      type: bed.type,
                      kind: bed.kind,
                      assignedMemberIds: bed.assignedMemberIds.toList(),
                    ),
                  )
                  .toList(),
            );
      }
      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chambre mise à jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(TripRoom room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la chambre ?'),
        content: Text('« ${room.name.isEmpty ? 'Chambre' : room.name} » sera supprimée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(roomsRepositoryProvider).deleteRoom(
            tripId: widget.tripId,
            roomId: room.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chambre supprimée')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(tripRoomsStreamProvider(widget.tripId));
    final cleanMemberIds = widget.memberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    return roomsAsync.when(
      data: (rooms) {
        final room = rooms.where((r) => r.id == widget.roomId).firstOrNull;
        if (room == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const SizedBox.shrink(),
          );
        }
        if (!_initialized || !_editing) {
          _setupEditorState(room, rooms);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: cleanMemberIds.isEmpty
              ? null
              : FirebaseFirestore.instance
                  .collection('users')
                  .where(FieldPath.documentId, whereIn: cleanMemberIds)
                  .snapshots(),
          builder: (context, snapshot) {
            final labels = tripMemberLabelsFromUserQuerySnapshot(
              snapshot.data,
              cleanMemberIds,
              tripMemberPublicLabels: widget.memberPublicLabels,
              currentUserId: FirebaseAuth.instance.currentUser?.uid,
              emptyFallback: 'Voyageur',
            );

            return Scaffold(
              appBar: AppBar(
                title: Text(room.name.isEmpty ? 'Chambre sans nom' : room.name),
                actions: [
                  if (_editing) ...[
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                                _editing = false;
                                _setupEditorState(room, rooms);
                              }),
                      icon: const Icon(Icons.close),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => _save(room),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                    ),
                  ] else ...[
                    IconButton(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () => _delete(room),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ],
              ),
              body: _editing
                  ? Form(
                      key: _formKey,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nom',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => (value == null || value.trim().isEmpty)
                                ? 'Nom obligatoire'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          for (var i = 0; i < _beds.length; i++)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ExpansionTile(
                                shape: const Border(),
                                collapsedShape: const Border(),
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 2,
                                ),
                                childrenPadding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                title: Text(
                                  'Lit ${i + 1} · ${_beds[i].type == TripBedType.double ? 'Double' : 'Simple'} · ${_beds[i].kind == TripBedKind.extra ? 'Appoint' : 'Normal'}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_beds.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => setState(() {
                                          _beds = [..._beds]..removeAt(i);
                                        }),
                                      ),
                                    const Icon(Icons.expand_more),
                                  ],
                                ),
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<TripBedType>(
                                          key: ValueKey('type-$i-${_beds[i].type.name}'),
                                          initialValue: _beds[i].type,
                                          isDense: true,
                                          decoration: const InputDecoration(
                                            border: OutlineInputBorder(),
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                              value: TripBedType.single,
                                              child: Text('Simple'),
                                            ),
                                            DropdownMenuItem(
                                              value: TripBedType.double,
                                              child: Text('Double'),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            if (value == null) return;
                                            setState(() {
                                              _beds[i].type = value;
                                              if (_beds[i].assignedMemberIds.length >
                                                  _beds[i].capacity) {
                                                _beds[i].assignedMemberIds = _beds[i]
                                                    .assignedMemberIds
                                                    .take(_beds[i].capacity)
                                                    .toSet();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: DropdownButtonFormField<TripBedKind>(
                                          key: ValueKey('kind-$i-${_beds[i].kind.name}'),
                                          initialValue: _beds[i].kind,
                                          isDense: true,
                                          decoration: const InputDecoration(
                                            border: OutlineInputBorder(),
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                              value: TripBedKind.regular,
                                              child: Text('Normal'),
                                            ),
                                            DropdownMenuItem(
                                              value: TripBedKind.extra,
                                              child: Text('Appoint'),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            if (value == null) return;
                                            setState(() => _beds[i].kind = value);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ..._orderedMemberIdsForBed(cleanMemberIds, i).map(
                                    (memberId) {
                                      final otherRoom = _assignedOtherRoomName(memberId);
                                      return CheckboxListTile(
                                        dense: true,
                                        visualDensity:
                                            const VisualDensity(horizontal: -4, vertical: -4),
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity: ListTileControlAffinity.leading,
                                        title: Text(labels[memberId] ?? 'Voyageur'),
                                        subtitle: otherRoom == null
                                            ? null
                                            : Text(
                                                'deja affecté chambre $otherRoom',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(fontSize: 11),
                                              ),
                                        value: _beds[i].assignedMemberIds.contains(memberId),
                                        onChanged: (checked) {
                                          setState(() {
                                            if (checked == true) {
                                              final alreadyOnBed = _beds[i]
                                                  .assignedMemberIds
                                                  .contains(memberId);
                                              if (!alreadyOnBed &&
                                                  _beds[i].assignedMemberIds.length >=
                                                      _beds[i].capacity) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Capacité de ce lit atteinte',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              if (_isAssignedElsewhereInCurrentRoom(
                                                memberId,
                                                i,
                                              )) {
                                                _removeMemberFromAllBeds(memberId);
                                              }
                                              _removeMemberFromOtherRooms(memberId);
                                              _beds[i].assignedMemberIds.add(memberId);
                                            } else {
                                              _beds[i].assignedMemberIds.remove(memberId);
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _beds = [
                                ..._beds,
                                _EditableBed(
                                  type: TripBedType.single,
                                  kind: TripBedKind.regular,
                                ),
                              ];
                            }),
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter un lit'),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text('${room.occupancy}/${room.capacity}'),
                        const SizedBox(height: 12),
                        for (var i = 0; i < room.beds.length; i++)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: _BedLine(index: i, bed: room.beds[i], labels: labels),
                            ),
                          ),
                      ],
                    ),
            );
          },
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Erreur: $error'))),
    );
  }
}

Future<void> _openCreateRoomSheet(
  BuildContext context,
  WidgetRef ref, {
  required String tripId,
  required List<String> memberIds,
  required Map<String, String> memberPublicLabels,
}) async {
  final rooms = await ref.read(tripRoomsStreamProvider(tripId).future);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _CreateRoomSheet(
        tripId: tripId,
        allRooms: rooms,
      ),
    ),
  );
}

class _CreateRoomSheet extends ConsumerStatefulWidget {
  const _CreateRoomSheet({
    required this.tripId,
    required this.allRooms,
  });

  final String tripId;
  final List<TripRoom> allRooms;

  @override
  ConsumerState<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends ConsumerState<_CreateRoomSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  List<_EditableBed> _beds = <_EditableBed>[
    _EditableBed(type: TripBedType.double, kind: TripBedKind.regular),
  ];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Chambre ${widget.allRooms.length + 1}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(roomsRepositoryProvider).addRoom(
            tripId: widget.tripId,
            name: _nameController.text.trim(),
            beds: _beds
                .map(
                  (bed) => TripRoomBed(
                    type: bed.type,
                    kind: bed.kind,
                    assignedMemberIds: const [],
                  ),
                )
                .toList(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chambre créée')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Créer une chambre', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Nom obligatoire' : null,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _beds.length; i++)
                Card(
                  child: ListTile(
                    title: Text('Lit ${i + 1}'),
                    subtitle: Text(
                      '${_beds[i].type == TripBedType.double ? 'Double' : 'Simple'} · ${_beds[i].kind == TripBedKind.extra ? 'Appoint' : 'Normal'}',
                    ),
                    trailing: IconButton(
                      onPressed: _beds.length <= 1
                          ? null
                          : () => setState(() {
                                _beds = [..._beds]..removeAt(i);
                              }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _beds = [
                    ..._beds,
                    _EditableBed(type: TripBedType.single, kind: TripBedKind.regular),
                  ];
                }),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un lit'),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Créer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableBed {
  _EditableBed({
    required this.type,
    required this.kind,
    Set<String>? assignedMemberIds,
  }) : assignedMemberIds = assignedMemberIds ?? <String>{};

  TripBedType type;
  TripBedKind kind;
  Set<String> assignedMemberIds;

  int get capacity => type.capacity;
}

class _OtherRoomDraft {
  _OtherRoomDraft({
    required this.roomId,
    required this.roomName,
    required List<TripRoomBed> originalBeds,
  }) : editableBeds = originalBeds
            .map(
              (bed) => _EditableBed(
                type: bed.type,
                kind: bed.kind,
                assignedMemberIds: bed.assignedMemberIds.toSet(),
              ),
            )
            .toList();

  final String roomId;
  final String roomName;
  final List<_EditableBed> editableBeds;
  bool changed = false;
}

class _BedLine extends StatelessWidget {
  const _BedLine({
    required this.index,
    required this.bed,
    required this.labels,
  });

  final int index;
  final TripRoomBed bed;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final typeLabel = bed.type == TripBedType.double ? 'Double' : 'Simple';
    final kindLabel = bed.kind == TripBedKind.extra ? 'Appoint' : 'Normal';
    final assigned = bed.assignedMemberIds;
    final assignedLabel = assigned.isEmpty
        ? '-'
        : assigned.map((id) => labels[id] ?? 'Voyageur').join(', ');
    return Text('Lit ${index + 1} · $typeLabel · $kindLabel · $assignedLabel');
  }
}
