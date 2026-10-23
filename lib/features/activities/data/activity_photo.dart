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

/// A traveler's own photo attached to a planned activity
/// (`trips/{tripId}/travelerModules/{uid}/activityPhotos/{photoId}`).
/// Only its author sees it; its files are removed server-side whenever the
/// record is deleted (by its author, a trip admin or a cleanup).
class ActivityPhoto {
  const ActivityPhoto({
    required this.id,
    required this.activityId,
    required this.url,
    required this.thumbUrl,
    this.caption = '',
    this.favorite = false,
    this.createdAt,
  });

  final String id;
  final String activityId;
  final String url;
  final String thumbUrl;

  /// Empty when the author wrote none.
  final String caption;

  /// At most one per activity: the photo shown on the trip map.
  final bool favorite;

  /// Null while the server timestamp is pending.
  final DateTime? createdAt;

  factory ActivityPhoto.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    return ActivityPhoto(
      id: doc.id,
      activityId: (data['activityId'] as String?) ?? '',
      url: (data['url'] as String?) ?? '',
      thumbUrl: (data['thumbUrl'] as String?) ?? '',
      caption: (data['caption'] as String?) ?? '',
      favorite: data['favorite'] == true,
      createdAt: createdAtRaw is Timestamp ? createdAtRaw.toDate() : null,
    );
  }
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

/// The favorite photo of each activity, by activity id. Should two be marked
/// (e.g. set from two devices at once), the first in display order wins.
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
