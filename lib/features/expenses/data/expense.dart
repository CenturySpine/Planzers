import 'package:cloud_firestore/cloud_firestore.dart';

/// How the expense total is allocated across [participantIds].
enum ExpenseSplitMode {
  /// Same amount for each participant (`total / count`).
  equal,

  /// Each participant has an explicit share in [participantShares].
  customAmounts,
}

/// Shared expense line for a trip (Firestore: `trips/{tripId}/expenses/{expenseId}`).
class TripExpense {
  TripExpense({
    required this.id,
    required this.groupId,
    required this.title,
    required this.amount,
    required this.currency,
    required this.paidBy,
    required this.participantIds,
    required this.category,
    required this.createdAt,
    required this.expenseDate,
    this.createdBy,
    this.splitMode = ExpenseSplitMode.equal,
    Map<String, double>? participantShares,
  }) : participantShares = participantShares ?? const {};

  final String id;
  final String groupId;
  final String title;
  final double amount;

  /// ISO-like code, e.g. `EUR`, `USD`.
  final String currency;
  final String paidBy;
  final List<String> participantIds;
  final String category;
  final DateTime createdAt;
  final DateTime expenseDate;
  final String? createdBy;

  /// When [splitMode] is [ExpenseSplitMode.customAmounts], share per participant
  /// (same keys as [participantIds]); ignored for equal split.
  final ExpenseSplitMode splitMode;
  final Map<String, double> participantShares;

  factory TripExpense.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    final createdAt = switch (createdAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? DateTime.now(),
      _ => DateTime.now(),
    };
    final expenseDateRaw = data['expenseDate'];
    final expenseDate = switch (expenseDateRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? createdAt,
      _ => createdAt,
    };

    final amountRaw = data['amount'];
    final amount = switch (amountRaw) {
      num n => n.toDouble(),
      _ => 0.0,
    };

    return TripExpense(
      id: doc.id,
      groupId: (data['groupId'] as String?)?.trim() ?? '',
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
      expenseDate: DateTime(
        expenseDate.year,
        expenseDate.month,
        expenseDate.day,
      ),
      createdBy: (data['createdBy'] as String?)?.trim(),
      splitMode: _splitModeFromFirestore(data['splitMode']),
      participantShares: _participantSharesFromFirestore(data['participantShares']),
    );
  }

  Map<String, dynamic> toCreateMap({
    required String paidBy,
    required String createdBy,
    required String groupId,
  }) {
    final map = <String, dynamic>{
      'groupId': groupId.trim(),
      'title': title.trim(),
      'amount': amount,
      'currency': currency.trim().toUpperCase(),
      'paidBy': paidBy.trim(),
      'participantIds': participantIds,
      'category': category.trim().isEmpty ? 'other' : category.trim(),
      'expenseDate': Timestamp.fromDate(
        DateTime(expenseDate.year, expenseDate.month, expenseDate.day),
      ),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy.trim(),
      'splitMode': splitMode == ExpenseSplitMode.customAmounts
          ? 'custom'
          : 'equal',
    };
    if (splitMode == ExpenseSplitMode.customAmounts) {
      map['participantShares'] = {
        for (final e in participantShares.entries)
          if (e.key.trim().isNotEmpty) e.key.trim(): e.value,
      };
    }
    return map;
  }
}

ExpenseSplitMode _splitModeFromFirestore(Object? raw) {
  final s = raw?.toString().trim().toLowerCase() ?? '';
  if (s == 'custom' || s == 'amounts' || s == 'montants') {
    return ExpenseSplitMode.customAmounts;
  }
  return ExpenseSplitMode.equal;
}

Map<String, double> _participantSharesFromFirestore(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, double>{};
  for (final e in raw.entries) {
    final k = e.key.toString().trim();
    if (k.isEmpty) continue;
    final v = e.value;
    final n = switch (v) {
      num x => x.toDouble(),
      _ => null,
    };
    if (n != null) out[k] = n;
  }
  return out;
}
