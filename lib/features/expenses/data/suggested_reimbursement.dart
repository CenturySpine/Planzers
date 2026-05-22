import 'package:cloud_firestore/cloud_firestore.dart';

/// Server-computed reimbursement suggestion for an expense post.
class SuggestedReimbursement {
  SuggestedReimbursement({
    required this.id,
    required this.fromParticipantId,
    required this.toParticipantId,
    required this.amount,
    required this.currency,
  });

  final String id;
  final String fromParticipantId;
  final String toParticipantId;
  final double amount;
  final String currency;

  factory SuggestedReimbursement.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final amountRaw = data['amount'];
    final amount = switch (amountRaw) {
      num n => n.toDouble(),
      _ => 0.0,
    };
    return SuggestedReimbursement(
      id: doc.id,
      fromParticipantId: (data['fromParticipantId'] as String?)?.trim() ?? '',
      toParticipantId: (data['toParticipantId'] as String?)?.trim() ?? '',
      amount: amount,
      currency: ((data['currency'] as String?) ?? 'EUR').trim().toUpperCase(),
    );
  }
}
