import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planerz/features/expenses/data/expense_icon_catalog.dart';

/// Expense post for a trip: visibility and title are scoped to the whole post.
///
/// Firestore: `trips/{tripId}/expenseGroups/{groupId}`.
class TripExpenseGroup {
  TripExpenseGroup({
    required this.id,
    required this.title,
    required this.visibleToMemberIds,
    required this.createdAt,
    this.icon = kDefaultExpensePostIconKey,
    this.createdBy,
    this.isDefault = false,
  });

  final String id;
  final String title;

  /// Material Symbol key (see [kExpenseIconCatalog]).
  final String icon;

  /// Members who see this post and its expenses. Must be non-empty in normal data.
  final List<String> visibleToMemberIds;
  final DateTime createdAt;
  final String? createdBy;

  /// Trip-wide default post (e.g. "Commun"), expanded by default in the UI.
  final bool isDefault;

  factory TripExpenseGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    final createdAt = switch (createdAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? DateTime.now(),
      _ => DateTime.now(),
    };

    final iconRaw = (data['icon'] as String?)?.trim() ?? '';
    final isDefault = data['isDefault'] == true;
    final icon = iconRaw.isNotEmpty
        ? iconRaw
        : (isDefault ? kDefaultExpensePostIconKey : kDefaultExpensePostIconKey);

    return TripExpenseGroup(
      id: doc.id,
      title: (data['title'] as String?)?.trim() ?? '',
      icon: icon,
      visibleToMemberIds:
          ((data['visibleToMemberIds'] as List<dynamic>?) ?? const [])
              .map((e) => e.toString())
              .where((id) => id.trim().isNotEmpty)
              .toList(),
      createdAt: createdAt,
      createdBy: (data['createdBy'] as String?)?.trim(),
      isDefault: isDefault,
    );
  }

  /// Whether this post is visible to [memberDocId] (TripMember document ID).
  /// Pass null or empty to default to visible (e.g. for unauthenticated preview).
  bool isVisibleTo(String? memberDocId) {
    if (memberDocId == null || memberDocId.trim().isEmpty) return true;
    if (visibleToMemberIds.isEmpty) return false;
    return visibleToMemberIds.contains(memberDocId.trim());
  }
}
