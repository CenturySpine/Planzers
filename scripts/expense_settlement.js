'use strict';

/**
 * Port of lib/features/expenses/domain/expense_settlement.dart
 * Keep in sync with Dart when settlement rules change.
 */

const BALANCE_EPSILON = 0.009;

function roundMoney(value) {
  return Math.round(value * 100) / 100;
}

function splitModeFromFirestore(raw) {
  const s = (raw == null ? '' : String(raw)).trim().toLowerCase();
  if (s === 'custom' || s === 'amounts' || s === 'montants') {
    return 'customAmounts';
  }
  return 'equal';
}

function participantSharesFromFirestore(raw) {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return {};
  }
  const out = {};
  for (const [key, value] of Object.entries(raw)) {
    const k = String(key).trim();
    if (!k) continue;
    const n = typeof value === 'number' ? value : Number(value);
    if (Number.isFinite(n)) out[k] = n;
  }
  return out;
}

/** @typedef {{ id: string, groupId: string, amount: number, currency: string, paidBy: string, participantIds: string[], splitMode: string, participantShares: Record<string, number> }} TripExpense */

/**
 * @param {import('firebase-admin').firestore.DocumentSnapshot} doc
 * @returns {TripExpense}
 */
function tripExpenseFromDoc(doc) {
  const data = doc.data() || {};
  const amountRaw = data.amount;
  const amount =
    typeof amountRaw === 'number' && Number.isFinite(amountRaw)
      ? amountRaw
      : 0;

  return {
    id: doc.id,
    groupId: String(data.groupId || '').trim(),
    amount,
    currency: String(data.currency || 'EUR')
      .trim()
      .toUpperCase(),
    paidBy: String(data.paidBy || '').trim(),
    participantIds: ((data.participantIds || []))
      .map((e) => String(e).trim())
      .filter((id) => id.length > 0),
    splitMode: splitModeFromFirestore(data.splitMode),
    participantShares: participantSharesFromFirestore(data.participantShares),
  };
}

/**
 * @param {TripExpense} expense
 * @param {string[]} participants
 * @returns {Record<string, number>}
 */
function participantSharesForExpense(expense, participants) {
  if (expense.splitMode !== 'customAmounts') {
    const n = participants.length;
    const per = n > 0 ? expense.amount / n : 0;
    return Object.fromEntries(participants.map((id) => [id, per]));
  }

  const raw = expense.participantShares;
  let sum = 0;
  const out = {};
  for (const id of participants) {
    const v = raw[id];
    if (v == null || v < 0) {
      const per =
        participants.length > 0 ? expense.amount / participants.length : 0;
      return Object.fromEntries(participants.map((uid) => [uid, per]));
    }
    out[id] = v;
    sum += v;
  }
  if (Math.abs(sum - expense.amount) > 0.02) {
    const n = participants.length;
    const per = n > 0 ? expense.amount / n : 0;
    return Object.fromEntries(participants.map((id) => [id, per]));
  }
  return out;
}

/**
 * @param {Iterable<TripExpense>} expenses
 * @returns {Record<string, Record<string, number>>}
 */
function computeBalances(expenses) {
  /** @type {Record<string, Record<string, number>>} */
  const result = {};

  for (const expense of expenses) {
    const currency = expense.currency.trim().toUpperCase();
    if (!currency) continue;

    const participants = expense.participantIds
      .map((id) => id.trim())
      .filter((id) => id.length > 0);
    if (participants.length === 0) continue;

    const paidBy = expense.paidBy.trim();
    if (!paidBy) continue;

    const amount = expense.amount;
    if (amount <= 0) continue;

    if (!result[currency]) result[currency] = {};
    const bucket = result[currency];

    const shares = participantSharesForExpense(expense, participants);
    for (const uid of participants) {
      const share = shares[uid] ?? 0;
      bucket[uid] = (bucket[uid] ?? 0) - share;
    }
    bucket[paidBy] = (bucket[paidBy] ?? 0) + amount;
  }

  return result;
}

/**
 * @typedef {{ fromUserId: string, toUserId: string, amount: number, currency: string }} SuggestedTransfer
 */

/**
 * @param {Record<string, Record<string, number>>} balances
 * @param {Iterable<SuggestedTransfer>} settledTransfers
 */
function applySettledTransfersToBalances(balances, settledTransfers) {
  for (const transfer of settledTransfers) {
    const fromUserId = String(transfer.fromUserId || '').trim();
    const toUserId = String(transfer.toUserId || '').trim();
    const currency = String(transfer.currency || '')
      .trim()
      .toUpperCase();
    const amount = roundMoney(transfer.amount);
    if (!fromUserId || !toUserId || !currency) continue;
    if (amount <= BALANCE_EPSILON) continue;

    if (!balances[currency]) balances[currency] = {};
    const bucket = balances[currency];
    const fromBalance = (bucket[fromUserId] ?? 0) + amount;
    const toBalance = (bucket[toUserId] ?? 0) - amount;
    bucket[fromUserId] = roundMoney(fromBalance);
    bucket[toUserId] = roundMoney(toBalance);

    if (Math.abs(bucket[fromUserId]) <= BALANCE_EPSILON) {
      bucket[fromUserId] = 0;
    }
    if (Math.abs(bucket[toUserId]) <= BALANCE_EPSILON) {
      bucket[toUserId] = 0;
    }
  }
}

/**
 * @param {Record<string, number>} balances
 * @param {string} currency
 * @param {SuggestedTransfer[]} out
 */
function simplifyCurrency(balances, currency, out) {
  while (true) {
    let maxCreditor = null;
    let maxCredit = 0;
    let maxDebtor = null;
    let maxDebt = 0;

    for (const [id, value] of Object.entries(balances)) {
      if (value > maxCredit) {
        maxCredit = value;
        maxCreditor = id;
      }
      if (value < maxDebt) {
        maxDebt = value;
        maxDebtor = id;
      }
    }

    if (
      maxCreditor == null ||
      maxDebtor == null ||
      maxCredit <= BALANCE_EPSILON ||
      maxDebt >= -BALANCE_EPSILON
    ) {
      break;
    }

    const pay = roundMoney(maxCredit < -maxDebt ? maxCredit : -maxDebt);
    if (pay <= BALANCE_EPSILON) break;

    out.push({
      fromUserId: maxDebtor,
      toUserId: maxCreditor,
      amount: pay,
      currency,
    });

    balances[maxCreditor] = roundMoney(maxCredit - pay);
    balances[maxDebtor] = roundMoney(maxDebt + pay);

    if (Math.abs(balances[maxCreditor]) <= BALANCE_EPSILON) {
      delete balances[maxCreditor];
    }
    if (Math.abs(balances[maxDebtor]) <= BALANCE_EPSILON) {
      delete balances[maxDebtor];
    }
  }
}

/**
 * @param {Record<string, Record<string, number>>} balancesByCurrency
 * @returns {SuggestedTransfer[]}
 */
function suggestTransfers(balancesByCurrency) {
  /** @type {SuggestedTransfer[]} */
  const transfers = [];

  for (const [currency, raw] of Object.entries(balancesByCurrency)) {
    /** @type {Record<string, number>} */
    const working = {};
    for (const [id, value] of Object.entries(raw)) {
      const v = roundMoney(value);
      if (Math.abs(v) > BALANCE_EPSILON) {
        working[id] = v;
      }
    }
    if (Object.keys(working).length === 0) continue;
    simplifyCurrency(working, currency, transfers);
  }

  return transfers;
}

/**
 * @param {Iterable<TripExpense>} expenses
 * @param {Iterable<SuggestedTransfer>} [settledTransfers]
 * @returns {{ balancesByCurrency: Record<string, Record<string, number>>, suggestedTransfers: SuggestedTransfer[] }}
 */
function computeSettlement(expenses, settledTransfers = []) {
  const balances = computeBalances(expenses);
  applySettledTransfersToBalances(balances, settledTransfers);
  const suggestedTransfers = suggestTransfers(balances);
  return { balancesByCurrency: balances, suggestedTransfers };
}

module.exports = {
  BALANCE_EPSILON,
  roundMoney,
  tripExpenseFromDoc,
  computeBalances,
  applySettledTransfersToBalances,
  suggestTransfers,
  computeSettlement,
};
