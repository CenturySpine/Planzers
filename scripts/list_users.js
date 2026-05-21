'use strict';

/**
 * list_users.js
 *
 * Lecture seule : liste tous les documents de la collection `users` avec,
 * pour chaque UID, le nom (account.name) puis le numéro de téléphone
 * (account.phoneCountryCode + account.phoneNumber) par ordre de priorité.
 *
 * Usage :
 *   node list_users.js --key <service-account.json> [options]
 *
 * Options :
 *   --key <path>        Compte de service Firebase (obligatoire)
 *   --sort uid|name     Ordre de tri : par UID ou par nom (défaut : name)
 *   --separator <char>  Séparateur entre colonnes ("," ou ";") — défaut : tableau aligné
 *   --json              Sortie JSON (sinon texte lisible)
 */

const fs   = require('fs');
const path = require('path');

function loadFirebaseAdmin() {
  try {
    return require('firebase-admin');
  } catch {
    return require(path.join(__dirname, 'migration', 'node_modules', 'firebase-admin'));
  }
}

const admin = loadFirebaseAdmin();

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = { keyPath: '', json: false, separator: null, sort: 'name' };
  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (token === '--json') { opts.json = true; continue; }
    if (!token.startsWith('--')) continue;
    const eqIdx   = token.indexOf('=');
    const flag    = eqIdx >= 0 ? token.slice(0, eqIdx) : token;
    const inlineVal = eqIdx >= 0 ? token.slice(eqIdx + 1) : null;
    const nextVal = inlineVal ?? argv[i + 1];
    const consume = () => { if (inlineVal === null) i++; };
    if (flag === '--key') {
      opts.keyPath = (nextVal || '').trim();
      consume();
    } else if (flag === '--separator') {
      opts.separator = nextVal ?? '';
      consume();
    } else if (flag === '--sort') {
      opts.sort = (nextVal || 'name').trim().toLowerCase();
      consume();
    }
  }
  return opts;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node list_users.js --key <service-account.json> [options]

Required:
  --key <path>        Chemin vers le JSON du compte de service Firebase

Optional:
  --sort uid|name     Tri par UID ou par nom alphabétique (défaut : name)
  --separator <char>  Séparateur entre colonnes ("," ou ";") — défaut : tableau aligné
  --json              Sortie JSON structurée

Exemples:
  node list_users.js --key ./planerz-PROD.json
  node list_users.js --key ./planerz-PROD.json --sort uid
  node list_users.js --key ./planerz-PROD.json --separator ";"
  node list_users.js --key ./planerz-PROD.json --json
`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Extrait le nom d'affichage et le numéro de téléphone depuis un doc users/{uid}.
 * Priorité nom : account.name → account.email → (vide)
 * Téléphone    : account.phoneCountryCode + account.phoneNumber
 */
function extractUser(uid, data) {
  const account =
    data && typeof data.account === 'object' && !Array.isArray(data.account)
      ? data.account
      : {};

  const name  = String(account.name  ?? '').trim();
  const email = String(account.email ?? data?.email ?? '').trim();

  const ccRaw    = String(account.phoneCountryCode ?? '').trim();
  const numRaw   = String(account.phoneNumber      ?? '').trim();
  const phone    = [ccRaw, numRaw].filter(Boolean).join(' ');

  return { uid, name, email, phone };
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

function buildRows(users) {
  return users.map(({ uid, name, email, phone }) => {
    const label = name || email || '(sans nom)';
    return { uid, label, phone: phone || '(sans téléphone)' };
  });
}

function printTable(rows) {
  if (rows.length === 0) { console.log('Aucun utilisateur trouvé.'); return; }

  const w0 = Math.max(...rows.map((r) => r.uid.length),   3);
  const w1 = Math.max(...rows.map((r) => r.label.length), 3);
  const w2 = Math.max(...rows.map((r) => r.phone.length), 9);

  const sep  = '-';
  const line = `+-${sep.repeat(w0)}-+-${sep.repeat(w1)}-+-${sep.repeat(w2)}-+`;
  const row  = (uid, label, phone) =>
    `| ${uid.padEnd(w0)} | ${label.padEnd(w1)} | ${phone.padEnd(w2)} |`;

  console.log(line);
  console.log(row('UID', 'Nom', 'Téléphone'));
  console.log(line);
  for (const r of rows) console.log(row(r.uid, r.label, r.phone));
  console.log(line);
  console.log(`\n${rows.length} utilisateur(s).`);
}

function printSeparated(rows, sep) {
  console.log(`uid${sep}nom${sep}telephone`);
  for (const r of rows) {
    const label = r.label === '(sans nom)'       ? '' : r.label;
    const phone = r.phone === '(sans téléphone)' ? '' : r.phone;
    console.log(`${r.uid}${sep}${label}${sep}${phone}`);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const opts = parseArgs(process.argv);

  if (!opts.keyPath) { console.error('Erreur : --key requis.'); printUsageAndExit(); }
  if (!fs.existsSync(opts.keyPath)) {
    console.error(`Erreur : fichier introuvable : ${opts.keyPath}`);
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(opts.keyPath, 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  console.error('Chargement des utilisateurs…');
  const snapshot = await db.collection('users').get();
  console.error(`${snapshot.size} document(s) trouvé(s).`);

  if (opts.sort !== 'uid' && opts.sort !== 'name') {
    console.error(`Erreur : --sort doit être "uid" ou "name" (reçu : "${opts.sort}").`);
    process.exit(1);
  }

  const users = snapshot.docs
    .map((doc) => extractUser(doc.id, doc.data()))
    .sort((a, b) => {
      if (opts.sort === 'uid') return a.uid.localeCompare(b.uid, 'fr');
      const la = (a.name || a.email || a.uid).toLowerCase();
      const lb = (b.name || b.email || b.uid).toLowerCase();
      return la.localeCompare(lb, 'fr');
    });

  if (opts.json) {
    console.log(JSON.stringify(users, null, 2));
    return;
  }

  const rows = buildRows(users);

  if (opts.separator !== null) {
    printSeparated(rows, opts.separator);
  } else {
    printTable(rows);
  }
}

main().catch((err) => {
  console.error('Erreur fatale :', err.message ?? err);
  process.exit(1);
});
