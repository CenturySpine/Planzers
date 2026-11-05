import 'package:cloud_firestore/cloud_firestore.dart';

/// Most receipts one expense can hold.
const int expenseAttachmentsMaxPerExpense = 2;

/// Storage location of a receipt (always JPEG, never replaced), stored with
/// the same sizes and compression as activity photos.
String expenseAttachmentStoragePath(
  String tripId,
  String expenseId,
  String attachmentId,
) =>
    'trips/$tripId/expenses/$expenseId/$attachmentId.jpg';

String expenseAttachmentThumbStoragePath(
  String tripId,
  String expenseId,
  String attachmentId,
) =>
    'trips/$tripId/expenses/$expenseId/${attachmentId}_thumb.jpg';

/// A receipt photo (bill, till receipt…) attached to an expense
/// (`trips/{tripId}/expenses/{expenseId}/attachments/{id}`), seen by every
/// trip member. It belongs to the expense: it stays when its author leaves
/// the trip, and its files are removed server-side with its record or its
/// expense.
class ExpenseAttachment {
  const ExpenseAttachment({
    required this.id,
    required this.url,
    required this.thumbUrl,
    this.createdBy = '',
    this.createdAt,
  });

  final String id;
  final String url;
  final String thumbUrl;
  final String createdBy;

  /// Null while the server timestamp is pending.
  final DateTime? createdAt;

  factory ExpenseAttachment.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    return ExpenseAttachment(
      id: doc.id,
      url: (data['url'] as String?) ?? '',
      thumbUrl: (data['thumbUrl'] as String?) ?? '',
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: createdAtRaw is Timestamp ? createdAtRaw.toDate() : null,
    );
  }
}

/// Oldest first; receipts still being recorded go last.
int compareExpenseAttachments(ExpenseAttachment a, ExpenseAttachment b) {
  final aAt = a.createdAt;
  final bAt = b.createdAt;
  if (aAt == null && bAt == null) return a.id.compareTo(b.id);
  if (aAt == null) return 1;
  if (bAt == null) return -1;
  return aAt.compareTo(bAt);
}
