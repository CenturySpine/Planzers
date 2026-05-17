const admin = require('firebase-admin');
const fs = require('fs');
const https = require('https');
const path = require('path');

const PLACEHOLDER_USER_ID_PREFIX = 'ph_';
const DELETE_BATCH_SIZE = 500;
const LIST_USERS_PAGE_SIZE = 300;

/** Sous-collections connues sous users/{uid} (secours si l'API REST échoue). */
const KNOWN_USER_SUBCOLLECTIONS = [
  'aiQuotas',
  'fcmTokens',
  'tripNotificationCounters',
  'tripNotificationPresence',
  'cupidonMatches',
  'globalNotificationReads',
  'dismissedAdminAnnouncements',
];

function parseCliArguments(argv) {
  const parsed = {
    keyPath: '',
    apply: false,
    dryRun: true,
    limit: 0,
    verbose: false,
  };

  for (let index = 2; index < argv.length; index++) {
    const token = argv[index];
    if (token === '--apply') {
      parsed.apply = true;
      parsed.dryRun = false;
      continue;
    }
    if (token === '--dry-run') {
      parsed.dryRun = true;
      parsed.apply = false;
      continue;
    }
    if (token === '--verbose') {
      parsed.verbose = true;
      continue;
    }
    if (!token.startsWith('--')) {
      continue;
    }

    const [flag, inlineValue] = token.split('=');
    const nextValue = inlineValue ?? argv[index + 1];
    const hasInlineValue = inlineValue !== undefined;

    const consumeNext = () => {
      if (!hasInlineValue) {
        index += 1;
      }
    };

    if (flag === '--key') {
      parsed.keyPath = (nextValue || '').trim();
      consumeNext();
      continue;
    }
    if (flag === '--limit') {
      const parsedValue = Number.parseInt((nextValue || '').trim(), 10);
      parsed.limit = Number.isFinite(parsedValue) && parsedValue > 0
        ? parsedValue
        : 0;
      consumeNext();
    }
  }

  return parsed;
}

function printUsageAndExit() {
  console.log(`
Usage:
  node delete_ph_users.js --key <service-account.json> [options]

Required:
  --key <path>           Chemin vers le JSON du compte de service Firebase

Optional:
  --apply                Supprime réellement (par défaut : dry-run)
  --dry-run              Aperçu sans écriture (par défaut)
  --limit <n>            Traiter au plus n utilisateurs ph_*
  --verbose              Lister chaque document imbriqué dans l'arbre users/{ph_*}

Détection : l'API REST Firestore avec showMissing=true (comme la console Firebase)
pour inclure les users/ph_* sans champs mais avec des sous-collections.

Examples:
  node delete_ph_users.js --key ./preview-key.json --verbose
  node delete_ph_users.js --key ./preview-key.json --limit 5
  node delete_ph_users.js --key ./preview-key.json --apply
`);
  process.exit(1);
}

function loadServiceAccountJson(keyPath) {
  const resolvedPath = path.resolve(process.cwd(), keyPath);
  const rawJson = fs.readFileSync(resolvedPath, 'utf8');
  return JSON.parse(rawJson);
}

function extractUserIdFromFirestoreDocumentName(documentName) {
  const marker = '/documents/users/';
  const markerIndex = documentName.indexOf(marker);
  if (markerIndex < 0) {
    return '';
  }
  const remainder = documentName.slice(markerIndex + marker.length);
  const slashIndex = remainder.indexOf('/');
  return slashIndex < 0 ? remainder : remainder.slice(0, slashIndex);
}

function httpsGetJson(url, accessToken) {
  return new Promise((resolve, reject) => {
    const request = https.get(
      url,
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      },
      (response) => {
        let body = '';
        response.on('data', (chunk) => {
          body += chunk;
        });
        response.on('end', () => {
          try {
            const parsed = JSON.parse(body);
            if (response.statusCode >= 400) {
              reject(
                new Error(
                  parsed.error?.message
                    ?? `HTTP ${response.statusCode} sur ${url}`
                )
              );
              return;
            }
            resolve(parsed);
          } catch (error) {
            reject(error);
          }
        });
      }
    );
    request.on('error', reject);
  });
}

async function discoverPlaceholderUserIdsViaRest(projectId, accessToken) {
  const userIds = new Set();
  let pageToken = '';

  do {
    const url = new URL(
      `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/databases/(default)/documents/users`
    );
    url.searchParams.set('pageSize', String(LIST_USERS_PAGE_SIZE));
    url.searchParams.set('showMissing', 'true');
    if (pageToken) {
      url.searchParams.set('pageToken', pageToken);
    }

    const response = await httpsGetJson(url.toString(), accessToken);
    const documents = Array.isArray(response.documents) ? response.documents : [];

    for (const document of documents) {
      const documentName = typeof document.name === 'string' ? document.name : '';
      const userId = extractUserIdFromFirestoreDocumentName(documentName);
      if (userId.startsWith(PLACEHOLDER_USER_ID_PREFIX)) {
        userIds.add(userId);
      }
    }

    pageToken = typeof response.nextPageToken === 'string'
      ? response.nextPageToken
      : '';
  } while (pageToken);

  return [...userIds].sort();
}

async function forEachCollectionGroupDocument(firestore, collectionId, visitor) {
  let lastDocument = null;

  while (true) {
    let query = firestore
      .collectionGroup(collectionId)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(DELETE_BATCH_SIZE);
    if (lastDocument) {
      query = query.startAfter(lastDocument);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      return;
    }

    for (const document of snapshot.docs) {
      await visitor(document);
      lastDocument = document;
    }

    if (snapshot.size < DELETE_BATCH_SIZE) {
      return;
    }
  }
}

function extractUserIdFromSubdocumentPath(documentPath) {
  const parts = documentPath.split('/');
  if (parts.length < 2 || parts[0] !== 'users') {
    return '';
  }
  return parts[1];
}

async function discoverPlaceholderUserIdsViaCollectionGroups(firestore) {
  const userIds = new Set();

  for (const subcollectionId of KNOWN_USER_SUBCOLLECTIONS) {
    await forEachCollectionGroupDocument(firestore, subcollectionId, (document) => {
      const userId = extractUserIdFromSubdocumentPath(document.ref.path);
      if (userId.startsWith(PLACEHOLDER_USER_ID_PREFIX)) {
        userIds.add(userId);
      }
    });
  }

  return [...userIds].sort();
}

async function discoverPlaceholderUserIds(firestore, projectId, serviceAccount) {
  try {
    const credential = admin.credential.cert(serviceAccount);
    const accessTokenResponse = await credential.getAccessToken();
    const accessToken = accessTokenResponse.access_token;
    if (!accessToken) {
      throw new Error('Jeton d accès indisponible');
    }

    const userIds = await discoverPlaceholderUserIdsViaRest(projectId, accessToken);
    console.log(
      `Détection REST (showMissing=true) : ${userIds.length} utilisateur(s) ${PLACEHOLDER_USER_ID_PREFIX}*`
    );
    return userIds;
  } catch (restError) {
    console.warn(
      `Détection REST indisponible (${restError.message}) -> repli collectionGroup`
    );
    const userIds = await discoverPlaceholderUserIdsViaCollectionGroups(firestore);
    console.log(
      `Détection collectionGroup : ${userIds.length} utilisateur(s) ${PLACEHOLDER_USER_ID_PREFIX}*`
    );
    return userIds;
  }
}

async function forEachDocumentInCollection(collectionRef, visitor) {
  let lastDocument = null;

  while (true) {
    let query = collectionRef.orderBy(admin.firestore.FieldPath.documentId()).limit(
      DELETE_BATCH_SIZE
    );
    if (lastDocument) {
      query = query.startAfter(lastDocument);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      return;
    }

    for (const document of snapshot.docs) {
      await visitor(document);
      lastDocument = document;
    }

    if (snapshot.size < DELETE_BATCH_SIZE) {
      return;
    }
  }
}

async function userRootDocumentExists(documentRef) {
  const snapshot = await documentRef.get();
  return snapshot.exists;
}

async function collectNestedDocumentPaths(documentRef) {
  const paths = [];

  const subcollections = await documentRef.listCollections();
  for (const subcollection of subcollections) {
    await forEachDocumentInCollection(subcollection, async (subDocument) => {
      const nestedPaths = await collectNestedDocumentPaths(subDocument.ref);
      paths.push(...nestedPaths);
      paths.push(subDocument.ref.path);
    });
  }

  return paths;
}

async function deleteDocumentRecursively(documentRef, rootExists) {
  let deletedCount = 0;

  const subcollections = await documentRef.listCollections();
  for (const subcollection of subcollections) {
    await forEachDocumentInCollection(subcollection, async (subDocument) => {
      deletedCount += await deleteDocumentRecursively(subDocument.ref, true);
    });
  }

  if (rootExists) {
    await documentRef.delete();
    return deletedCount + 1;
  }

  return deletedCount;
}

async function run() {
  const options = parseCliArguments(process.argv);
  if (!options.keyPath) {
    printUsageAndExit();
  }

  const serviceAccount = loadServiceAccountJson(options.keyPath);
  const app = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  const firestore = app.firestore();

  console.log(`Mode: ${options.dryRun ? 'DRY-RUN (lecture seule)' : 'APPLY (suppression en cascade)'}`);
  console.log(`Préfixe ciblé: ${PLACEHOLDER_USER_ID_PREFIX}`);

  const placeholderUserIds = await discoverPlaceholderUserIds(
    firestore,
    serviceAccount.project_id,
    serviceAccount
  );
  const userIdsToProcess = options.limit > 0
    ? placeholderUserIds.slice(0, options.limit)
    : placeholderUserIds;

  let deletedUserRoots = 0;
  let deletedNestedDocuments = 0;
  let previewUserRoots = 0;
  let previewNestedDocuments = 0;
  let previewPhantomRoots = 0;
  let errorCount = 0;

  for (const userId of userIdsToProcess) {
    const userRef = firestore.collection('users').doc(userId);
    const userPath = userRef.path;

    try {
      const rootExists = await userRootDocumentExists(userRef);
      const nestedPaths = await collectNestedDocumentPaths(userRef);
      const rootContribution = rootExists ? 1 : 0;
      const totalDocumentsForUser = nestedPaths.length + rootContribution;

      if (options.dryRun) {
        if (rootExists) {
          previewUserRoots += 1;
        } else {
          previewPhantomRoots += 1;
        }
        previewNestedDocuments += nestedPaths.length;
        const rootLabel = rootExists ? 'racine + sous-arbre' : 'sous-arbre seulement (doc racine absent)';
        console.log(
          `DRY  ${userPath} -> ${totalDocumentsForUser} document(s) (${rootLabel}, ${nestedPaths.length} imbriqué(s))`
        );
        if (options.verbose) {
          for (const nestedPath of nestedPaths.sort()) {
            console.log(`       - ${nestedPath}`);
          }
        }
        continue;
      }

      const deletedForUser = await deleteDocumentRecursively(userRef, rootExists);
      if (rootExists) {
        deletedUserRoots += 1;
      }
      deletedNestedDocuments += deletedForUser - (rootExists ? 1 : 0);
      console.log(
        `DONE ${userPath} -> ${deletedForUser} document(s) supprimé(s) en cascade`
      );
      if (options.verbose && nestedPaths.length > 0) {
        for (const nestedPath of nestedPaths.sort()) {
          console.log(`       - ${nestedPath}`);
        }
      }
    } catch (error) {
      errorCount += 1;
      console.error(`ERR  ${userPath} -> ${error.message}`);
    }
  }

  console.log('\n--- Résultat ---');
  console.log(`Utilisateurs ${PLACEHOLDER_USER_ID_PREFIX}* trouvés: ${placeholderUserIds.length}`);
  console.log(`Utilisateurs traités: ${userIdsToProcess.length}`);
  if (options.dryRun) {
    console.log(`Racines existantes prévisualisées: ${previewUserRoots}`);
    console.log(`Racines fantômes (italique console) prévisualisées: ${previewPhantomRoots}`);
    console.log(`Documents imbriqués prévisualisés: ${previewNestedDocuments}`);
    console.log(
      `Total documents qui seraient supprimés: ${previewUserRoots + previewPhantomRoots + previewNestedDocuments}`
    );
  } else {
    console.log(`Racines existantes supprimées: ${deletedUserRoots}`);
    console.log(`Documents imbriqués supprimés: ${deletedNestedDocuments}`);
    console.log(`Total documents supprimés: ${deletedUserRoots + deletedNestedDocuments}`);
  }
  console.log(`Erreurs: ${errorCount}`);

  await app.delete();
}

run().catch((error) => {
  console.error('Erreur fatale:', error);
  process.exit(1);
});
