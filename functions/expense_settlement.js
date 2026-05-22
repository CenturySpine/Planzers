'use strict';

/**
 * Authoritative settlement math for Cloud Functions (participantId field names).
 * Keep logic in sync with scripts/expense_settlement.js (utility scripts; fromUserId naming).
 * When changing algorithms, update both files.
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

function operationTypeFromFirestore(raw) {
  const s = (raw == null ? '' : String(raw)).trim().toLowerCase();
  return s === 'settlement' ? 'settlement' : 'expense';
}

/** @typedef {{ id: string, groupId: string, operationType: string, amount: number, currency: string, paidBy: string, participantIds: string[], splitMode: string, participantShares: Record<string, number> }} TripExpense */

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
    operationType: operationTypeFromFirestore(data.operationType),
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
      return Object.fromEntries(participants.map((pid) => [pid, per]));
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
    for (const participantId of participants) {
      const share = shares[participantId] ?? 0;
      bucket[participantId] = (bucket[participantId] ?? 0) - share;
    }
    bucket[paidBy] = (bucket[paidBy] ?? 0) + amount;
  }

  for (const currency of Object.keys(result)) {
    const bucket = result[currency];
    for (const [participantId, value] of Object.entries(bucket)) {
      const rounded = roundMoney(value);
      bucket[participantId] =
        Math.abs(rounded) <= BALANCE_EPSILON ? 0 : rounded;
    }
  }

  return result;
}

/**
 * @typedef {{ fromParticipantId: string, toParticipantId: string, amount: number, currency: string }} SuggestedTransfer
 */

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
      fromParticipantId: maxDebtor,
      toParticipantId: maxCreditor,
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
 * @returns {{ postTotalsByCurrency: Record<string, number>, paidByTotalsByCurrency: Record<string, Record<string, number>> }}
 */
function computeGroupSummary(expenses) {
  /** @type {Record<string, number>} */
  const postTotalsByCurrency = {};
  /** @type {Record<string, Record<string, number>>} */
  const paidByTotalsByCurrency = {};

  for (const expense of expenses) {
    if (expense.operationType !== 'expense') continue;
    const currency = expense.currency.trim().toUpperCase();
    if (!currency) continue;
    const amount = expense.amount;
    if (amount <= 0) continue;

    postTotalsByCurrency[currency] = roundMoney(
      (postTotalsByCurrency[currency] ?? 0) + amount
    );

    const paidBy = expense.paidBy.trim();
    if (!paidBy) continue;
    if (!paidByTotalsByCurrency[paidBy]) {
      paidByTotalsByCurrency[paidBy] = {};
    }
    const bucket = paidByTotalsByCurrency[paidBy];
    bucket[currency] = roundMoney((bucket[currency] ?? 0) + amount);
  }

  return { postTotalsByCurrency, paidByTotalsByCurrency };
}

function amountsMatch(a, b) {
  return Math.abs(roundMoney(a) - roundMoney(b)) <= BALANCE_EPSILON;
}

module.exports = {
  BALANCE_EPSILON,
  roundMoney,
  tripExpenseFromDoc,
  computeBalances,
  suggestTransfers,
  computeGroupSummary,
  amountsMatch,
};
