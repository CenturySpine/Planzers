import 'package:cloud_firestore/cloud_firestore.dart';

enum TripBedType {
  single,
  double;

  String get firestoreValue => switch (this) {
        TripBedType.single => 'single',
        TripBedType.double => 'double',
      };

  int get capacity => switch (this) {
        TripBedType.single => 1,
        TripBedType.double => 2,
      };

  static TripBedType fromFirestoreValue(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    return value == 'double' ? TripBedType.double : TripBedType.single;
  }
}

enum TripBedKind {
  regular,
  extra;

  String get firestoreValue => switch (this) {
        TripBedKind.regular => 'regular',
        TripBedKind.extra => 'extra',
      };

  static TripBedKind fromFirestoreValue(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    return value == 'extra' ? TripBedKind.extra : TripBedKind.regular;
  }
}

class TripRoomBed {
  const TripRoomBed({
    required this.type,
    required this.kind,
    required this.assignedMemberIds,
  });

  final TripBedType type;
  final TripBedKind kind;
  final List<String> assignedMemberIds;

  int get capacity => type.capacity;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.firestoreValue,
      'kind': kind.firestoreValue,
      'assignedMemberIds': assignedMemberIds,
    };
  }

  factory TripRoomBed.fromMap(Map<String, dynamic> map) {
    return TripRoomBed(
      type: TripBedType.fromFirestoreValue(map['type']),
      kind: TripBedKind.fromFirestoreValue(map['kind']),
      assignedMemberIds: ((map['assignedMemberIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString().trim())
          .where((id) => id.isNotEmpty)
          .toList(),
    );
  }
}

class TripRoom {
  TripRoom({
    required this.id,
    required this.name,
    required this.beds,
    required this.createdAt,
    this.createdBy,
  });

  final String id;
  final String name;
  final List<TripRoomBed> beds;
  final DateTime createdAt;
  final String? createdBy;

  int get capacity => beds.fold<int>(0, (total, bed) => total + bed.capacity);

  List<String> get assignedMemberIds {
    final all = <String>{};
    for (final bed in beds) {
      all.addAll(
        bed.assignedMemberIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty),
      );
    }
    return all.toList();
  }

  int get occupancy => assignedMemberIds.length;

  factory TripRoom.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    final createdAt = switch (createdAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? DateTime.now(),
      _ => DateTime.now(),
    };
    final rawBeds = (data['beds'] as List<dynamic>?) ?? const [];
    final beds = rawBeds
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(TripRoomBed.fromMap)
        .toList();
    final roomAssigned = ((data['assignedMemberIds'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString().trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final hydratedBeds = _hydrateBedAssignmentsFromLegacyRoomAssignments(
      beds,
      roomAssigned,
    );

    return TripRoom(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      beds: hydratedBeds,
      createdAt: createdAt,
      createdBy: (data['createdBy'] as String?)?.trim(),
    );
  }
}

List<TripRoomBed> _hydrateBedAssignmentsFromLegacyRoomAssignments(
  List<TripRoomBed> beds,
  List<String> roomAssigned,
) {
  if (beds.isEmpty) return beds;
  final hasPerBedAssignments =
      beds.any((bed) => bed.assignedMemberIds.isNotEmpty);
  if (hasPerBedAssignments || roomAssigned.isEmpty) {
    return beds;
  }

  final queue = [...roomAssigned];
  return beds.map((bed) {
    final forBed = <String>[];
    for (var i = 0; i < bed.capacity && queue.isNotEmpty; i++) {
      forBed.add(queue.removeAt(0));
    }
    return TripRoomBed(
      type: bed.type,
      kind: bed.kind,
      assignedMemberIds: forBed,
    );
  }).toList();
}
