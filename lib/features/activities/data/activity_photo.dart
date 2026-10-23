import 'package:cloud_firestore/cloud_firestore.dart';

/// Most photos a traveler can attach to the activities of one day.
const int activityPhotosMaxPerDay = 10;

/// Longest side of the stored photo and of its thumbnail, in pixels.
const int activityPhotoMaxSide = 2048;
const int activityPhotoThumbMaxSide = 400;

/// Must match `storage.rules`.
const int activityPhotoMaxFileSizeBytes = 3 * 1024 * 1024;

/// In characters as people count them (an emoji is one), enforced by the
/// caption field; `firestore.rules` leaves room for emoji.
const int activityPhotoMaxCaptionLength = 500;

/// Storage location of a photo (always JPEG, never replaced).
String activityPhotoStoragePath(String uid, String tripId, String photoId) =>
    'users/$uid/activityPhotos/$tripId/$photoId.jpg';

String activityPhotoThumbStoragePath(
  String uid,
  String tripId,
  String photoId,
) =>
    'users/$uid/activityPhotos/$tripId/${photoId}_thumb.jpg';

/// A traveler's photo attached to a planned activity
/// (`trips/{tripId}/travelerModules/{ownerId}/activityPhotos/{id}`).
/// Shared photos are seen by every trip member, private ones by their author
/// only. Its files are removed server-side whenever the record is deleted
/// (by its author, a trip admin or a cleanup).
class ActivityPhoto {
  const ActivityPhoto({
    required this.id,
    this.ownerId = '',
    required this.activityId,
    required this.url,
    required this.thumbUrl,
    this.caption = '',
    this.shared = false,
    this.favorite = false,
    this.createdAt,
  });

  final String id;

  /// The traveler who added it.
  final String ownerId;
  final String activityId;
  final String url;
  final String thumbUrl;

  /// Empty when the author wrote none.
  final String caption;

  /// Seen by the other trip members; photos added before sharing existed
  /// have no flag and stay private.
  final bool shared;

  /// Former favorite mark, set on the author's own photo; favorites now live
  /// in each traveler's [ActivityFavoriteRef]s.
  final bool favorite;

  /// Null while the server timestamp is pending.
  final DateTime? createdAt;

  factory ActivityPhoto.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    return ActivityPhoto(
      id: doc.id,
      ownerId: doc.reference.parent.parent?.id ?? '',
      activityId: (data['activityId'] as String?) ?? '',
      url: (data['url'] as String?) ?? '',
      thumbUrl: (data['thumbUrl'] as String?) ?? '',
      caption: (data['caption'] as String?) ?? '',
      shared: data['shared'] == true,
      favorite: data['favorite'] == true,
      createdAt: createdAtRaw is Timestamp ? createdAtRaw.toDate() : null,
    );
  }

  /// Identifies the photo across travelers.
  String get key => '$ownerId/$id';
}

/// Oldest first; photos still being recorded go last.
int compareActivityPhotos(ActivityPhoto a, ActivityPhoto b) {
  final aAt = a.createdAt;
  final bAt = b.createdAt;
  if (aAt == null && bAt == null) return a.id.compareTo(b.id);
  if (aAt == null) return 1;
  if (bAt == null) return -1;
  return aAt.compareTo(bAt);
}

/// The photos marked with the former favorite field, by activity id. Should
/// two be marked (e.g. set from two devices at once), the first in display
/// order wins.
Map<String, ActivityPhoto> activityFavoritePhotos(
  Iterable<ActivityPhoto> photos,
) {
  final sorted = photos.where((photo) => photo.favorite).toList()
    ..sort(compareActivityPhotos);
  final favorites = <String, ActivityPhoto>{};
  for (final photo in sorted) {
    favorites.putIfAbsent(photo.activityId, () => photo);
  }
  return favorites;
}

/// A traveler's favorite photo of an activity, possibly another member's
/// (`trips/{tripId}/travelerModules/{uid}/activityFavorites/{activityId}`).
class ActivityFavoriteRef {
  const ActivityFavoriteRef({
    required this.activityId,
    required this.ownerId,
    required this.photoId,
  });

  final String activityId;
  final String ownerId;
  final String photoId;

  String get photoKey => '$ownerId/$photoId';

  factory ActivityFavoriteRef.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ActivityFavoriteRef(
      activityId: doc.id,
      ownerId: (data['ownerId'] as String?) ?? '',
      photoId: (data['photoId'] as String?) ?? '',
    );
  }
}

/// The favorite photo of each activity, by activity id, among the photos the
/// traveler can see. A chosen favorite whose photo was deleted or made
/// private shows none; activities never chosen since favorites moved fall
/// back to the former mark on the traveler's own photos.
Map<String, ActivityPhoto> resolveActivityFavorites({
  required Map<String, ActivityFavoriteRef> favorites,
  required Iterable<ActivityPhoto> visiblePhotos,
  required Iterable<ActivityPhoto> myPhotos,
}) {
  final byKey = {for (final photo in visiblePhotos) photo.key: photo};
  final result = <String, ActivityPhoto>{
    for (final entry in activityFavoritePhotos(myPhotos).entries)
      if (!favorites.containsKey(entry.key)) entry.key: entry.value,
  };
  for (final favorite in favorites.values) {
    final photo = byKey[favorite.photoKey];
    if (photo != null && photo.activityId == favorite.activityId) {
      result[favorite.activityId] = photo;
    }
  }
  return result;
}

/// Why a member reports another member's photo (values must match
/// `firestore.rules`).
enum PhotoReportReason {
  inappropriate,
  notConsenting,
  other;

  static PhotoReportReason fromFirestore(Object? raw) =>
      values.firstWhere((reason) => reason.name == raw, orElse: () => other);
}

/// A member's report of a shared photo (`trips/{tripId}/photoReports/{id}`),
/// listed for the trip admins and the application owner. The photo stays
/// hidden for its reporter, even once the report is dismissed.
class PhotoReport {
  const PhotoReport({
    required this.id,
    required this.tripId,
    required this.photoOwnerId,
    required this.photoId,
    required this.activityId,
    required this.reporterId,
    required this.reason,
    this.dismissed = false,
    this.createdAt,
  });

  final String id;
  final String tripId;
  final String photoOwnerId;
  final String photoId;
  final String activityId;
  final String reporterId;
  final PhotoReportReason reason;
  final bool dismissed;
  final DateTime? createdAt;

  String get photoKey => '$photoOwnerId/$photoId';

  /// One report per reporter and photo.
  static String idFor({
    required String reporterId,
    required String photoOwnerId,
    required String photoId,
  }) =>
      '${reporterId}_${photoOwnerId}_$photoId';

  factory PhotoReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    return PhotoReport(
      id: doc.id,
      tripId: doc.reference.parent.parent?.id ?? '',
      photoOwnerId: (data['photoOwnerId'] as String?) ?? '',
      photoId: (data['photoId'] as String?) ?? '',
      activityId: (data['activityId'] as String?) ?? '',
      reporterId: (data['reporterId'] as String?) ?? '',
      reason: PhotoReportReason.fromFirestore(data['reason']),
      dismissed: data['dismissed'] == true,
      createdAt: createdAtRaw is Timestamp ? createdAtRaw.toDate() : null,
    );
  }
}
