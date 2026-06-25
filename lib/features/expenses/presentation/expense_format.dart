import 'package:intl/intl.dart';

const String kDefaultExpenseCurrency = 'EUR';

String formatExpenseMoney(String currency, double amount, {String? locale}) {
  final c = currency.trim().toUpperCase();
  if (c == 'EUR') {
    return NumberFormat.currency(locale: locale ?? 'fr_FR', symbol: '€')
        .format(amount);
  }
  if (c == 'USD') {
    return NumberFormat.currency(locale: locale ?? 'en_US', symbol: r'$')
        .format(amount);
  }
  return '$amount $c';
}

/// Primary currency for hero/net pill: EUR when present, else first sorted key.
String resolvePrimaryExpenseCurrency(Map<String, double> totalsByCurrency) {
  if (totalsByCurrency.isEmpty) return kDefaultExpenseCurrency;
  if (totalsByCurrency.containsKey('EUR')) return 'EUR';
  final keys = totalsByCurrency.keys.toList()..sort();
  return keys.first;
}

String formatExpenseDateShort(DateTime date, String locale) {
  return DateFormat.yMMMd(locale).format(date);
}

String formatExpenseDateForm(DateTime date) {
  return DateFormat('dd/MM/yyyy').format(date);
}

double expenseShareForUnit({
  required double amount,
  required String unitId,
  required List<String> participantIds,
  required Map<String, double> groupParts,
  required String splitModeKey,
  required Map<String, double> participantShares,
}) {
  if (unitId.trim().isEmpty || !participantIds.contains(unitId)) {
    return 0.0;
  }
  if (splitModeKey == 'custom') {
    return participantShares[unitId] ?? 0.0;
  }
  final totalParts = participantIds.fold<double>(
    0,
    (sum, id) => sum + (groupParts[id] ?? 1.0),
  );
  final myParts = groupParts[unitId] ?? 1.0;
  return totalParts > 0 ? amount * myParts / totalParts : 0.0;
}

/// Viewer delta on an expense: positive = others owe viewer.
double? viewerExpenseDelta({
  required String? viewerBillingUnitId,
  required String paidBy,
  required List<String> participantIds,
  required double amount,
  required double share,
}) {
  final me = viewerBillingUnitId?.trim();
  if (me == null || me.isEmpty) return null;
  if (paidBy == me) {
    return amount - share;
  }
  if (participantIds.contains(me)) {
    return -share;
  }
  return null;
}
