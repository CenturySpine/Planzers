import 'package:cloud_firestore/cloud_firestore.dart';

class AdminAnnouncement {
  AdminAnnouncement({
    required this.id,
    required this.text,
    required this.authorId,
    required this.createdAt,
    required this.userDismissAllowed,
    this.updatedAt,
  });

  final String id;
  final String text;
  final String authorId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// When `false`, end users do not see the per-announcement dismiss control.
  final bool userDismissAllowed;

  bool get wasEdited => updatedAt != null;

  /// Parses [userDismissAllowed] from Firestore; defaults to `true` when absent or invalid.
  static bool userDismissAllowedFromFirestoreData(Map<String, dynamic> data) {
    final raw = data['userDismissAllowed'];
    return raw is bool ? raw : true;
  }

  factory AdminAnnouncement.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdRaw = data['createdAt'];
    final createdAt = switch (createdRaw) {
      Timestamp timestamp => timestamp.toDate(),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final updatedRaw = data['updatedAt'];
    final updatedAt = switch (updatedRaw) {
      Timestamp timestamp => timestamp.toDate(),
      _ => null,
    };
    return AdminAnnouncement(
      id: doc.id,
      text: (data['text'] as String?)?.trim() ?? '',
      authorId: (data['authorId'] as String?)?.trim() ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      userDismissAllowed: userDismissAllowedFromFirestoreData(data),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'text': text.trim(),
      'authorId': authorId.trim(),
      'createdAt': Timestamp.fromDate(createdAt),
      'userDismissAllowed': userDismissAllowed,
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }
}
