'use strict';

/**
 * Authoritative settlement math for Cloud Functions (participantId field names).
 * Keep logic in sync with scripts/expense_settlement.js (utility scripts; fromUserId naming).
 * When changing algorithms, update both files.
 */

const BALANCE_EPSILON = 0.009;

// Balances below this threshold are considered at equilibrium and sent as zero to the client.
const BALANCE_SETTLEMENT_THRESHOLD = 0.50;

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

/**
 * Resolves how many billing parts an id represents.
 *
 * Priority: participant (TripMember) ids return 1; group ids return group.parts.
 * Since participantGroups are the only special case and we don't have a membersMap
 * at this layer, the rule simplifies to: if id is in groupsMap return group.parts, else 1.
 *
 * @param {string} id
 * @param {Record<string, { parts: number }>} groupsMap  keyed by groupId
 * @returns {number}
 */
function resolveUnit(id, groupsMap) {
  const g = groupsMap[id];
  return g != null && g.parts > 0 ? g.parts : 1;
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
 * @param {Record<string, { parts: number }>} [groupsMap]
 * @returns {Record<string, number>}
 */
function participantSharesForExpense(expense, participants, groupsMap = {}) {
  if (expense.splitMode !== 'customAmounts') {
    const totalParts = participants.reduce(
      (sum, id) => sum + resolveUnit(id, groupsMap),
      0
    );
    if (totalParts <= 0) {
      return Object.fromEntries(participants.map((id) => [id, 0]));
    }
    return Object.fromEntries(
      participants.map((id) => [
        id,
        expense.amount * resolveUnit(id, groupsMap) / totalParts,
      ])
    );
  }

  const raw = expense.participantShares;
  let sum = 0;
  const out = {};
  for (const id of participants) {
    const v = raw[id];
    if (v == null || v < 0) {
      const totalParts = participants.reduce(
        (s, i) => s + resolveUnit(i, groupsMap),
        0
      );
      if (totalParts <= 0) {
        return Object.fromEntries(participants.map((pid) => [pid, 0]));
      }
      return Object.fromEntries(
        participants.map((pid) => [
          pid,
          expense.amount * resolveUnit(pid, groupsMap) / totalParts,
        ])
      );
    }
    out[id] = v;
    sum += v;
  }
  if (Math.abs(sum - expense.amount) > 0.02) {
    const totalParts = participants.reduce(
      (s, i) => s + resolveUnit(i, groupsMap),
      0
    );
    if (totalParts <= 0) {
      return Object.fromEntries(participants.map((id) => [id, 0]));
    }
    return Object.fromEntries(
      participants.map((id) => [
        id,
        expense.amount * resolveUnit(id, groupsMap) / totalParts,
      ])
    );
  }
  return out;
}

/**
 * @param {Iterable<TripExpense>} expenses
 * @param {Record<string, { parts: number }>} [groupsMap]  keyed by groupId
 * @returns {Record<string, Record<string, number>>}
 */
function computeBalances(expenses, groupsMap = {}) {
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

    const shares = participantSharesForExpense(expense, participants, groupsMap);
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

/**
 * Normalizes a single net balance for Firestore client display.
 * Values below the settlement threshold (including rounding dust) are sent as 0.
 *
 * @param {number} value
 * @returns {number}
 */
function normalizeNetForFirestore(value) {
  const rounded = roundMoney(value);
  if (Math.abs(rounded) < BALANCE_SETTLEMENT_THRESHOLD) {
    return 0;
  }
  return rounded;
}

/**
 * Keeps every participant entry; equilibrium balances are written as 0.
 *
 * @param {Record<string, number>} nets
 * @returns {Record<string, number>}
 */
function normalizeNetsMapForFirestore(nets) {
  /** @type {Record<string, number>} */
  const out = {};
  for (const [participantId, value] of Object.entries(nets)) {
    out[participantId] = normalizeNetForFirestore(value);
  }
  return out;
}

/**
 * @param {Record<string, Record<string, number>>} balancesByCurrency
 * @returns {Record<string, Record<string, number>>}
 */
function balancesForClientFirestore(balancesByCurrency) {
  /** @type {Record<string, Record<string, number>>} */
  const result = {};
  for (const [currency, nets] of Object.entries(balancesByCurrency)) {
    result[currency] = normalizeNetsMapForFirestore(nets);
  }
  return result;
}

/**
 * Input for suggestTransfers: only balances above the settlement threshold.
 *
 * @param {Record<string, Record<string, number>>} balancesByCurrency
 * @returns {Record<string, Record<string, number>>}
 */
function balancesForSuggestions(balancesByCurrency) {
  /** @type {Record<string, Record<string, number>>} */
  const result = {};
  for (const [currency, nets] of Object.entries(balancesByCurrency)) {
    const filtered = {};
    for (const [participantId, value] of Object.entries(nets)) {
      if (Math.abs(value) >= BALANCE_SETTLEMENT_THRESHOLD) {
        filtered[participantId] = value;
      }
    }
    result[currency] = filtered;
  }
  return result;
}

module.exports = {
  BALANCE_EPSILON,
  BALANCE_SETTLEMENT_THRESHOLD,
  roundMoney,
  resolveUnit,
  tripExpenseFromDoc,
  computeBalances,
  suggestTransfers,
  computeGroupSummary,
  amountsMatch,
  normalizeNetForFirestore,
  normalizeNetsMapForFirestore,
  balancesForClientFirestore,
  balancesForSuggestions,
};
