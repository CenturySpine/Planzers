import 'package:firebase_auth/firebase_auth.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/core/presentation/pz_components.dart';
import 'package:planerz/features/rooms/data/rooms_repository.dart';
import 'package:planerz/features/rooms/data/trip_room.dart';
import 'package:planerz/features/rooms/data/trip_room_lodgings.dart';
import 'package:planerz/features/trips/data/trip_lodging_plan.dart';
import 'package:planerz/features/trips/data/trip_lodgings_repository.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/presentation/name_list_search.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// The trip's rooms, lodging by lodging (one tab each when there are
/// several). A lodging's rooms are shared by all its nights; a night can be
/// set apart with rooms of its own.
class TripRoomsPage extends ConsumerStatefulWidget {
  const TripRoomsPage({super.key});

  @override
  ConsumerState<TripRoomsPage> createState() => _TripRoomsPageState();
}

/// What the page shows for the lodging and night chosen.
enum _RoomsView {
  /// The rooms shared by every night.
  shared,

  /// A night using the shared rooms, shown as they are.
  nightUsingShared,

  /// A night with rooms of its own.
  nightApart,
}

class _TripRoomsPageState extends ConsumerState<TripRoomsPage>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _lodgingIndex = 0;

  /// The night chosen, by lodging (`''` for none); absent for every night.
  final Map<String, String> _nightByLodging = {};

  /// Lodgings whose nights were asked for, before any is set apart.
  final Set<String> _nightsShownByLodging = {};
  bool _busy = false;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  TabController _tabControllerFor(int length) {
    final current = _tabController;
    if (current != null && current.length == length) return current;
    current?.dispose();
    _lodgingIndex = _lodgingIndex.clamp(0, length - 1);
    final controller = TabController(
      length: length,
      initialIndex: _lodgingIndex,
      vsync: this,
    );
    _tabController = controller;
    return controller;
  }

  Future<void> _setNightApart({
    required String tripId,
    required String? lodgingId,
    required String nightKey,
    required List<TripRoom> sharedRooms,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(roomsRepositoryProvider).setNightApart(
            tripId: tripId,
            lodgingId: lodgingId,
            nightKey: nightKey,
            commonRooms: sharedRooms,
          );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useSharedRooms({
    required String tripId,
    required List<TripRoom> nightRooms,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.roomsUseSharedRooms),
        content: Text(l10n.roomsUseSharedRoomsBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(roomsRepositoryProvider).deleteNightRooms(
            tripId: tripId,
            nightRooms: nightRooms,
          );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final canManageRooms = canManageRoomsForTrip(
      trip: trip,
      userId: FirebaseAuth.instance.currentUser?.uid,
    );
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(trip.id));
    final roomsAsync = ref.watch(tripRoomsStreamProvider(trip.id));
    final lodgingsAsync = ref.watch(tripLodgingsStreamProvider(trip.id));
    final storedLodgings = lodgingsAsync.asData?.value;
    final rooms = roomsAsync.asData?.value;
    final error = roomsAsync.error ?? lodgingsAsync.error;

    if (error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.commonErrorWithDetails(error.toString()),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    // Rooms wait for the lodgings, so that none shows under a wrong one.
    if (rooms == null || storedLodgings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final split = TripRoomLodgings.forTrip(
      trip,
      effectiveTripLodgings(trip, storedLodgings),
    );
    final lodgings = split.lodgings;
    final tabController = _tabControllerFor(lodgings.length);
    final lodging = lodgings[_lodgingIndex];
    final lodgingKey = lodging.id ?? '';
    final nightKeys = lodging.nightKeys;
    final nightKey = nightKeys.contains(_nightByLodging[lodgingKey])
        ? _nightByLodging[lodgingKey]
        : null;
    final sharedRooms = split.commonRooms(rooms, lodging.id);
    final nightRooms = nightKey == null
        ? const <TripRoom>[]
        : split.nightRooms(rooms, lodging.id, nightKey);
    final view = nightKey == null
        ? _RoomsView.shared
        : nightRooms.isNotEmpty || sharedRooms.isEmpty
            ? _RoomsView.nightApart
            : _RoomsView.nightUsingShared;
    final shownRooms = switch (view) {
      _RoomsView.shared || _RoomsView.nightUsingShared => sharedRooms,
      _RoomsView.nightApart => nightRooms,
    };
    final nightsApart = {
      for (final key in nightKeys)
        if (split.nightRooms(rooms, lodging.id, key).isNotEmpty) key,
    };

    Widget? action;
    if (canManageRooms && view == _RoomsView.nightUsingShared) {
      action = OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => _setNightApart(
                  tripId: trip.id,
                  lodgingId: lodging.id,
                  nightKey: nightKey!,
                  sharedRooms: sharedRooms,
                ),
        icon: const Icon(PhosphorIconsRegular.copy),
        label: Text(l10n.roomsSetNightApart),
      );
    } else if (canManageRooms &&
        view == _RoomsView.nightApart &&
        nightRooms.isNotEmpty) {
      action = OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => _useSharedRooms(tripId: trip.id, nightRooms: nightRooms),
        icon: const Icon(PhosphorIconsRegular.arrowBendUpLeft),
        label: Text(l10n.roomsUseSharedRooms),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lodgings.length > 1)
            TabBar(
              controller: tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              onTap: (index) => setState(() => _lodgingIndex = index),
              tabs: [
                for (final l in lodgings)
                  Tab(text: l.lodging?.displayTitle ?? l10n.tripLodgingTitle),
              ],
            ),
          // Nights stay out of the way until one is set apart, or asked for.
          if (nightKeys.length > 1 &&
              (nightsApart.isNotEmpty ||
                  _nightByLodging.containsKey(lodgingKey) ||
                  _nightsShownByLodging.contains(lodgingKey)))
            _RoomNightChips(
              nights: lodging.nights,
              selectedKey: nightKey,
              nightsApart: nightsApart,
              onSelected: (key) => setState(() {
                if (key == null) {
                  _nightByLodging.remove(lodgingKey);
                } else {
                  _nightByLodging[lodgingKey] = key;
                }
              }),
            )
          else if (nightKeys.length > 1 && canManageRooms)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _nightsShownByLodging.add(lodgingKey)),
                  icon: const Icon(PhosphorIconsRegular.calendarDots, size: 18),
                  label: Text(l10n.roomsCustomizeNight),
                ),
              ),
            ),
          Expanded(
            child: _TripRoomsBody(
              // A fresh search for each set of rooms.
              key: ValueKey('$lodgingKey|${nightKey ?? ''}'),
              tripId: trip.id,
              memberLabels: memberLabels,
              rooms: shownRooms,
              readOnly: !canManageRooms || view == _RoomsView.nightUsingShared,
              action: action,
              roomSetOf: (room) =>
                  '${split.lodgingIdOf(room) ?? ''}|${room.nightKey ?? ''}',
            ),
          ),
        ],
      ),
      floatingActionButton: !canManageRooms ||
              view == _RoomsView.nightUsingShared
          ? null
          : FloatingActionButton(
              heroTag: 'trip_rooms_add',
              tooltip: l10n.roomsCreate,
              onPressed: () => _openCreateRoomSheet(
                context,
                tripId: trip.id,
                roomsOfSet: shownRooms,
                lodgingId: lodging.id,
                nightKey: view == _RoomsView.nightApart ? nightKey : null,
              ),
              child: const Icon(PhosphorIconsRegular.plus),
            ),
    );
  }
}

/// "Every night" then each night of the lodging; nights with rooms of
/// their own are marked.
class _RoomNightChips extends StatelessWidget {
  const _RoomNightChips({
    required this.nights,
    required this.selectedKey,
    required this.nightsApart,
    required this.onSelected,
  });

  final List<DateTime> nights;
  final String? selectedKey;
  final Set<String> nightsApart;

  /// Null for every night.
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final format =
        DateFormat('EEE d', Localizations.localeOf(context).toString());
    final group = ActivityFilterGroup.nuits;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(l10n.tripLodgingEveryNight),
            selected: selectedKey == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final night in nights) ...[
            const SizedBox(width: 8),
            Builder(builder: (context) {
              final key = tripNightKey(night);
              return ChoiceChip(
                avatar: nightsApart.contains(key)
                    ? Icon(PhosphorIconsFill.circle,
                        size: 8, color: group.filterColor)
                    : null,
                label: Text(format.format(night)),
                selected: selectedKey == key,
                onSelected: (_) => onSelected(key),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _TripRoomsBody extends StatefulWidget {
  const _TripRoomsBody({
    super.key,
    required this.tripId,
    required this.memberLabels,
    required this.rooms,
    required this.roomSetOf,
    this.readOnly = false,
    this.action,
  });

  final String tripId;
  final Map<String, String> memberLabels;
  final List<TripRoom> rooms;

  /// Rooms of the same set (lodging and night) share their travelers: each
  /// one sleeps in one bed of the set.
  final String Function(TripRoom room) roomSetOf;

  /// Rooms shown as they are, not opened.
  final bool readOnly;

  /// Shown above the rooms (setting a night apart, or back to the shared
  /// rooms).
  final Widget? action;

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
    final action = widget.action;
    final capacity = rooms.fold<int>(0, (sum, r) => sum + r.capacity);
    final assigned =
        rooms.fold<int>(0, (sum, r) => sum + r.assignedMemberIds.length);
    final visibleRooms = rooms.where(_matchesQuery).toList()
      ..sort((a, b) => _compareRoomNames(a.name, b.name));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      children: [
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(alignment: Alignment.centerLeft, child: action),
          ),
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
              onTap: widget.readOnly
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _TripRoomDetailPage(
                            tripId: widget.tripId,
                            roomId: room.id,
                            roomSetOf: widget.roomSetOf,
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

  /// Null leaves the card still.
  final VoidCallback? onTap;

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
                  if (onTap != null)
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
    required this.roomSetOf,
  });

  final String tripId;
  final String roomId;

  /// See [_TripRoomsBody.roomSetOf].
  final String Function(TripRoom room) roomSetOf;

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
      data: (allRooms) {
        final room = allRooms.where((r) => r.id == widget.roomId).firstOrNull;
        if (room == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const SizedBox.shrink(),
          );
        }
        // The other rooms of the same lodging and night.
        final roomSet = widget.roomSetOf(room);
        final rooms = [
          for (final r in allRooms)
            if (widget.roomSetOf(r) == roomSet) r,
        ];
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

/// Adds a room to [lodgingId], shared by its nights, or for [nightKey] only;
/// [roomsOfSet] are the rooms already there.
Future<void> _openCreateRoomSheet(
  BuildContext context, {
  required String tripId,
  required List<TripRoom> roomsOfSet,
  required String? lodgingId,
  required String? nightKey,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _CreateRoomSheet(
        tripId: tripId,
        allRooms: roomsOfSet,
        lodgingId: lodgingId,
        nightKey: nightKey,
      ),
    ),
  );
}

class _CreateRoomSheet extends ConsumerStatefulWidget {
  const _CreateRoomSheet({
    required this.tripId,
    required this.allRooms,
    required this.lodgingId,
    required this.nightKey,
  });

  final String tripId;
  final List<TripRoom> allRooms;
  final String? lodgingId;
  final String? nightKey;

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
            lodgingId: widget.lodgingId,
            nightKey: widget.nightKey,
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
