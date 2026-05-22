import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-currency net balances for an expense post (`balances/{currency}`).
class GroupBalance {
  GroupBalance({
    required this.currency,
    required this.nets,
  });

  final String currency;
  final Map<String, double> nets;

  factory GroupBalance.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final netsRaw = data['nets'];
    final nets = <String, double>{};
    if (netsRaw is Map) {
      for (final entry in netsRaw.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        final value = entry.value;
        final amount = switch (value) {
          num n => n.toDouble(),
          _ => null,
        };
        if (amount != null) nets[key] = amount;
      }
    }
    return GroupBalance(
      currency: ((data['currency'] as String?) ?? doc.id).trim().toUpperCase(),
      nets: nets,
    );
  }
}
