'use strict';

const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const {
  BALANCE_EPSILON,
  BALANCE_SETTLEMENT_THRESHOLD,
  roundMoney,
  tripExpenseFromDoc,
  computeBalances,
  suggestTransfers,
  computeGroupSummary,
  amountsMatch,
} = require('./expense_settlement');

const BATCH_OP_LIMIT = 499;

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function groupRef(db, tripId, groupId) {
  return db
    .collection('trips')
    .doc(tripId)
    .collection('expenseGroups')
    .doc(groupId);
}

function expensesCol(db, tripId) {
  return db.collection('trips').doc(tripId).collection('expenses');
}

function expensesStatesRef(db, tripId) {
  return db
    .collection('trips')
    .doc(tripId)
    .collection('expenses_states')
    .doc('default');
}

function parseBoolFlag(raw, defaultValue) {
  if (raw === true) return true;
  if (raw === false) return false;
  if (typeof raw === 'string') {
    const normalized = raw.trim().toLowerCase();
    if (normalized === 'true') return true;
    if (normalized === 'false') return false;
  }
  return defaultValue;
}

async function areExpenseNotificationsEnabled(db, tripId) {
  const snap = await expensesStatesRef(db, tripId).get();
  if (!snap.exists) return true;
  return parseBoolFlag(snap.data()?.expensesNotificationsEnabled, true);
}

async function resolveCallerParticipantId(db, tripId, uid) {
  const snap = await db
    .collection('trips')
    .doc(tripId)
    .collection('participants')
    .where('userId', '==', uid)
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0].id;
}

async function resolveParticipantData(db, tripId, participantId) {
  const snap = await db
    .collection('trips')
    .doc(tripId)
    .collection('participants')
    .doc(participantId)
    .get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  const userId = normalizeString(data.userId);
  const displayName = normalizeString(data.participantName) || 'Utilisateur';
  return { userId: userId || null, displayName };
}

/**
 * Resolves notification recipients for a billing unit id.
 * If the id belongs to a ParticipantGroup, returns data for all group members that have a userId.
 * Otherwise behaves like resolveParticipantData.
 *
 * @returns {Promise<Array<{ userId: string|null, displayName: string }>>}
 */
async function resolveUnitRecipients(db, tripId, unitId) {
  // Try participant first (priority per plan)
  const participantSnap = await db
    .collection('trips')
    .doc(tripId)
    .collection('participants')
    .doc(unitId)
    .get();
  if (participantSnap.exists) {
    const data = participantSnap.data() || {};
    const userId = normalizeString(data.userId);
    const displayName = normalizeString(data.participantName) || 'Utilisateur';
    return [{ userId: userId || null, displayName }];
  }

  // Try participantGroup
  const groupSnap = await db
    .collection('trips')
    .doc(tripId)
    .collection('participantGroups')
    .doc(unitId)
    .get();
  if (!groupSnap.exists) return [];
  const groupData = groupSnap.data() || {};
  const memberIds = Array.isArray(groupData.memberIds) ? groupData.memberIds : [];

  const memberSnaps = await Promise.all(
    memberIds
      .map((mid) => normalizeString(mid))
      .filter((mid) => mid.length > 0)
      .map((mid) =>
        db
          .collection('trips')
          .doc(tripId)
          .collection('participants')
          .doc(mid)
          .get()
      )
  );

  return memberSnaps
    .filter((snap) => snap.exists)
    .map((snap) => {
      const d = snap.data() || {};
      const userId = normalizeString(d.userId);
      const displayName = normalizeString(d.participantName) || 'Utilisateur';
      return { userId: userId || null, displayName };
    });
}

function formatReimbursementAmount(amount) {
  const fixed = parseFloat(amount.toFixed(2));
  return fixed % 1 === 0 ? fixed.toFixed(0) : fixed.toFixed(2);
}

async function assertExpenseGroupVisibleToCaller({
  db,
  tripId,
  groupId,
  uid,
}) {
  const tripSnap = await db.collection('trips').doc(tripId).get();
  if (!tripSnap.exists) {
    throw new HttpsError('not-found', 'Voyage introuvable');
  }
  const memberUserIds = tripSnap.data()?.memberUserIds;
  if (!Array.isArray(memberUserIds) || !memberUserIds.includes(uid)) {
    throw new HttpsError('permission-denied', 'Accès refusé');
  }

  const groupSnap = await groupRef(db, tripId, groupId).get();
  if (!groupSnap.exists) {
    throw new HttpsError('not-found', 'Poste introuvable');
  }

  const visibleTo = groupSnap.data()?.visibleToMemberIds;
  if (!Array.isArray(visibleTo) || visibleTo.length === 0) {
    throw new HttpsError('permission-denied', 'Poste non visible');
  }

  const callerParticipantId = await resolveCallerParticipantId(db, tripId, uid);
  if (!callerParticipantId || !visibleTo.includes(callerParticipantId)) {
    throw new HttpsError('permission-denied', 'Poste non visible');
  }

  return { groupSnap, callerParticipantId };
}

function roleRank(role) {
  const r = normalizeString(role).toLowerCase();
  if (r === 'owner') return 3;
  if (r === 'admin') return 2;
  if (r === 'chef') return 1;
  return 0;
}

/** Co-admin uids on the trip document (creator is always admin via ownerId). */
function tripAdminMemberIdSet(tripData) {
  const raw = tripData?.adminMemberIds;
  if (!Array.isArray(raw)) return new Set();
  return new Set(raw.map((v) => String(v)));
}

function tripCallerRoleRank(tripData, uid) {
  const cleanUid = normalizeString(uid);
  if (!cleanUid) return -1;
  if (normalizeString(tripData?.ownerId) === cleanUid) return roleRank('owner');
  return tripAdminMemberIdSet(tripData).has(cleanUid) ? roleRank('admin') : 0;
}

function deleteExpensePostMinRole(tripData) {
  const expenses = tripData?.permissions?.expenses;
  const raw =
    expenses && typeof expenses.deleteExpensePost === 'string'
      ? expenses.deleteExpensePost
      : 'participant';
  return roleRank(raw);
}

async function loadGroupExpenses(db, tripId, groupId) {
  const snap = await expensesCol(db, tripId)
    .where('groupId', '==', groupId)
    .get();
  return snap.docs.map(tripExpenseFromDoc);
}

/**
 * @param {import('firebase-admin').firestore.Firestore} db
 * @param {string} tripId
 * @param {string} groupId
 */
async function recomputeExpenseGroupSettlementForGroup(db, tripId, groupId) {
  const cleanGroupId = normalizeString(groupId);
  if (!cleanGroupId) return;

  const gRef = groupRef(db, tripId, cleanGroupId);
  const groupSnap = await gRef.get();
  if (!groupSnap.exists) return;

  await gRef.set(
    { recalcGeneration: FieldValue.increment(1) },
    { merge: true }
  );
  const afterIncSnap = await gRef.get();
  const myGeneration = afterIncSnap.data()?.recalcGeneration;
  if (typeof myGeneration !== 'number') return;

  const [expenses, participantGroupsSnap] = await Promise.all([
    loadGroupExpenses(db, tripId, cleanGroupId),
    db.collection('trips').doc(tripId).collection('participantGroups').get(),
  ]);
  const groupsMap = {};
  for (const doc of participantGroupsSnap.docs) {
    const d = doc.data() || {};
    const parts = typeof d.parts === 'number' && d.parts > 0 ? d.parts : 1;
    groupsMap[doc.id] = { parts };
  }
  const balancesByCurrency = computeBalances(expenses, groupsMap);

  // Zero out members whose net balance is below the settlement threshold before
  // computing suggestions and writing to Firestore, so the client receives no
  // intelligence about what amount counts as "at equilibrium".
  const thresholdedByCurrency = {};
  for (const [currency, nets] of Object.entries(balancesByCurrency)) {
    const thresholdedNets = {};
    for (const [participantId, value] of Object.entries(nets)) {
      if (Math.abs(value) >= BALANCE_SETTLEMENT_THRESHOLD) {
        thresholdedNets[participantId] = value;
      }
    }
    thresholdedByCurrency[currency] = thresholdedNets;
  }

  const suggested = suggestTransfers(thresholdedByCurrency);
  const summary = computeGroupSummary(expenses);

  const balancesCol = gRef.collection('balances');
  const suggestionsCol = gRef.collection('suggestedReimbursements');
  const summaryRef = gRef.collection('summary').doc('current');

  const [existingSuggestions, existingBalances] = await Promise.all([
    suggestionsCol.get(),
    balancesCol.get(),
  ]);

  const currencyKeys = new Set(Object.keys(thresholdedByCurrency));

  await db.runTransaction(async (tx) => {
    const freshGroup = await tx.get(gRef);
    const currentGen = freshGroup.data()?.recalcGeneration;
    if (currentGen !== myGeneration) return;

    for (const doc of existingSuggestions.docs) {
      tx.delete(doc.ref);
    }

    for (const doc of existingBalances.docs) {
      if (!currencyKeys.has(doc.id)) {
        tx.delete(doc.ref);
      }
    }

    for (const [currency, nets] of Object.entries(thresholdedByCurrency)) {
      const cleanedNets = {};
      for (const [participantId, value] of Object.entries(nets)) {
        if (Math.abs(value) > BALANCE_EPSILON) {
          cleanedNets[participantId] = value;
        }
      }
      tx.set(balancesCol.doc(currency), {
        currency,
        nets: cleanedNets,
      });
    }

    for (const transfer of suggested) {
      const docRef = suggestionsCol.doc();
      tx.set(docRef, {
        fromParticipantId: transfer.fromParticipantId,
        toParticipantId: transfer.toParticipantId,
        amount: transfer.amount,
        currency: transfer.currency,
      });
    }

    tx.set(summaryRef, {
      settlementComputedAt: FieldValue.serverTimestamp(),
      postTotalsByCurrency: summary.postTotalsByCurrency,
      paidByTotalsByCurrency: summary.paidByTotalsByCurrency,
    });
  });
}

const recomputeExpenseGroupSettlement = onDocumentWritten(
  'trips/{tripId}/expenses/{expenseId}',
  async (event) => {
    const tripId = event.params.tripId;
    const db = admin.firestore();

    const before = event.data.before?.data();
    const after = event.data.after?.data();

    const afterOpType = after != null ? normalizeString(after.operationType) : null;
    const beforeOpType = before != null ? normalizeString(before.operationType) : null;

    // Skip recalc for any settlement write (creation or deletion).
    // markExpenseReimbursementPaid and unmarkExpenseReimbursementPaid handle
    // suggestion and balance updates directly in their own transactions.
    const opType = afterOpType ?? beforeOpType;
    if (opType === 'settlement') return;

    // Regular expense written while locked → skip (lock freezes the suggested transfers).
    const statesSnap = await expensesStatesRef(db, tripId).get();
    if (parseBoolFlag(statesSnap.data()?.expensesLocked, false)) return;

    const groupIds = new Set();
    const beforeGroup = normalizeString(before?.groupId);
    const afterGroup = normalizeString(after?.groupId);
    if (beforeGroup) groupIds.add(beforeGroup);
    if (afterGroup) groupIds.add(afterGroup);

    for (const groupId of groupIds) {
      await recomputeExpenseGroupSettlementForGroup(db, tripId, groupId);
    }
  }
);

const markExpenseReimbursementPaid = onCall({}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }

  const tripId = normalizeString(request.data?.tripId);
  const groupId = normalizeString(request.data?.groupId);
  const fromParticipantId = normalizeString(request.data?.fromParticipantId);
  const toParticipantId = normalizeString(request.data?.toParticipantId);
  const currency = normalizeString(request.data?.currency).toUpperCase();
  const amountRaw = request.data?.amount;
  const amount =
    typeof amountRaw === 'number' && Number.isFinite(amountRaw)
      ? amountRaw
      : Number(amountRaw);

  if (
    !tripId ||
    !groupId ||
    !fromParticipantId ||
    !toParticipantId ||
    !currency ||
    !Number.isFinite(amount) ||
    amount <= BALANCE_EPSILON
  ) {
    throw new HttpsError('invalid-argument', 'Paramètres invalides');
  }

  const db = admin.firestore();
  await assertExpenseGroupVisibleToCaller({ db, tripId, groupId, uid });

  const gRef = groupRef(db, tripId, groupId);
  const expensesCollection = expensesCol(db, tripId);
  let createdExpenseId = null;

  await db.runTransaction(async (tx) => {
    // All reads must come before any writes in a Firestore transaction.
    const balanceDocRef = gRef.collection('balances').doc(currency);
    const [suggestionsSnap, settlementsSnap, balanceSnap] = await Promise.all([
      tx.get(gRef.collection('suggestedReimbursements')),
      tx.get(expensesCollection.where('groupId', '==', groupId)),
      tx.get(balanceDocRef),
    ]);

    const matchedSuggestion = suggestionsSnap.docs.find((doc) => {
      const d = doc.data() || {};
      return (
        normalizeString(d.fromParticipantId) === fromParticipantId &&
        normalizeString(d.toParticipantId) === toParticipantId &&
        normalizeString(d.currency).toUpperCase() === currency &&
        amountsMatch(d.amount, amount)
      );
    });
    if (!matchedSuggestion) {
      throw new HttpsError(
        'failed-precondition',
        'Ce remboursement ne correspond pas à une suggestion actuelle'
      );
    }

    for (const doc of settlementsSnap.docs) {
      const expense = tripExpenseFromDoc(doc);
      if (expense.operationType !== 'settlement') continue;
      if (
        expense.paidBy === fromParticipantId &&
        expense.participantIds.length === 1 &&
        expense.participantIds[0] === toParticipantId &&
        expense.currency === currency &&
        amountsMatch(expense.amount, amount)
      ) {
        throw new HttpsError(
          'already-exists',
          'Ce remboursement est déjà enregistré'
        );
      }
    }

    // Writes — all reads above are complete.
    const newRef = expensesCollection.doc();
    createdExpenseId = newRef.id;
    tx.set(newRef, {
      groupId,
      operationType: 'settlement',
      title: 'Remboursement',
      amount,
      currency,
      paidBy: fromParticipantId,
      participantIds: [toParticipantId],
      splitMode: 'equal',
      expenseDate: Timestamp.now(),
      createdAt: FieldValue.serverTimestamp(),
      createdBy: uid,
    });

    // Delete the matched suggestion directly — the trigger skips recalc on settlement writes,
    // so we must keep Firestore consistent here in the same transaction.
    tx.delete(matchedSuggestion.ref);

    // Update net balances for this currency to mirror what computeBalances would produce
    // for this settlement: debtor (fromParticipantId) balance goes up, creditor goes down.
    const nets = Object.assign({}, balanceSnap.data()?.nets || {});
    nets[fromParticipantId] = roundMoney((nets[fromParticipantId] ?? 0) + amount);
    nets[toParticipantId] = roundMoney((nets[toParticipantId] ?? 0) - amount);
    for (const [pid, val] of Object.entries(nets)) {
      if (Math.abs(val) <= BALANCE_EPSILON) delete nets[pid];
    }
    tx.set(balanceDocRef, { currency, nets });
  });

  try {
    if (await areExpenseNotificationsEnabled(db, tripId)) {
      const [toRecipients, fromRecipients, tripSnap] = await Promise.all([
        resolveUnitRecipients(db, tripId, toParticipantId),
        resolveUnitRecipients(db, tripId, fromParticipantId),
        db.collection('trips').doc(tripId).get(),
      ]);
      const fromName = (fromRecipients[0]?.displayName) || "Quelqu'un";
      const tripTitle = normalizeString(tripSnap.data()?.title) || 'Voyage';
      const amountLabel = formatReimbursementAmount(amount);
      const candidateRecipients = toRecipients
        .map((r) => r.userId)
        .filter((userId) => userId && userId !== uid);
      if (candidateRecipients.length > 0) {
        await db.collection('notificationQueue').add({
          channel: 'expenses',
          type: 'expense_reimbursement_paid',
          tripId,
          actorId: uid,
          targetPath: `/trips/${tripId}/expenses`,
          title: `Dépenses · ${tripTitle}`,
          body: `${fromName} vous a remboursé ${amountLabel} ${currency}`,
          candidateRecipients,
          skipPresenceCheck: false,
          androidChannelId: 'planerz_expenses',
          payload: {},
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    }
  } catch (e) {
    console.warn('markExpenseReimbursementPaid: notification failed', e);
  }

  return { expenseId: createdExpenseId };
});

const unmarkExpenseReimbursementPaid = onCall({}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }

  const tripId = normalizeString(request.data?.tripId);
  const groupId = normalizeString(request.data?.groupId);
  const expenseId = normalizeString(request.data?.expenseId);

  if (!tripId || !groupId || !expenseId) {
    throw new HttpsError('invalid-argument', 'Paramètres invalides');
  }

  const db = admin.firestore();
  await assertExpenseGroupVisibleToCaller({ db, tripId, groupId, uid });

  const expenseRef = expensesCol(db, tripId).doc(expenseId);
  const expenseSnap = await expenseRef.get();
  if (!expenseSnap.exists) {
    throw new HttpsError('not-found', 'Opération introuvable');
  }

  const expense = tripExpenseFromDoc(expenseSnap);
  if (
    expense.operationType !== 'settlement' ||
    normalizeString(expense.groupId) !== groupId
  ) {
    throw new HttpsError('failed-precondition', 'Opération invalide');
  }

  const fromParticipantId = normalizeString(expense.paidBy);
  const toParticipantId = normalizeString(expense.participantIds?.[0]);
  const settlementCurrency = expense.currency;
  const settlementAmount = expense.amount;

  const gRef = groupRef(db, tripId, groupId);

  await db.runTransaction(async (tx) => {
    // All reads first.
    const balanceDocRef = gRef.collection('balances').doc(settlementCurrency);
    const [freshExpense, balanceSnap] = await Promise.all([
      tx.get(expenseRef),
      tx.get(balanceDocRef),
    ]);
    if (!freshExpense.exists) {
      throw new HttpsError('not-found', 'Opération introuvable');
    }

    // Writes.
    tx.delete(expenseRef);

    // Restore the suggestion that was removed when the settlement was created.
    if (fromParticipantId && toParticipantId) {
      tx.set(gRef.collection('suggestedReimbursements').doc(), {
        fromParticipantId,
        toParticipantId,
        amount: settlementAmount,
        currency: settlementCurrency,
      });

      // Reverse the balance delta applied during mark-as-paid.
      const nets = Object.assign({}, balanceSnap.data()?.nets || {});
      nets[fromParticipantId] = roundMoney((nets[fromParticipantId] ?? 0) - settlementAmount);
      nets[toParticipantId] = roundMoney((nets[toParticipantId] ?? 0) + settlementAmount);
      for (const [pid, val] of Object.entries(nets)) {
        if (Math.abs(val) <= BALANCE_EPSILON) delete nets[pid];
      }
      tx.set(balanceDocRef, { currency: settlementCurrency, nets });
    }
  });

  try {
    if (await areExpenseNotificationsEnabled(db, tripId)) {
      if (fromParticipantId && toParticipantId) {
        const [toRecipients, fromRecipients, tripSnap] = await Promise.all([
          resolveUnitRecipients(db, tripId, toParticipantId),
          resolveUnitRecipients(db, tripId, fromParticipantId),
          db.collection('trips').doc(tripId).get(),
        ]);
        const fromName = (fromRecipients[0]?.displayName) || "Quelqu'un";
        const tripTitle = normalizeString(tripSnap.data()?.title) || 'Voyage';
        const amountLabel = formatReimbursementAmount(expense.amount);
        const candidateRecipients = toRecipients
          .map((r) => r.userId)
          .filter((userId) => userId && userId !== uid);
        if (candidateRecipients.length > 0) {
          await db.collection('notificationQueue').add({
            channel: 'expenses',
            type: 'expense_reimbursement_unpaid',
            tripId,
            actorId: uid,
            targetPath: `/trips/${tripId}/expenses`,
            title: `Dépenses · ${tripTitle}`,
            body: `${fromName} a annulé un remboursement de ${amountLabel} ${expense.currency}`,
            candidateRecipients,
            skipPresenceCheck: false,
            androidChannelId: 'planerz_expenses',
            payload: {},
            createdAt: FieldValue.serverTimestamp(),
          });
        }
      }
    }
  } catch (e) {
    console.warn('unmarkExpenseReimbursementPaid: notification failed', e);
  }

  return { ok: true };
});

async function commitBatches(db, ops) {
  for (let i = 0; i < ops.length; i += BATCH_OP_LIMIT) {
    const batch = db.batch();
    const slice = ops.slice(i, i + BATCH_OP_LIMIT);
    for (const op of slice) {
      if (op.type === 'delete') batch.delete(op.ref);
      else if (op.type === 'set') batch.set(op.ref, op.data, op.options);
    }
    await batch.commit();
  }
}

const deleteExpenseGroup = onCall({}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }

  const tripId = normalizeString(request.data?.tripId);
  const groupId = normalizeString(request.data?.groupId);
  if (!tripId || !groupId) {
    throw new HttpsError('invalid-argument', 'Paramètres invalides');
  }

  const db = admin.firestore();
  const tripSnap = await db.collection('trips').doc(tripId).get();
  if (!tripSnap.exists) {
    throw new HttpsError('not-found', 'Voyage introuvable');
  }
  const tripData = tripSnap.data() || {};
  const memberUserIds = tripData.memberUserIds;
  if (!Array.isArray(memberUserIds) || !memberUserIds.includes(uid)) {
    throw new HttpsError('permission-denied', 'Accès refusé');
  }
  if (
    tripCallerRoleRank(tripData, uid) < deleteExpensePostMinRole(tripData)
  ) {
    throw new HttpsError(
      'permission-denied',
      'Droits insuffisants pour supprimer ce poste'
    );
  }

  const gRef = groupRef(db, tripId, groupId);
  const groupSnap = await gRef.get();
  if (!groupSnap.exists) {
    throw new HttpsError('not-found', 'Poste introuvable');
  }

  const visibleTo = groupSnap.data()?.visibleToMemberIds;
  const callerParticipantId = await resolveCallerParticipantId(db, tripId, uid);
  if (
    !Array.isArray(visibleTo) ||
    !callerParticipantId ||
    !visibleTo.includes(callerParticipantId)
  ) {
    throw new HttpsError('permission-denied', 'Poste non visible');
  }

  const ops = [];

  const expensesSnap = await expensesCol(db, tripId)
    .where('groupId', '==', groupId)
    .get();
  for (const doc of expensesSnap.docs) {
    ops.push({ type: 'delete', ref: doc.ref });
  }

  const balancesSnap = await gRef.collection('balances').get();
  for (const doc of balancesSnap.docs) {
    ops.push({ type: 'delete', ref: doc.ref });
  }

  const suggestionsSnap = await gRef.collection('suggestedReimbursements').get();
  for (const doc of suggestionsSnap.docs) {
    ops.push({ type: 'delete', ref: doc.ref });
  }

  const summarySnap = await gRef.collection('summary').get();
  for (const doc of summarySnap.docs) {
    ops.push({ type: 'delete', ref: doc.ref });
  }

  ops.push({ type: 'delete', ref: gRef });

  await commitBatches(db, ops);
  return { ok: true };
});

const refreshExpenseGroupSettlement = onCall({}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }

  const tripId = normalizeString(request.data?.tripId);
  const groupId = normalizeString(request.data?.groupId);
  if (!tripId || !groupId) {
    throw new HttpsError('invalid-argument', 'Paramètres invalides');
  }

  const db = admin.firestore();
  const tripSnap = await db.collection('trips').doc(tripId).get();
  if (!tripSnap.exists) {
    throw new HttpsError('not-found', 'Voyage introuvable');
  }
  if (tripCallerRoleRank(tripSnap.data() || {}, uid) < roleRank('admin')) {
    throw new HttpsError('permission-denied', 'Droits insuffisants');
  }

  await recomputeExpenseGroupSettlementForGroup(db, tripId, groupId);
  return { ok: true };
});

module.exports = {
  recomputeExpenseGroupSettlement,
  markExpenseReimbursementPaid,
  unmarkExpenseReimbursementPaid,
  deleteExpenseGroup,
  recomputeExpenseGroupSettlementForGroup,
  refreshExpenseGroupSettlement,
  tripCallerRoleRank,
  roleRank,
};
