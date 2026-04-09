import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared expense line for a trip (Firestore: `trips/{tripId}/expenses/{expenseId}`).
class TripExpense {
  TripExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.currency,
    required this.paidBy,
    required this.participantIds,
    required this.category,
    required this.createdAt,
    this.createdBy,
  });

  final String id;
  final String title;
  final double amount;
  /// ISO-like code, e.g. `EUR`, `USD`.
  final String currency;
  final String paidBy;
  final List<String> participantIds;
  final String category;
  final DateTime createdAt;
  final String? createdBy;

  factory TripExpense.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    final createdAt = switch (createdAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? DateTime.now(),
      _ => DateTime.now(),
    };

    final amountRaw = data['amount'];
    final amount = switch (amountRaw) {
      num n => n.toDouble(),
      _ => 0.0,
    };

    return TripExpense(
      id: doc.id,
      title: (data['title'] as String?)?.trim() ?? '',
      amount: amount,
      currency: ((data['currency'] as String?) ?? 'EUR').trim().toUpperCase(),
      paidBy: (data['paidBy'] as String?)?.trim() ?? '',
      participantIds: ((data['participantIds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .where((id) => id.trim().isNotEmpty)
          .toList(),
      category: ((data['category'] as String?) ?? 'other').trim(),
      createdAt: createdAt,
      createdBy: (data['createdBy'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toCreateMap({
    required String paidBy,
    required String createdBy,
  }) {
    return {
      'title': title.trim(),
      'amount': amount,
      'currency': currency.trim().toUpperCase(),
      'paidBy': paidBy.trim(),
      'participantIds': participantIds,
      'category': category.trim().isEmpty ? 'other' : category.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy.trim(),
    };
  }
}
