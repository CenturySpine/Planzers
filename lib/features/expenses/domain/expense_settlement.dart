import 'package:planzers/features/expenses/data/expense.dart';

/// Net balance per person in one currency (positive = others owe this person).
typedef BalancesByCurrency = Map<String, Map<String, double>>;

/// One suggested bank transfer / cash payment to settle debts.
class SuggestedTransfer {
  const SuggestedTransfer({
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.currency,
  });

  final String fromUserId;
  final String toUserId;
  final double amount;
  final String currency;
}

/// Supported expense currencies for MVP (display + separate balance buckets).
const Set<String> kSupportedExpenseCurrencies = {'EUR', 'USD'};

/// Epsilon for floating-point comparisons (cent-level).
const double _kBalanceEpsilon = 0.009;

/// Computes per-user net balance by currency from shared expenses.
///
/// For each expense, the amount is split equally across [participantIds];
/// each participant is debited their share; [paidBy] is credited the full
/// amount paid (standard Splitwise / TriCount-style model).
BalancesByCurrency computeBalances(Iterable<TripExpense> expenses) {
  final result = <String, Map<String, double>>{};

  for (final expense in expenses) {
    final currency = expense.currency.trim().toUpperCase();
    if (currency.isEmpty) continue;

    final participants = expense.participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (participants.isEmpty) continue;

    final paidBy = expense.paidBy.trim();
    if (paidBy.isEmpty) continue;

    final amount = expense.amount;
    if (amount <= 0) continue;

    final perPerson = amount / participants.length;
    final bucket = result.putIfAbsent(currency, () => <String, double>{});

    for (final uid in participants) {
      bucket[uid] = (bucket[uid] ?? 0) - perPerson;
    }
    bucket[paidBy] = (bucket[paidBy] ?? 0) + amount;
  }

  return result;
}

/// Greedy simplification: minimal number of transfers per currency to zero balances.
List<SuggestedTransfer> suggestTransfers(BalancesByCurrency balancesByCurrency) {
  final transfers = <SuggestedTransfer>[];

  for (final entry in balancesByCurrency.entries) {
    final currency = entry.key;
    final raw = entry.value;

    final working = <String, double>{};
    for (final e in raw.entries) {
      final v = _roundMoney(e.value);
      if (v.abs() > _kBalanceEpsilon) {
        working[e.key] = v;
      }
    }
    if (working.isEmpty) continue;

    _simplifyCurrency(working, currency, transfers);
  }

  return transfers;
}

void _simplifyCurrency(
  Map<String, double> balances,
  String currency,
  List<SuggestedTransfer> out,
) {
  while (true) {
    String? maxCreditor;
    double maxCredit = 0;
    String? maxDebtor;
    double maxDebt = 0;

    for (final e in balances.entries) {
      if (e.value > maxCredit) {
        maxCredit = e.value;
        maxCreditor = e.key;
      }
      if (e.value < maxDebt) {
        maxDebt = e.value;
        maxDebtor = e.key;
      }
    }

    if (maxCreditor == null ||
        maxDebtor == null ||
        maxCredit <= _kBalanceEpsilon ||
        maxDebt >= -_kBalanceEpsilon) {
      break;
    }

    final pay = _roundMoney(
      maxCredit < -maxDebt ? maxCredit : -maxDebt,
    );
    if (pay <= _kBalanceEpsilon) break;

    out.add(SuggestedTransfer(
      fromUserId: maxDebtor,
      toUserId: maxCreditor,
      amount: pay,
      currency: currency,
    ));

    balances[maxCreditor] = _roundMoney(maxCredit - pay);
    balances[maxDebtor] = _roundMoney(maxDebt + pay);

    if (balances[maxCreditor]!.abs() <= _kBalanceEpsilon) {
      balances.remove(maxCreditor);
    }
    if (balances[maxDebtor]!.abs() <= _kBalanceEpsilon) {
      balances.remove(maxDebtor);
    }
  }
}

double _roundMoney(double value) => (value * 100).round() / 100;
