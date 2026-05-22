'use strict';

/**
 * trip_expense_settlements.js
 *
 * Lecture seule : soldes et remboursements suggérés pour le poste principal
 * d'un voyage (isDefault, ex. « Commun »), même logique que l'onglet « Équilibres ».
 * Libellés : memberPublicLabels du voyage, puis users/{uid} si absent (prod legacy).
 *
 * Algorithme : scripts/expense_settlement.js (script utilitaire).
 * En production, les remboursements payés sont des expenses operationType settlement ;
 * expenseSettledTransfers est legacy (ignoré par l'app).
 *
 * Usage :
 *   node trip_expense_settlements.js --key <service-account.json> --trip <tripId>
 *
 * Options :
 *   --key <path>            Compte de service Firebase (obligatoire)
 *   --trip <tripId>         ID du voyage (obligatoire)
 *   --include-settled       Déduire les remboursements déjà enregistrés (défaut : ignorés)
 *   --separator <char>      Séparateur entre colonnes (ex. "," ou ";") — sinon tableau aligné
 *   --json                  Sortie JSON (sinon texte lisible)
 */

const fs = require('fs');
const path = require('path');

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch {
    return require(path.join(__dirname, 'migration', 'node_modules', 'firebase-admin'));
  }
}

const admin = loadFirebaseAdmin();
const {
  BALANCE_EPSILON,
  roundMoney,
  tripExpenseFromDoc,
  computeSettlement,
} = require('./expense_settlement');

function parseArgs(argv) {
  const opts = {
    keyPath: '',
    tripId: '',
    json: false,
    includeSettled: false,
    separator: null,
  };
  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (token === '--json') {
      opts.json = true;
      continue;
    }
    if (token === '--include-settled') {
      opts.includeSettled = true;
      continue;
    }
    if (!token.startsWith('--')) continue;
    const eqIdx = token.indexOf('=');
    const flag = eqIdx >= 0 ? token.slice(0, eqIdx) : token;
    const inlineVal = eqIdx >= 0 ? token.slice(eqIdx + 1) : null;
    const nextVal = inlineVal ?? argv[i + 1];
    const consume = () => {
      if (inlineVal === null) i++;
    };
    if (flag === '--key') {
      opts.keyPath = (nextVal || '').trim();
      consume();
    } else if (flag === '--trip') {
      opts.tripId = (nextVal || '').trim();
      consume();
    } else if (flag === '--separator' || flag === '--separateur') {
      opts.separator = nextVal ?? '';
      consume();
    }
  }
  return opts;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node trip_expense_settlements.js --key <service-account.json> --trip <tripId> [options]

Required:
  --key <path>     Chemin vers le JSON du compte de service Firebase
  --trip <id>      ID du document voyage (trips/{tripId})

Optional:
  --include-settled       Prendre en compte les remboursements déjà enregistrés
  --separator <char>      Séparateur entre colonnes ("," ou ";") — défaut : tableau aligné
  --json                  Sortie structurée JSON

Exemples:
  node trip_expense_settlements.js --key ./preview-key.json --trip abc123
  node trip_expense_settlements.js --key ./preview-key.json --trip abc123 --separator ";"
  node trip_expense_settlements.js --key ./preview-key.json --trip abc123 --include-settled --json
`);
  process.exit(1);
}

function settledTransferFromDoc(doc) {
  const data = doc.data() || {};
  const amountRaw = data.amount;
  const amount =
    typeof amountRaw === 'number' && Number.isFinite(amountRaw)
      ? amountRaw
      : 0;
  return {
    id: doc.id,
    groupId: String(data.groupId || '').trim(),
    fromUserId: String(data.fromUserId || '').trim(),
    toUserId: String(data.toUserId || '').trim(),
    amount,
    currency: String(data.currency || 'EUR')
      .trim()
      .toUpperCase(),
  };
}

function expenseGroupFromDoc(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    title: String(data.title || '').trim(),
    isDefault: data.isDefault === true,
  };
}

function formatAmount(amount, currency) {
  return `${roundMoney(amount).toFixed(2)} ${currency}`;
}

const TRANSFER_TABLE_GAP = 3;

/** @param {{ fromName: string }[]} transfers */
function sortTransfersByPayerName(transfers) {
  return [...transfers].sort((a, b) =>
    a.fromName.localeCompare(b.fromName, 'fr', { sensitivity: 'base' }),
  );
}

function formatTransferTableLines(transfers, indent = '    ') {
  if (transfers.length === 0) return [];

  const headerPayer = 'Payeur';
  const headerAmount = 'Montant';
  const headerReceiver = 'Receveur';

  const rows = transfers.map((t) => ({
    payer: t.fromName,
    amount: formatAmount(t.amount, t.currency),
    receiver: t.toName,
  }));

  const payerWidth = Math.max(
    headerPayer.length,
    ...rows.map((r) => r.payer.length),
  );
  const amountWidth = Math.max(
    headerAmount.length,
    ...rows.map((r) => r.amount.length),
  );
  const receiverWidth = Math.max(
    headerReceiver.length,
    ...rows.map((r) => r.receiver.length),
  );

  const sep =
    indent +
    '-'.repeat(payerWidth + amountWidth + receiverWidth + 2 * TRANSFER_TABLE_GAP);

  const line = (payer, amount, receiver) =>
    indent +
    payer.padEnd(payerWidth) +
    ' '.repeat(TRANSFER_TABLE_GAP) +
    amount.padStart(amountWidth) +
    ' '.repeat(TRANSFER_TABLE_GAP) +
    receiver.padEnd(receiverWidth);

  return [
    line(headerPayer, headerAmount, headerReceiver),
    sep,
    ...rows.map((r) => line(r.payer, r.amount, r.receiver)),
  ];
}

/** @param {string} value @param {string} separator */
function escapeDelimitedField(value, separator) {
  const text = String(value);
  if (
    text.includes(separator) ||
    text.includes('"') ||
    text.includes('\n') ||
    text.includes('\r')
  ) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

/**
 * @param {{ fromName: string, toName: string, amount: number, currency: string }[]} transfers
 * @param {string} separator
 * @param {string} indent
 * @returns {string[]}
 */
function formatTransferDelimitedLines(transfers, separator, indent = '') {
  if (transfers.length === 0) return [];

  const joinRow = (payer, amount, receiver) =>
    [payer, amount, receiver]
      .map((cell) => escapeDelimitedField(cell, separator))
      .join(separator);

  const header = joinRow('Payeur', 'Montant', 'Receveur');
  const dataLines = transfers.map((t) =>
    joinRow(t.fromName, formatAmount(t.amount, t.currency), t.toName),
  );
  return [indent + header, ...dataLines.map((line) => indent + line)];
}

/**
 * @param {{ fromName: string, toName: string, amount: number, currency: string }[]} transfers
 * @param {string} indent
 * @param {string|null} separator
 * @returns {string[]}
 */
function formatTransferOutputLines(transfers, indent, separator) {
  const sep =
    separator != null && String(separator).length > 0 ? String(separator) : null;
  if (sep == null) {
    return formatTransferTableLines(transfers, indent);
  }
  return formatTransferDelimitedLines(transfers, sep, indent);
}

function balanceLabel(value) {
  const v = roundMoney(value);
  if (Math.abs(v) <= BALANCE_EPSILON) return 'équilibré';
  if (v > 0) return `créditeur +${v.toFixed(2)}`;
  return `débiteur ${v.toFixed(2)}`;
}

/**
 * Libellés publics du voyage (trips/{tripId}.memberPublicLabels).
 * Clés = memberIds (UID Firebase ou ph_xxx), comme paidBy / participantIds en prod.
 *
 * @param {Record<string, unknown>} tripData
 * @returns {Record<string, string>}
 */
function memberPublicLabelsFromTripData(tripData) {
  const raw = tripData.memberPublicLabels;
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return {};
  }
  /** @type {Record<string, string>} */
  const labels = {};
  for (const [key, value] of Object.entries(raw)) {
    const memberId = String(key).trim();
    if (!memberId) continue;
    const name = String(value ?? '').trim();
    if (name) labels[memberId] = name;
  }
  return labels;
}

const PLACEHOLDER_MEMBER_PREFIX = 'ph_';
const FIRESTORE_WHERE_IN_LIMIT = 30;

/** @param {string} email */
function displayLabelFromEmail(email) {
  const e = String(email || '').trim();
  if (!e) return '';
  const at = e.indexOf('@');
  if (at <= 0) return e;
  return e.substring(0, at).trim();
}

/** @param {string} phoneNumber */
function displayLabelFromPhoneNumber(phoneNumber) {
  const raw = String(phoneNumber || '').trim();
  if (!raw) return '';
  const digits = raw.replace(/\D/g, '');
  if (!digits) return '';
  if (digits.length < 2) return raw;
  const lastTwo = digits.slice(-2);
  const ccMatch = raw.match(/^\+\d+/);
  const prefix = ccMatch ? `${ccMatch[0]} ` : '';
  return `${prefix}•• •• •• ${lastTwo}`;
}

/**
 * @param {Record<string, unknown>|undefined} data users/{uid} document
 * @returns {string}
 */
function displayLabelFromUserDoc(data) {
  if (!data || typeof data !== 'object') return '';
  const account =
    data.account != null && typeof data.account === 'object' && !Array.isArray(data.account)
      ? /** @type {Record<string, unknown>} */ (data.account)
      : {};

  const accountName = String(account.name ?? '').trim();
  if (accountName) return accountName;

  const email = String(account.email ?? data.email ?? '').trim();
  const fromEmail = displayLabelFromEmail(email);
  if (fromEmail) return fromEmail;

  const phoneParts = [
    String(account.phoneCountryCode ?? '').trim(),
    String(account.phoneNumber ?? '').trim(),
  ].filter((p) => p.length > 0);
  const accountPhone = phoneParts.join(' ');
  if (accountPhone) {
    const fromPhone = displayLabelFromPhoneNumber(accountPhone);
    if (fromPhone) return fromPhone;
  }

  const rootPhone = String(data.phoneNumber ?? '').trim();
  if (rootPhone) {
    const fromRoot = displayLabelFromPhoneNumber(rootPhone);
    if (fromRoot) return fromRoot;
  }

  return '';
}

/**
 * @param {import('firebase-admin').firestore.Firestore} db
 * @param {string[]} userIds Firebase Auth UIDs (hors ph_)
 * @returns {Promise<Record<string, string>>}
 */
async function fetchUserLabelsByIds(db, userIds) {
  const unique = [
    ...new Set(
      userIds.map((id) => String(id || '').trim()).filter((id) => id.length > 0),
    ),
  ];
  /** @type {Record<string, string>} */
  const labels = {};
  if (unique.length === 0) return labels;

  for (let i = 0; i < unique.length; i += FIRESTORE_WHERE_IN_LIMIT) {
    const chunk = unique.slice(i, i + FIRESTORE_WHERE_IN_LIMIT);
    const snap = await db
      .collection('users')
      .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
      .get();
    for (const doc of snap.docs) {
      const label = displayLabelFromUserDoc(doc.data());
      if (label) labels[doc.id] = label;
    }
  }
  return labels;
}

/**
 * @param {{ id: string }} mainGroup
 * @param {ReturnType<typeof tripExpenseFromDoc>[]} allExpenses
 * @param {ReturnType<typeof settledTransferFromDoc>[]} allSettled
 * @param {boolean} includeSettled
 */
function collectMemberIdsForMainGroup(
  mainGroup,
  allExpenses,
  allSettled,
  includeSettled,
) {
  const ids = new Set();
  for (const expense of allExpenses) {
    if (expense.groupId !== mainGroup.id) continue;
    const paidBy = expense.paidBy.trim();
    if (paidBy) ids.add(paidBy);
    for (const participantId of expense.participantIds) {
      const id = participantId.trim();
      if (id) ids.add(id);
    }
  }
  if (includeSettled) {
    for (const transfer of allSettled) {
      if (transfer.groupId !== mainGroup.id) continue;
      const from = transfer.fromUserId.trim();
      const to = transfer.toUserId.trim();
      if (from) ids.add(from);
      if (to) ids.add(to);
    }
  }
  return [...ids];
}

/**
 * @param {Record<string, string>} memberPublicLabels
 * @param {Record<string, string>} userLabelsById
 */
function createNameResolver(memberPublicLabels, userLabelsById) {
  return (memberId) => {
    const id = String(memberId || '').trim();
    if (!id) return '(inconnu)';
    const fromPublic = memberPublicLabels[id];
    if (fromPublic) return fromPublic;
    const fromUser = userLabelsById[id];
    if (fromUser) return fromUser;
    return id;
  };
}

function buildReportForGroup({
  group,
  allExpenses,
  allSettled,
  nameFor,
  includeSettled,
}) {

  const groupExpenses = allExpenses.filter((e) => e.groupId === group.id);
  const groupSettled = includeSettled
    ? allSettled
        .filter((t) => t.groupId === group.id)
        .map((t) => ({
          fromUserId: t.fromUserId,
          toUserId: t.toUserId,
          amount: t.amount,
          currency: t.currency,
        }))
    : [];

  const settlement = computeSettlement(groupExpenses, groupSettled);

  const balancesReadable = {};
  for (const [currency, byMember] of Object.entries(
    settlement.balancesByCurrency,
  )) {
    balancesReadable[currency] = {};
    for (const [memberId, value] of Object.entries(byMember)) {
      if (Math.abs(roundMoney(value)) <= BALANCE_EPSILON) continue;
      balancesReadable[currency][memberId] = {
        memberId,
        name: nameFor(memberId),
        net: roundMoney(value),
        status: value > 0 ? 'creditor' : 'debtor',
      };
    }
  }

  const suggestedTransfers = settlement.suggestedTransfers.map((t) => ({
    fromMemberId: t.fromUserId,
    fromName: nameFor(t.fromUserId),
    toMemberId: t.toUserId,
    toName: nameFor(t.toUserId),
    amount: roundMoney(t.amount),
    currency: t.currency,
    summary: `${nameFor(t.fromUserId)} doit ${formatAmount(t.amount, t.currency)} à ${nameFor(t.toUserId)}`,
  }));

  const settledTransfersApplied = includeSettled
    ? allSettled
        .filter((t) => t.groupId === group.id)
        .map((t) => ({
          id: t.id,
          fromMemberId: t.fromUserId,
          fromName: nameFor(t.fromUserId),
          toMemberId: t.toUserId,
          toName: nameFor(t.toUserId),
          amount: roundMoney(t.amount),
          currency: t.currency,
        }))
    : [];

  return {
    groupId: group.id,
    title: group.title || group.id,
    isDefault: true,
    expenseCount: groupExpenses.length,
    settledTransferCount: settledTransfersApplied.length,
    balancesByCurrency: balancesReadable,
    suggestedTransfers: sortTransfersByPayerName(suggestedTransfers),
    settledTransfersApplied: sortTransfersByPayerName(settledTransfersApplied),
  };
}

async function main() {
  const opts = parseArgs(process.argv);
  if (!opts.keyPath || !opts.tripId) {
    printUsageAndExit();
  }

  const keyAbs = path.resolve(opts.keyPath);
  if (!fs.existsSync(keyAbs)) {
    console.error(`Clé introuvable : ${keyAbs}`);
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(keyAbs, 'utf8'));
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const db = admin.firestore();
  const tripRef = db.collection('trips').doc(opts.tripId);
  const tripSnap = await tripRef.get();
  if (!tripSnap.exists) {
    console.error(`Voyage introuvable : trips/${opts.tripId}`);
    process.exit(1);
  }

  const tripData = tripSnap.data() || {};
  const tripTitle =
    String(tripData.title || tripData.name || '').trim() || opts.tripId;

  const [groupsSnap, expensesSnap, settledSnap] = await Promise.all([
    tripRef.collection('expenseGroups').get(),
    tripRef.collection('expenses').get(),
    tripRef.collection('expenseSettledTransfers').get(),
  ]);

  const memberPublicLabels = memberPublicLabelsFromTripData(tripData);

  const allGroups = groupsSnap.docs.map(expenseGroupFromDoc);
  const mainGroups = allGroups.filter((g) => g.isDefault);
  if (mainGroups.length === 0) {
    console.error(
      `Aucun poste principal (isDefault) sur trips/${opts.tripId}.`,
    );
    process.exit(1);
  }
  if (mainGroups.length > 1) {
    console.error(
      `Plusieurs postes principaux (isDefault) sur trips/${opts.tripId} : ${mainGroups.map((g) => g.id).join(', ')}`,
    );
    process.exit(1);
  }

  const mainGroup = mainGroups[0];
  const allExpenses = expensesSnap.docs.map(tripExpenseFromDoc);
  const allSettled = settledSnap.docs.map(settledTransferFromDoc);

  const memberIdsInScope = collectMemberIdsForMainGroup(
    mainGroup,
    allExpenses,
    allSettled,
    opts.includeSettled,
  );
  const userIdsToFetch = memberIdsInScope.filter(
    (id) =>
      !id.startsWith(PLACEHOLDER_MEMBER_PREFIX) && !memberPublicLabels[id],
  );
  const userLabelsById = await fetchUserLabelsByIds(db, userIdsToFetch);
  const nameFor = createNameResolver(memberPublicLabels, userLabelsById);

  const mainPost = buildReportForGroup({
    group: mainGroup,
    allExpenses,
    allSettled,
    nameFor,
    includeSettled: opts.includeSettled,
  });

  const payload = {
    tripId: opts.tripId,
    tripTitle,
    projectId: serviceAccount.project_id,
    includeSettled: opts.includeSettled,
    memberPublicLabelsCount: Object.keys(memberPublicLabels).length,
    userLabelsResolvedCount: Object.keys(userLabelsById).length,
    mainPost,
  };

  if (opts.json) {
    console.log(JSON.stringify(payload, null, 2));
    process.exit(0);
  }

  const g = mainPost;
  console.log(`Voyage : ${tripTitle} (${opts.tripId})`);
  console.log(`Projet : ${serviceAccount.project_id}`);
  console.log(
    opts.includeSettled
      ? 'Remboursements enregistrés : pris en compte'
      : 'Remboursements enregistrés : ignorés',
  );
  console.log(
    `Libellés : memberPublicLabels (${Object.keys(memberPublicLabels).length}), users (${Object.keys(userLabelsById).length} résolu(s))`,
  );
  console.log('');
  console.log(`Poste principal : ${g.title}`);
  console.log(`  Dépenses : ${g.expenseCount}`);
  if (opts.includeSettled) {
    console.log(
      `  Remboursements déjà enregistrés : ${g.settledTransferCount}`,
    );
  }

  const currencies = Object.keys(g.balancesByCurrency).sort();
  if (currencies.length === 0) {
    console.log('  Soldes : (aucune dépense)');
  } else {
    console.log('  Soldes nets (positif = les autres lui doivent) :');
    for (const currency of currencies) {
      const entries = Object.values(g.balancesByCurrency[currency]);
      if (entries.length === 0) {
        console.log(`    ${currency} : équilibré`);
        continue;
      }
      console.log(`    ${currency} :`);
      for (const row of entries) {
        console.log(`      ${row.name} — ${balanceLabel(row.net)}`);
      }
    }
  }

  if (g.suggestedTransfers.length === 0) {
    console.log('  Remboursements suggérés : aucun (comptes équilibrés)');
  } else {
    console.log('  Remboursements suggérés :');
    for (const line of formatTransferOutputLines(
      g.suggestedTransfers,
      '    ',
      opts.separator,
    )) {
      console.log(line);
    }
  }

  if (opts.includeSettled && g.settledTransfersApplied.length > 0) {
    console.log('');
    console.log('  Remboursements déjà enregistrés :');
    for (const line of formatTransferOutputLines(
      g.settledTransfersApplied,
      '    ',
      opts.separator,
    )) {
      console.log(line);
    }
  }

  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
