'use strict';

/**
 * ensure_default_expense_group.js
 *
 * Détecte les voyages sans poste de dépense par défaut (isDefault) et propose
 * de créer le poste « Commun » (même schéma que à la création d'un voyage).
 *
 * Usage :
 *   node ensure_default_expense_group.js --key <service-account.json> [options]
 *
 * Options :
 *   --apply          Écriture réelle (par défaut : dry-run)
 *   --dry-run        Aperçu sans écriture (défaut)
 *   --verbose        Détail par voyage
 *   --trip <tripId>  Limiter au voyage indiqué
 *   --all            Traiter tous les voyages listés (confirmation globale)
 *
 * Exemples :
 *   node ensure_default_expense_group.js --key ./planerz-PROD.json
 *   node ensure_default_expense_group.js --key ./planerz-PROD.json --trip abc123 --verbose
 *   node ensure_default_expense_group.js --key ./planerz-PROD.json --all --apply
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch {
    return require(path.join(__dirname, 'migration', 'node_modules', 'firebase-admin'));
  }
}

const admin = loadFirebaseAdmin();

const DEFAULT_TITLE = 'Commun';

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = {
    keyPath: '',
    apply: false,
    dryRun: true,
    verbose: false,
    tripId: '',
    all: false,
  };
  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (token === '--apply') {
      opts.apply = true;
      opts.dryRun = false;
      continue;
    }
    if (token === '--dry-run') {
      opts.dryRun = true;
      opts.apply = false;
      continue;
    }
    if (token === '--verbose') {
      opts.verbose = true;
      continue;
    }
    if (token === '--all') {
      opts.all = true;
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
    }
  }
  return opts;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node ensure_default_expense_group.js --key <service-account.json> [options]

Required:
  --key <path>    Chemin vers le JSON du compte de service Firebase

Optional:
  --apply         Écriture réelle (par défaut : dry-run)
  --dry-run       Aperçu sans écriture
  --verbose       Afficher le détail de chaque voyage analysé
  --trip <id>     Analyser un seul voyage (trips/{tripId})
  --all           Créer pour tous les voyages listés (avec confirmation)

Exemples:
  node ensure_default_expense_group.js --key ./planerz-PROD.json
  node ensure_default_expense_group.js --key ./planerz-PROD.json --trip abc123
  node ensure_default_expense_group.js --key ./planerz-PROD.json --all --apply
`);
  process.exit(1);
}

function prompt(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

// ---------------------------------------------------------------------------
// Firestore
// ---------------------------------------------------------------------------

function tripDisplayTitle(data) {
  return String(data?.title ?? '').trim() || '(sans titre)';
}

async function countDefaultGroupsForTrip(tripRef) {
  const snap = await tripRef.collection('expenseGroups').get();
  let count = 0;
  for (const doc of snap.docs) {
    if (doc.data()?.isDefault === true) count++;
  }
  return count;
}

async function loadParticipantDocIds(tripRef) {
  const snap = await tripRef.collection('participants').get();
  return snap.docs.map((d) => d.id);
}

async function discoverTripsMissingDefault(db, opts) {
  let tripDocs;
  if (opts.tripId) {
    const doc = await db.collection('trips').doc(opts.tripId).get();
    if (!doc.exists) {
      throw new Error(`Voyage introuvable : trips/${opts.tripId}`);
    }
    tripDocs = [doc];
  } else {
    const snap = await db.collection('trips').get();
    tripDocs = snap.docs;
  }

  const missing = [];
  const ambiguous = [];

  for (const tripDoc of tripDocs) {
    const tripId = tripDoc.id;
    const data = tripDoc.data() || {};
    const defaultCount = await countDefaultGroupsForTrip(tripDoc.ref);

    if (defaultCount > 1) {
      ambiguous.push({ tripId, data, defaultCount });
      continue;
    }
    if (defaultCount === 1) {
      if (opts.verbose) {
        console.log(
          `  OK  "${tripDisplayTitle(data)}" (${tripId}) — poste par défaut présent`,
        );
      }
      continue;
    }

    const ownerId = String(data.ownerId ?? '').trim();
    const participantIds = await loadParticipantDocIds(tripDoc.ref);

    missing.push({
      tripId,
      data,
      ownerId,
      participantIds,
    });
  }

  return { missing, ambiguous };
}

function buildDefaultGroupPayload(ownerId, participantIds) {
  return {
    title: DEFAULT_TITLE,
    visibleToMemberIds: participantIds,
    isDefault: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: ownerId,
  };
}

async function createDefaultGroupForTrip(db, entry, opts) {
  const { tripId, ownerId, participantIds } = entry;
  const title = tripDisplayTitle(entry.data);

  if (!ownerId) {
    throw new Error(`ownerId manquant sur trips/${tripId}`);
  }
  if (participantIds.length === 0) {
    throw new Error(
      `aucun participant sur trips/${tripId} — visibleToMemberIds serait vide`,
    );
  }

  const tripRef = db.collection('trips').doc(tripId);
  const groupRef = tripRef.collection('expenseGroups').doc();
  const payload = buildDefaultGroupPayload(ownerId, participantIds);

  if (opts.dryRun) {
    console.log(
      `  [dry-run] trips/${tripId}/expenseGroups/${groupRef.id}  title="${DEFAULT_TITLE}"  participants=${participantIds.length}  createdBy=${ownerId}`,
    );
    if (opts.verbose) {
      console.log(`            visibleToMemberIds: ${participantIds.join(', ')}`);
    }
    return { tripId, groupId: groupRef.id, dryRun: true };
  }

  await groupRef.set(payload);
  console.log(
    `  [apply]   "${title}" (${tripId}) → expenseGroups/${groupRef.id}`,
  );
  return { tripId, groupId: groupRef.id, dryRun: false };
}

function printMissingList(missing) {
  console.log(`\n${missing.length} voyage(s) sans poste par défaut :\n`);
  missing.forEach((entry, idx) => {
    const title = tripDisplayTitle(entry.data);
    const n = entry.participantIds.length;
    console.log(
      `  [${idx + 1}] ${title}  (${entry.tripId})  owner=${entry.ownerId || '?'}  participants=${n}`,
    );
  });
}

function printAmbiguousList(ambiguous) {
  if (ambiguous.length === 0) return;
  console.log(
    `\nATTENTION — ${ambiguous.length} voyage(s) avec plusieurs postes isDefault (non traités) :\n`,
  );
  ambiguous.forEach((entry) => {
    console.log(
      `  • ${tripDisplayTitle(entry.data)}  (${entry.tripId})  count=${entry.defaultCount}`,
    );
  });
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function run() {
  const opts = parseArgs(process.argv);
  if (!opts.keyPath) printUsageAndExit();

  const resolvedKey = path.resolve(process.cwd(), opts.keyPath);
  const serviceAccount = JSON.parse(fs.readFileSync(resolvedKey, 'utf8'));

  const app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  const db = app.firestore();

  console.log(
    `Mode     : ${opts.dryRun ? 'DRY-RUN (aucune écriture)' : 'APPLY (écriture Firestore)'}`,
  );
  console.log(`Projet   : ${serviceAccount.project_id}`);
  if (opts.tripId) console.log(`Filtre   : trips/${opts.tripId}`);
  console.log('');
  console.log('Scan des voyages...');

  const { missing, ambiguous } = await discoverTripsMissingDefault(db, opts);
  printAmbiguousList(ambiguous);

  if (missing.length === 0) {
    console.log('\nAucun voyage sans poste de dépense par défaut.');
    await app.delete();
    return;
  }

  printMissingList(missing);

  let toProcess = [];

  if (opts.all) {
    const confirmAll = await prompt(
      `\nCréer le poste « ${DEFAULT_TITLE} » pour les ${missing.length} voyage(s) ci-dessus ? (oui/non) : `,
    );
    if (confirmAll.toLowerCase() !== 'oui' && confirmAll.toLowerCase() !== 'o') {
      console.log('Annulé.');
      await app.delete();
      return;
    }
    toProcess = missing;
  } else {
    console.log('');
    const answer = await prompt(
      'Numéro du voyage à corriger, "tous" pour la liste entière, ou "q" pour quitter : ',
    );

    if (answer.toLowerCase() === 'q' || answer === '') {
      console.log('Annulé.');
      await app.delete();
      return;
    }

    if (answer.toLowerCase() === 'tous' || answer.toLowerCase() === 'all') {
      const confirmAll = await prompt(
        `Confirmer la création pour ${missing.length} voyage(s) ? (oui/non) : `,
      );
      if (
        confirmAll.toLowerCase() !== 'oui' &&
        confirmAll.toLowerCase() !== 'o'
      ) {
        console.log('Annulé.');
        await app.delete();
        return;
      }
      toProcess = missing;
    } else {
      const choice = parseInt(answer, 10);
      if (!Number.isFinite(choice) || choice < 1 || choice > missing.length) {
        console.error(`Choix invalide : "${answer}"`);
        await app.delete();
        process.exit(1);
      }
      toProcess = [missing[choice - 1]];
    }
  }

  if (!opts.apply && !opts.dryRun) {
    opts.dryRun = true;
  }

  if (!opts.apply) {
    console.log(
      '\nMode dry-run : aucune écriture. Relancer avec --apply pour créer les postes.',
    );
  }

  console.log('');
  let created = 0;
  let errors = 0;

  for (const entry of toProcess) {
    try {
      await createDefaultGroupForTrip(db, entry, opts);
      created++;
    } catch (err) {
      errors++;
      console.error(
        `  ERR  trips/${entry.tripId} → ${err.message}`,
      );
    }
  }

  console.log('');
  console.log('--- Résultat ---');
  if (opts.dryRun) {
    console.log(`Postes à créer (simulation) : ${created}`);
  } else {
    console.log(`Postes créés                : ${created}`);
  }
  console.log(`Erreurs                     : ${errors}`);

  await app.delete();
}

run().catch((err) => {
  console.error('Erreur fatale :', err);
  process.exit(1);
});
