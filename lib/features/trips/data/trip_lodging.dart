import 'package:cloud_firestore/cloud_firestore.dart';

/// Where the group sleeps for one or several nights of a trip
/// (`trips/{tripId}/lodgings/{lodgingId}`).
class TripLodging {
  const TripLodging({
    required this.id,
    this.name = '',
    this.address = '',
    this.location,
    this.linkUrl = '',
    this.linkPreview = const {},
    this.nightKeys = const [],
    this.allNights = false,
    this.isLegacy = false,
  });

  final String id;
  final String name;
  final String address;
  final GeoPoint? location;
  final String linkUrl;

  /// Same shape as trip `linkPreview` (filled by Cloud Function).
  final Map<String, dynamic> linkPreview;

  /// Evenings of the nights spent there (`yyyy-MM-dd`): `2026-07-12` is the
  /// night from 12 to 13 July. Ignored when [allNights].
  final List<String> nightKeys;

  /// Every night of the trip, following its dates when they change.
  final bool allNights;

  /// Stands for the trip's former single link and address, not stored as a
  /// lodging yet.
  final bool isLegacy;

  /// Title shown for the lodging: its name, else the link preview title,
  /// else its address, else its link.
  String get displayTitle {
    final cleanName = name.trim();
    if (cleanName.isNotEmpty) return cleanName;
    final previewTitle = ((linkPreview['title'] as String?) ?? '').trim();
    if (previewTitle.isNotEmpty) return previewTitle;
    final cleanAddress = address.trim();
    if (cleanAddress.isNotEmpty) return cleanAddress;
    return linkUrl.trim();
  }

  bool get hasPlace =>
      name.trim().isNotEmpty ||
      address.trim().isNotEmpty ||
      linkUrl.trim().isNotEmpty ||
      location != null;

  /// Same name, address, point and link.
  bool samePlaceAs(TripLodging other) =>
      name.trim() == other.name.trim() &&
      address.trim() == other.address.trim() &&
      linkUrl.trim() == other.linkUrl.trim() &&
      location == other.location;

  TripLodging copyWith({
    String? id,
    String? name,
    String? address,
    GeoPoint? location,
    String? linkUrl,
    Map<String, dynamic>? linkPreview,
    List<String>? nightKeys,
    bool? allNights,
    bool? isLegacy,
  }) {
    return TripLodging(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      location: location ?? this.location,
      linkUrl: linkUrl ?? this.linkUrl,
      linkPreview: linkPreview ?? this.linkPreview,
      nightKeys: nightKeys ?? this.nightKeys,
      allNights: allNights ?? this.allNights,
      isLegacy: isLegacy ?? this.isLegacy,
    );
  }

  /// Same place, nights and all-nights choice.
  bool sameContentAs(TripLodging other) {
    if (!samePlaceAs(other) || allNights != other.allNights) return false;
    final mine = [...nightKeys]..sort();
    final theirs = [...other.nightKeys]..sort();
    if (mine.length != theirs.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  factory TripLodging.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final location = data['location'];
    final preview = data['linkPreview'];
    final nights = data['nights'];
    return TripLodging(
      id: doc.id,
      name: ((data['name'] as String?) ?? '').trim(),
      address: ((data['address'] as String?) ?? '').trim(),
      location: location is GeoPoint ? location : null,
      linkUrl: ((data['linkUrl'] as String?) ?? '').trim(),
      linkPreview:
          preview is Map ? Map<String, dynamic>.from(preview) : const {},
      nightKeys: nights is List
          ? nights.whereType<String>().map((n) => n.trim()).toList()
          : const [],
      allNights: data['allNights'] == true,
    );
  }

  /// Fields written by the app, to merge into the document; `linkPreview` is
  /// left to the Cloud Function.
  Map<String, dynamic> toFirestore() {
    final sortedNights = allNights ? <String>[] : ([...nightKeys]..sort());
    return {
      'name': name.trim(),
      'address': address.trim(),
      'location': location ?? FieldValue.delete(),
      'linkUrl': linkUrl.trim(),
      'nights': sortedNights,
      'allNights': allNights,
    };
  }
}
