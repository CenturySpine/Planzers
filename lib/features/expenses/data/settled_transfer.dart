import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planzers/features/expenses/domain/expense_settlement.dart';

class SettledTransfer {
  const SettledTransfer({
    required this.id,
    required this.groupId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.currency,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String groupId;
  final String fromUserId;
  final String toUserId;
  final double amount;
  final String currency;
  final DateTime createdAt;
  final String createdBy;

  SuggestedTransfer toSuggestedTransfer() {
    return SuggestedTransfer(
      fromUserId: fromUserId,
      toUserId: toUserId,
      amount: amount,
      currency: currency,
    );
  }

  factory SettledTransfer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
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
    return SettledTransfer(
      id: doc.id,
      groupId: (data['groupId'] as String?)?.trim() ?? '',
      fromUserId: (data['fromUserId'] as String?)?.trim() ?? '',
      toUserId: (data['toUserId'] as String?)?.trim() ?? '',
      amount: amount,
      currency: ((data['currency'] as String?) ?? 'EUR').trim().toUpperCase(),
      createdAt: createdAt,
      createdBy: (data['createdBy'] as String?)?.trim() ?? '',
    );
  }
}
