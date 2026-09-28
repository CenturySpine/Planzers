import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/core/presentation/pz_components.dart';
import 'package:planerz/features/rooms/data/rooms_repository.dart';
import 'package:planerz/features/rooms/data/trip_room.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripRoomsPage extends ConsumerWidget {
  const TripRoomsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(trip.id));
    final roomsAsync = ref.watch(tripRoomsStreamProvider(trip.id));

    return Scaffold(
      body: roomsAsync.when(
        data: (rooms) => _TripRoomsBody(
          tripId: trip.id,
          memberLabels: memberLabels,
          rooms: rooms,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.commonErrorWithDetails(error.toString()),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'trip_rooms_add',
        tooltip: l10n.roomsCreate,
        onPressed: () => _openCreateRoomSheet(context, ref, tripId: trip.id),
        child: const Icon(PhosphorIconsRegular.plus),
      ),
    );
  }
}

class _TripRoomsBody extends StatefulWidget {
  const _TripRoomsBody({
    required this.tripId,
    required this.memberLabels,
    required this.rooms,
  });

  final String tripId;
  final Map<String, String> memberLabels;
  final List<TripRoom> rooms;

  @override
  State<_TripRoomsBody> createState() => _TripRoomsBodyState();
}

class _TripRoomsBodyState extends State<_TripRoomsBody> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Matches the room name or the name of any of its occupants.
  bool _matchesQuery(TripRoom room) {
    if (displayNameMatchesNameSearch(room.name, _query)) return true;
    return room.assignedMemberIds.any((id) {
      final label = widget.memberLabels[id];
      return label != null && displayNameMatchesNameSearch(label, _query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rooms = widget.rooms;
    if (rooms.isEmpty) {
      return PzEmptyState(
        icon: ActivityFilterGroup.nuits.filterIcon,
        title: l10n.roomsCreateTitle,
      );
    }
    final capacity = rooms.fold<int>(0, (sum, r) => sum + r.capacity);
    final assigned =
        rooms.fold<int>(0, (sum, r) => sum + r.assignedMemberIds.length);
    final visibleRooms = rooms.where(_matchesQuery).toList()
      ..sort((a, b) => _compareRoomNames(a.name, b.name));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      children: [
        PzSectionHeader(
          title: l10n.tripOverviewTileRooms,
          count: rooms.length,
          trailing: _OccupancyPill(assigned: assigned, capacity: capacity),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: NameListSearchTextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        if (visibleRooms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              l10n.nameSearchEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (final room in visibleRooms)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RoomCard(
              room: room,
              memberLabels: widget.memberLabels,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _TripRoomDetailPage(
                      tripId: widget.tripId,
                      roomId: room.id,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

final _digitsOrText = RegExp(r'\d+|\D+');

/// Case-insensitive alphabetical order, with numbers compared by value so
/// that "Chambre 2" comes before "Chambre 10".
int _compareRoomNames(String a, String b) {
  final chunksA = _digitsOrText
      .allMatches(a.trim().toLowerCase())
      .map((m) => m[0]!)
      .toList();
  final chunksB = _digitsOrText
      .allMatches(b.trim().toLowerCase())
      .map((m) => m[0]!)
      .toList();
  for (var i = 0; i < chunksA.length && i < chunksB.length; i++) {
    final numA = int.tryParse(chunksA[i]);
    final numB = int.tryParse(chunksB[i]);
    final result = numA != null && numB != null
        ? numA.compareTo(numB)
        : chunksA[i].compareTo(chunksB[i]);
    if (result != 0) return result;
  }
  return chunksA.length.compareTo(chunksB.length);
}

class _OccupancyPill extends StatelessWidget {
  const _OccupancyPill({required this.assigned, required this.capacity});

  final int assigned;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final group = ActivityFilterGroup.nuits;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: group.filterLightBgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsRegular.bed, size: 14, color: group.filterInkColor),
          const SizedBox(width: 4),
          Text(
            '$assigned/$capacity',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: group.filterInkColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.memberLabels,
    required this.onTap,
  });

  final TripRoom room;
  final Map<String, String> memberLabels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final group = ActivityFilterGroup.nuits;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: group.filterLightBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(group.filterIcon,
                        size: 19, color: group.filterColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      room.name.isEmpty ? l10n.roomsUnnamedRoom : room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _OccupancyPill(
                    assigned: room.assignedMemberIds.length,
                    capacity: room.capacity,
                  ),
                  const Icon(PhosphorIconsRegular.caretRight,
                      color: Color(0xFF8891A1)),
                ],
              ),
              const SizedBox(height: 6),
              for (final bed in room.beds)
                Padding(
                  padding: const EdgeInsets.only(left: 44, top: 4, right: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        bed.type == TripBedType.double
                            ? PhosphorIconsRegular.bed
                            : PhosphorIconsRegular.bed,
                        size: 17,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.roomsBedTypeAndKind(
                          bed.type == TripBedType.double
                              ? l10n.roomsBedTypeDouble
                              : l10n.roomsBedTypeSingle,
                          bed.kind == TripBedKind.extra
                              ? l10n.roomsBedKindExtra
                              : l10n.roomsBedKindRegular,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: bed.assignedMemberIds.isEmpty
                              ? [
                                  Text(
                                    l10n.commonDash,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ]
                              : [
                                  for (final id in bed.assignedMemberIds)
                                    PzPersonChip(
                                      label: memberLabels[id] ??
                                          l10n.tripParticipantsTraveler,
                                    ),
                                ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripRoomDetailPage extends ConsumerStatefulWidget {
  const _TripRoomDetailPage({
    required this.tripId,
    required this.roomId,
  });

  final String tripId;
  final String roomId;

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
    final l10n = AppLocalizations.of(context)!;
    for (final draft in _otherRoomDraftsById.values) {
      for (final bed in draft.editableBeds) {
        if (bed.assignedMemberIds.contains(memberId)) {
          return draft.roomName.isEmpty ? l10n.roomsUnnamedRoom : draft.roomName;
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
    final l10n = AppLocalizations.of(context)!;
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;
    if (_beds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.roomsAddAtLeastOneBed)),
      );
      return;
    }
    for (final bed in _beds) {
      if (bed.assignedMemberIds.length > bed.capacity) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.roomsBedCapacityExceeded)),
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
        SnackBar(content: Text(l10n.roomsUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(TripRoom room) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.roomsDeleteTitle),
        content: Text(
          l10n.roomsDeleteBody(
            room.name.isEmpty ? l10n.roomsRoomLabel : room.name,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
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
        SnackBar(content: Text(l10n.roomsDeleted)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final participants =
        ref.watch(tripParticipantsStreamProvider(widget.tripId)).asData?.value ?? [];
    final memberLabels =
        ref.watch(tripMemberResolvedLabelsProvider(widget.tripId));
    final memberIds = participants.map((m) => m.id).toList();
    final roomsAsync = ref.watch(tripRoomsStreamProvider(widget.tripId));

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

        return Scaffold(
          appBar: AppBar(
            title: Text(
              room.name.isEmpty ? l10n.roomsUnnamedRoom : room.name,
            ),
            actions: [
              if (_editing) ...[
                IconButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _editing = false;
                            _setupEditorState(room, rooms);
                          }),
                  icon: const Icon(PhosphorIconsRegular.x),
                ),
                IconButton(
                  onPressed: _saving ? null : () => _save(room),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsRegular.check),
                ),
              ] else ...[
                IconButton(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(PhosphorIconsRegular.pencilSimple),
                ),
                IconButton(
                  onPressed: () => _delete(room),
                  icon: Icon(PhosphorIconsRegular.trash, color: Theme.of(context).colorScheme.error),
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
                        decoration: InputDecoration(
                          labelText: l10n.commonName,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? l10n.roomsNameRequired
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
                              l10n.roomsBedSummary(
                                i + 1,
                                _beds[i].type == TripBedType.double
                                    ? l10n.roomsBedTypeDouble
                                    : l10n.roomsBedTypeSingle,
                                _beds[i].kind == TripBedKind.extra
                                    ? l10n.roomsBedKindExtra
                                    : l10n.roomsBedKindRegular,
                              ),
                            ),
                            subtitle: _beds[i].assignedMemberIds.isEmpty
                                ? null
                                : Text(
                                    _beds[i]
                                        .assignedMemberIds
                                        .map((id) =>
                                            memberLabels[id] ??
                                            l10n.tripParticipantsTraveler)
                                        .join(', '),
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_beds.length > 1)
                                  IconButton(
                                    icon: Icon(PhosphorIconsRegular.trash, color: Theme.of(context).colorScheme.error),
                                    onPressed: () => setState(() {
                                      _beds = [..._beds]..removeAt(i);
                                    }),
                                  ),
                                const Icon(PhosphorIconsRegular.caretDown),
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
                                      items: [
                                        DropdownMenuItem(
                                          value: TripBedType.single,
                                          child: Text(l10n.roomsBedTypeSingle),
                                        ),
                                        DropdownMenuItem(
                                          value: TripBedType.double,
                                          child: Text(l10n.roomsBedTypeDouble),
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
                                      items: [
                                        DropdownMenuItem(
                                          value: TripBedKind.regular,
                                          child: Text(l10n.roomsBedKindRegular),
                                        ),
                                        DropdownMenuItem(
                                          value: TripBedKind.extra,
                                          child: Text(l10n.roomsBedKindExtra),
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
                              ..._orderedMemberIdsForBed(memberIds, i).map(
                                (memberId) {
                                  final otherRoom = _assignedOtherRoomName(memberId);
                                  return CheckboxListTile(
                                    dense: true,
                                    visualDensity:
                                        const VisualDensity(horizontal: -4, vertical: -4),
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    title: Text(
                                      memberLabels[memberId] ??
                                          l10n.tripParticipantsTraveler,
                                    ),
                                    subtitle: otherRoom == null
                                        ? null
                                        : Text(
                                            l10n.roomsAlreadyAssigned(otherRoom),
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
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  l10n.roomsThisBedCapacityReached,
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
                        icon: const Icon(PhosphorIconsRegular.plus),
                        label: Text(l10n.roomsAddBed),
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
                          child: _BedLine(index: i, bed: room.beds[i], labels: memberLabels),
                        ),
                      ),
                  ],
                ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(
          child: Text(l10n.commonErrorWithDetails(error.toString())),
        ),
      ),
    );
  }
}

Future<void> _openCreateRoomSheet(
  BuildContext context,
  WidgetRef ref, {
  required String tripId,
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
  bool _defaultNameInitialized = false;
  List<_EditableBed> _beds = <_EditableBed>[
    _EditableBed(type: TripBedType.double, kind: TripBedKind.regular),
  ];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_defaultNameInitialized) return;
    _defaultNameInitialized = true;
    final l10n = AppLocalizations.of(context)!;
    _nameController.text = '${l10n.roomsRoomLabel} ${widget.allRooms.length + 1}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
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
        SnackBar(content: Text(l10n.roomsCreated)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.roomsCreateTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.commonName,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? l10n.roomsNameRequired
                        : null,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _beds.length; i++)
                Card(
                  child: ListTile(
                    title: Text(l10n.roomsBedLabel(i + 1)),
                    subtitle: Text(
                      l10n.roomsBedTypeAndKind(
                        _beds[i].type == TripBedType.double
                            ? l10n.roomsBedTypeDouble
                            : l10n.roomsBedTypeSingle,
                        _beds[i].kind == TripBedKind.extra
                            ? l10n.roomsBedKindExtra
                            : l10n.roomsBedKindRegular,
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: _beds.length <= 1
                          ? null
                          : () => setState(() {
                                _beds = [..._beds]..removeAt(i);
                              }),
                      icon: Icon(PhosphorIconsRegular.trash, color: Theme.of(context).colorScheme.error),
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
                icon: const Icon(PhosphorIconsRegular.plus),
                label: Text(l10n.roomsAddBed),
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
                    : Text(l10n.roomsCreate),
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
    final l10n = AppLocalizations.of(context)!;
    final typeLabel =
        bed.type == TripBedType.double ? l10n.roomsBedTypeDouble : l10n.roomsBedTypeSingle;
    final kindLabel =
        bed.kind == TripBedKind.extra ? l10n.roomsBedKindExtra : l10n.roomsBedKindRegular;
    final assigned = bed.assignedMemberIds;
    final assignedLabel = assigned.isEmpty
        ? '-'
        : assigned
            .map((id) => labels[id] ?? l10n.tripParticipantsTraveler)
            .join(', ');
    return Text(l10n.roomsBedLine(index + 1, typeLabel, kindLabel, assignedLabel));
  }
}
