'use strict';

/**
 * cleanup_fcm_tokens_missing_platform.js
 *
 * Supprime les documents fcmTokens obsolètes :
 *   - tokens sans champ `platform` (enregistrés avant l'introduction du champ,
 *     non achemineables correctement vers le format web data-only ou natif)
 *   - tokens avec `platform === 'android'` (décommissionnement de l'app Android)
 *     → activé uniquement avec --include-android (désactivé par défaut)
 *
 * Après suppression, les clients actifs re-enregistrent leur token au prochain
 * démarrage avec le champ `platform` correct.
 *
 * Usage (depuis le dossier scripts/) :
 *   node cleanup_fcm_tokens_missing_platform.js --key <service-account.json> [options]
 *
 * Options :
 *   --key <path>         Compte de service Firebase (obligatoire)
 *   --apply              Suppression réelle (par défaut : dry-run)
 *   --dry-run            Aperçu sans écriture (défaut)
 *   --include-android    Inclure aussi les tokens android (décommissionnement)
 *   --verbose            Lister chaque token concerné
 *
 * Exemples :
 *   node cleanup_fcm_tokens_missing_platform.js --key ./planerz-PREVIEW.json
 *   node cleanup_fcm_tokens_missing_platform.js --key ./planerz-PROD.json --apply
 *   node cleanup_fcm_tokens_missing_platform.js --key ./planerz-PROD.json --include-android
 *   node cleanup_fcm_tokens_missing_platform.js --key ./planerz-PROD.json --include-android --apply
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

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { keyPath: null, apply: false, includeAndroid: false, verbose: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--key' && args[i + 1]) { opts.keyPath = args[++i]; }
    else if (args[i] === '--apply') { opts.apply = true; }
    else if (args[i] === '--dry-run') { opts.apply = false; }
    else if (args[i] === '--include-android') { opts.includeAndroid = true; }
    else if (args[i] === '--verbose') { opts.verbose = true; }
  }
  return opts;
}

async function run() {
  const opts = parseArgs();

  if (!opts.keyPath) {
    console.error('Usage: node cleanup_fcm_tokens_missing_platform.js --key <service-account.json> [--apply] [--verbose]');
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(path.resolve(opts.keyPath), 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  console.log(`Mode : ${opts.apply ? 'APPLY (suppression réelle)' : 'DRY-RUN (aucune écriture)'}`);
  console.log(`Cibles : tokens sans platform${opts.includeAndroid ? ' + tokens android' : ''}\n`);

  const usersSnap = await db.collection('users').get();
  let totalScanned = 0;
  let totalMissing = 0;
  let totalAndroid = 0;
  let totalDeleted = 0;
  const BATCH_SIZE = 400;
  let batch = db.batch();
  let batchOps = 0;

  async function commitBatch() {
    if (batchOps === 0) return;
    if (opts.apply) await batch.commit();
    totalDeleted += batchOps;
    batch = db.batch();
    batchOps = 0;
  }

  for (const userDoc of usersSnap.docs) {
    const tokensSnap = await db
      .collection('users')
      .doc(userDoc.id)
      .collection('fcmTokens')
      .get();

    for (const tokenDoc of tokensSnap.docs) {
      totalScanned++;
      const data = tokenDoc.data() || {};
      const platform = typeof data.platform === 'string' ? data.platform.trim() : '';

      const isMissingPlatform = !platform;
      const isAndroid = opts.includeAndroid && platform === 'android';
      if (!isMissingPlatform && !isAndroid) continue;

      if (isMissingPlatform) totalMissing++;
      if (isAndroid) totalAndroid++;

      if (opts.verbose) {
        const reason = isMissingPlatform ? 'sans platform' : 'android';
        console.log(`  [${reason}] users/${userDoc.id}/fcmTokens/${tokenDoc.id}  token=${String(data.token || '').slice(0, 20)}...`);
      }

      if (opts.apply) {
        batch.delete(tokenDoc.ref);
        batchOps++;
        if (batchOps >= BATCH_SIZE) await commitBatch();
      }
    }
  }

  await commitBatch();

  console.log(`\nTokens analysés    : ${totalScanned}`);
  console.log(`  sans platform    : ${totalMissing}`);
  if (opts.includeAndroid) console.log(`  android          : ${totalAndroid}`);
  console.log(`  total à purger   : ${totalMissing + (opts.includeAndroid ? totalAndroid : 0)}`);
  if (opts.apply) {
    console.log(`Tokens supprimés   : ${totalDeleted}`);
    console.log('\nDone. Les clients actifs re-enregistreront leur token au prochain démarrage.');
  } else {
    console.log('\n(Dry-run — relancer avec --apply pour supprimer)');
  }
}

run().catch((e) => { console.error(e); process.exit(1); });
