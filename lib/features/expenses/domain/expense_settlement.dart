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

/// Balances and transfer suggestions for one viewer within a single scope
/// (e.g. one expense post).
class ViewerSettlement {
  const ViewerSettlement({
    required this.balancesByCurrency,
    required this.suggestedTransfers,
  });

  /// Net balances from the provided expenses (caller scopes the list).
  final BalancesByCurrency balancesByCurrency;

  /// Transfers that involve the viewer as payer or payee; when there is no
  /// viewer id, every suggested transfer for that scope is returned.
  final List<SuggestedTransfer> suggestedTransfers;
}

/// Computes [ViewerSettlement] from [expenses] (already scoped, e.g. one post).
///
/// When [viewerUserId] is null or blank, every suggested transfer is returned.
ViewerSettlement computeViewerSettlement(
  Iterable<TripExpense> expenses,
  String? viewerUserId,
  {Iterable<SuggestedTransfer> settledTransfers = const []}
) {
  final balances = computeBalances(expenses);
  applySettledTransfersToBalances(
    balances: balances,
    settledTransfers: settledTransfers,
  );
  var transfers = suggestTransfers(balances);
  final v = viewerUserId?.trim();
  if (v != null && v.isNotEmpty) {
    transfers = transfers
        .where((t) => t.fromUserId == v || t.toUserId == v)
        .toList();
  }
  return ViewerSettlement(
    balancesByCurrency: balances,
    suggestedTransfers: transfers,
  );
}

/// Applies already-paid transfers on top of computed balances.
///
/// This makes paid transfers disappear from suggestions and impacts displayed
/// balances.
void applySettledTransfersToBalances({
  required BalancesByCurrency balances,
  required Iterable<SuggestedTransfer> settledTransfers,
}) {
  for (final transfer in settledTransfers) {
    final fromUserId = transfer.fromUserId.trim();
    final toUserId = transfer.toUserId.trim();
    final currency = transfer.currency.trim().toUpperCase();
    final amount = _roundMoney(transfer.amount);
    if (fromUserId.isEmpty || toUserId.isEmpty || currency.isEmpty) continue;
    if (amount <= _kBalanceEpsilon) continue;

    final bucket = balances.putIfAbsent(currency, () => <String, double>{});
    final fromBalance = (bucket[fromUserId] ?? 0) + amount;
    final toBalance = (bucket[toUserId] ?? 0) - amount;
    bucket[fromUserId] = _roundMoney(fromBalance);
    bucket[toUserId] = _roundMoney(toBalance);

    if (bucket[fromUserId]!.abs() <= _kBalanceEpsilon) {
      bucket.remove(fromUserId);
    }
    if (bucket[toUserId]!.abs() <= _kBalanceEpsilon) {
      bucket.remove(toUserId);
    }
    if (bucket.isEmpty) {
      balances.remove(currency);
    }
  }
}

/// Supported expense currencies for MVP (display + separate balance buckets).
const Set<String> kSupportedExpenseCurrencies = {'EUR', 'USD'};

/// Epsilon for floating-point comparisons (cent-level).
const double _kBalanceEpsilon = 0.009;

/// Computes per-user net balance by currency from shared expenses.
///
/// For each expense, each participant is debited their share (equal split or
/// explicit [TripExpense.participantShares]); [paidBy] is credited the full
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

    final bucket = result.putIfAbsent(currency, () => <String, double>{});

    final shares = _participantSharesForExpense(expense, participants);
    for (final uid in participants) {
      final share = shares[uid] ?? 0;
      bucket[uid] = (bucket[uid] ?? 0) - share;
    }
    bucket[paidBy] = (bucket[paidBy] ?? 0) + amount;
  }

  return result;
}

/// Resolves owed amount per participant; falls back to equal split when needed.
Map<String, double> _participantSharesForExpense(
  TripExpense expense,
  List<String> participants,
) {
  if (expense.splitMode != ExpenseSplitMode.customAmounts) {
    final n = participants.length;
    final per = n > 0 ? expense.amount / n : 0.0;
    return {for (final id in participants) id: per};
  }

  final raw = expense.participantShares;
  var sum = 0.0;
  final out = <String, double>{};
  for (final id in participants) {
    final v = raw[id];
    if (v == null || v < 0) {
      return {
        for (final uid in participants)
          uid: participants.isEmpty ? 0.0 : expense.amount / participants.length,
      };
    }
    out[id] = v;
    sum += v;
  }
  if ((sum - expense.amount).abs() > 0.02) {
    final n = participants.length;
    final per = n > 0 ? expense.amount / n : 0.0;
    return {for (final id in participants) id: per};
  }
  return out;
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
