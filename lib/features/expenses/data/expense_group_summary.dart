import 'package:cloud_firestore/cloud_firestore.dart';

/// Header totals and metadata for an expense post (`summary/current`).
class ExpenseGroupSummary {
  ExpenseGroupSummary({
    this.settlementComputedAt,
    required this.postTotalsByCurrency,
    required this.paidByTotalsByCurrency,
  });

  final DateTime? settlementComputedAt;
  final Map<String, double> postTotalsByCurrency;
  final Map<String, Map<String, double>> paidByTotalsByCurrency;

  factory ExpenseGroupSummary.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final computedAtRaw = data['settlementComputedAt'];
    final settlementComputedAt = switch (computedAtRaw) {
      Timestamp ts => ts.toDate(),
      _ => null,
    };

    final postTotals = _currencyTotalsFromMap(data['postTotalsByCurrency']);
    final paidByTotals = <String, Map<String, double>>{};
    final paidRaw = data['paidByTotalsByCurrency'];
    if (paidRaw is Map) {
      for (final entry in paidRaw.entries) {
        final participantId = entry.key.toString().trim();
        if (participantId.isEmpty) continue;
        paidByTotals[participantId] = _currencyTotalsFromMap(entry.value);
      }
    }

    return ExpenseGroupSummary(
      settlementComputedAt: settlementComputedAt,
      postTotalsByCurrency: postTotals,
      paidByTotalsByCurrency: paidByTotals,
    );
  }
}

Map<String, double> _currencyTotalsFromMap(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, double>{};
  for (final entry in raw.entries) {
    final currency = entry.key.toString().trim().toUpperCase();
    if (currency.isEmpty) continue;
    final value = entry.value;
    final amount = switch (value) {
      num n => n.toDouble(),
      _ => null,
    };
    if (amount != null) out[currency] = amount;
  }
  return out;
}
