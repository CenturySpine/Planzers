import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';

class Trip {
  Trip({
    required this.id,
    required this.title,
    required this.destination,
    required this.address,
    required this.linkUrl,
    this.shoppingMeetupLinkUrl = '',
    required this.photosStorageUrl,
    required this.cupidonModeEnabled,
    required this.ownerId,
    required this.memberUserIds,
    required this.createdAt,
    this.startDate,
    this.endDate,
    this.tripStartDayPart,
    this.tripEndDayPart,
    this.bannerImageUrl,
    this.bannerImagePath,
    this.linkPreview = const {},
    this.shoppingMeetupLinkPreview = const {},
    this.adminMemberIds = const [],
    this.generalPermissions = TripGeneralPermissions.defaults,
    this.participantsPermissions = TripParticipantsPermissions.defaults,
    this.expensesPermissions = TripExpensesPermissions.defaults,
    this.activitiesPermissions = TripActivitiesPermissions.defaults,
    this.mealsPermissions = TripMealsPermissions.defaults,
    this.shoppingPermissions = TripShoppingPermissions.defaults,
    this.carpoolPermissions = TripCarpoolPermissions.defaults,
    this.participantCount,
  });

  final String id;
  final String title;
  final String destination;
  final String address;
  final String linkUrl;
  final String shoppingMeetupLinkUrl;
  final String photosStorageUrl;
  final bool cupidonModeEnabled;
  final String ownerId;

  /// Firebase UIDs of all members. Managed server-side for Firestore rules.
  final List<String> memberUserIds;

  /// Total number of participants (real users + placeholders).
  /// Maintained by Firestore triggers. Null on legacy docs before migration.
  final int? participantCount;

  /// Co-admins (trip creator is always admin via [ownerId]).
  final List<String> adminMemberIds;
  final TripGeneralPermissions generalPermissions;
  final TripParticipantsPermissions participantsPermissions;
  final TripExpensesPermissions expensesPermissions;
  final TripActivitiesPermissions activitiesPermissions;
  final TripMealsPermissions mealsPermissions;
  final TripShoppingPermissions shoppingPermissions;
  final TripCarpoolPermissions carpoolPermissions;
  final DateTime createdAt;
  final DateTime? startDate;
  final DateTime? endDate;

  /// First included day-part for the trip calendar span (Firestore: `tripStartDayPart`).
  /// Does not change how [startDate] alone is formatted in the UI.
  final TripDayPart? tripStartDayPart;

  /// Last included day-part for the trip calendar span (Firestore: `tripEndDayPart`).
  final TripDayPart? tripEndDayPart;

  final String? bannerImageUrl;
  final String? bannerImagePath;

  /// Open Graph / meta preview data written by Cloud Functions after a [linkUrl] fetch.
  final Map<String, dynamic> linkPreview;
  final Map<String, dynamic> shoppingMeetupLinkPreview;

  static List<String> adminMemberIdsFromFirestore(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString().trim()).where((id) => id.isNotEmpty).toList();
  }

  /// Trip admins: creator plus [adminMemberIds] entries.
  bool isTripAdmin(String? userId) {
    final u = userId?.trim() ?? '';
    if (u.isEmpty) return false;
    if (u == ownerId.trim()) return true;
    return adminMemberIds.contains(u);
  }

  /// True when [memberId] has admin privileges (creator or listed co-admin).
  bool memberHasAdminRole(String memberId) {
    final id = memberId.trim();
    if (id.isEmpty) return false;
    if (id == ownerId.trim()) return true;
    return adminMemberIds.contains(id);
  }

  static DateTime? _parseOptionalDate(dynamic raw) {
    return switch (raw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s),
      _ => null,
    };
  }

  factory Trip.fromMap(String id, Map<String, dynamic> data) {
    final createdAtRaw = data['createdAt'];
    final createdAt = switch (createdAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? DateTime.now(),
      _ => DateTime.now(),
    };

    return Trip(
      id: id,
      title: (data['title'] as String?) ?? '',
      destination: (data['destination'] as String?) ?? '',
      address: (data['address'] as String?) ?? '',
      linkUrl: (data['linkUrl'] as String?) ?? '',
      shoppingMeetupLinkUrl:
          (data['shoppingMeetupLinkUrl'] as String?)?.trim().isNotEmpty == true
              ? (data['shoppingMeetupLinkUrl'] as String).trim()
              : ((data['carpoolShoppingMeetupLinkUrl'] as String?) ?? ''),
      photosStorageUrl: (data['photosStorageUrl'] as String?) ?? '',
      cupidonModeEnabled: data['cupidonModeEnabled'] != false,
      ownerId: (data['ownerId'] as String?) ?? '',
      memberUserIds: ((data['memberUserIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      participantCount: (data['participantCount'] as num?)?.toInt(),
      createdAt: createdAt,
      startDate: _parseOptionalDate(data['startDate']),
      endDate: _parseOptionalDate(data['endDate']),
      tripStartDayPart:
          tripDayPartFromFirestore(data['tripStartDayPart'] as String?),
      tripEndDayPart: tripDayPartFromFirestore(data['tripEndDayPart'] as String?),
      bannerImageUrl: (data['bannerImageUrl'] as String?)?.trim(),
      bannerImagePath: (data['bannerImagePath'] as String?)?.trim(),
      linkPreview:
          (data['linkPreview'] as Map<String, dynamic>?) ?? const {},
      shoppingMeetupLinkPreview:
          (data['shoppingMeetupLinkPreview'] as Map<String, dynamic>?) ??
              ((data['carpoolShoppingMeetupLinkPreview'] as Map<String, dynamic>?) ??
                  const {}),
      adminMemberIds: adminMemberIdsFromFirestore(data['adminMemberIds']),
      generalPermissions: TripGeneralPermissions.fromFirestore(
        (data['permissions'] as Map<String, dynamic>?)?['tripGeneral'],
      ),
      participantsPermissions: TripParticipantsPermissions.fromFirestore(
        (data['permissions'] as Map<String, dynamic>?)?['participants'],
      ),
      expensesPermissions: TripExpensesPermissions.fromFirestore(
        (data['permissions'] as Map<String, dynamic>?)?['expenses'],
      ),
      activitiesPermissions: TripActivitiesPermissions.fromFirestore(
        (data['permissions'] as Map<String, dynamic>?)?['activities'],
      ),
      mealsPermissions: TripMealsPermissions.fromFirestore(
        (data['permissions'] as Map<String, dynamic>?)?['meals'],
      ),
      shoppingPermissions: TripShoppingPermissions.fromFirestore(
        (data['permissions'] as Map<String, dynamic>?)?['shopping'],
      ),
      carpoolPermissions: TripCarpoolPermissions.fromFirestore(
        (data['permissions'] as Map<String, dynamic>?)?['carpool'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'destination': destination,
      'address': address,
      'linkUrl': linkUrl,
      if (shoppingMeetupLinkUrl.trim().isNotEmpty)
        'shoppingMeetupLinkUrl': shoppingMeetupLinkUrl.trim(),
      if (shoppingMeetupLinkPreview.isNotEmpty)
        'shoppingMeetupLinkPreview': shoppingMeetupLinkPreview,
      'photosStorageUrl': photosStorageUrl,
      'cupidonModeEnabled': cupidonModeEnabled,
      'ownerId': ownerId,
      'memberUserIds': memberUserIds,
      'createdAt': createdAt.toIso8601String(),
      if (startDate != null) 'startDate': startDate!.toIso8601String(),
      if (endDate != null) 'endDate': endDate!.toIso8601String(),
      if (tripStartDayPart != null)
        'tripStartDayPart': tripDayPartToFirestore(tripStartDayPart!),
      if (tripEndDayPart != null)
        'tripEndDayPart': tripDayPartToFirestore(tripEndDayPart!),
      if ((bannerImageUrl ?? '').trim().isNotEmpty)
        'bannerImageUrl': bannerImageUrl!.trim(),
      if ((bannerImagePath ?? '').trim().isNotEmpty)
        'bannerImagePath': bannerImagePath!.trim(),
      if (adminMemberIds.isNotEmpty) 'adminMemberIds': adminMemberIds,
      'permissions': <String, dynamic>{
        'tripGeneral': generalPermissions.toFirestore(),
        'participants': participantsPermissions.toFirestore(),
        'expenses': expensesPermissions.toFirestore(),
        'activities': activitiesPermissions.toFirestore(),
        'meals': mealsPermissions.toFirestore(),
        'shopping': shoppingPermissions.toFirestore(),
        'carpool': carpoolPermissions.toFirestore(),
      },
    };
  }
}
