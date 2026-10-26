'use strict';

/**
 * Trip transfer between environments (typically preview → prod), restricted
 * to application owners (`users/{uid}.isApplicationOwner`) while it serves
 * development: one exports any trip as a JSON file, and imports such a file
 * from the trip list as a new trip they own.
 *
 * Both sides must run exactly the same app version, so the file carries the
 * Firestore documents as they are stored, with no migration. Sub-document ids
 * are kept (they only live under the new trip), so links between records
 * (participants, activities, expense posts…) stay valid as they are.
 *
 * Accounts do not carry over between Firebase projects. The file holds no
 * account id: the exporter is replaced by a placeholder and every other
 * account reference is dropped (see remapAccountIds). On import, the
 * placeholder becomes the importer: the exporter's participant slot is theirs
 * and records they created are attributed to them; every other slot is left
 * to be claimed again with the invite code.
 *
 * The exporter's own private data of the trip goes along (personal documents
 * with their files, all their activity photos, favorite photos, packing list,
 * personal modules, archived state); other travelers' private data never
 * does. Also left behind: messages, Cupidon, read states, photo reports and
 * AI quotas. The banner and the activity photos shared with the group travel
 * inside the file, base64-encoded, and are attributed to the importer.
 *
 * The file goes through Storage (users/{uid}/tripTransfers/) both ways, since
 * the embedded files can exceed the size of a callable request or response.
 * Each run leaves a journal in tripTransferLogs/{id} (see TransferLog).
 */

const crypto = require('crypto');
const admin = require('firebase-admin');
const { FieldValue, GeoPoint, Timestamp } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');

const TRANSFER_FORMAT = 'planerz-trip';
const TRANSFER_FORMAT_VERSION = 1;
const TRANSFER_FOLDER = 'tripTransfers';
const TRANSFER_LOGS_COLLECTION = 'tripTransferLogs';

/** Stands for the exporter in the file, and becomes the importer. */
const EXPORTER_PLACEHOLDER = '$exporter';

/** Appended to the title of an imported trip, to tell it from the original. */
const IMPORTED_TITLE_SUFFIX = '(export)';

/** Transfer files left behind (download or import interrupted). */
const STALE_TRANSFER_FILE_AGE_MS = 24 * 60 * 60 * 1000;

/** Keeps a journal well under the Firestore document size limit. */
const MAX_LOG_STEPS = 300;

const BATCH_SIZE = 400;
const SAFE_SEGMENT = /^[A-Za-z0-9_-]+$/;
const SAFE_FILE_NAME = /^[A-Za-z0-9._-]+$/;
const SEMVER = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/;

const BANNER_CONTENT_TYPES = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
};
const BANNER_MAX_BYTES = 20 * 1024 * 1024;
/** Must match `storage.rules` (activity photos). */
const ACTIVITY_PHOTO_MAX_BYTES = 3 * 1024 * 1024;
const ACTIVITY_PHOTO_CAPTION_MAX_LENGTH = 2000;
/** Must match `storage.rules` (personal documents). */
const WALLET_CONTENT_TYPES = [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
];
const WALLET_FILE_MAX_BYTES = 15 * 1024 * 1024;

/**
 * Trip subcollections carried over, each with its own carried-over
 * subcollections. Expense balances and summaries are copied as computed;
 * the settlement trigger recomputes them as the expenses are written.
 */
const TRANSFERRED_COLLECTIONS = {
  participants: {},
  participantGroups: {},
  expenseGroups: {
    balances: {},
    suggestedReimbursements: {},
    summary: {},
    state: {},
  },
  expenses: {},
  expenses_states: {},
  rooms: {},
  lodgings: {},
  activities: {},
  boardGames: {},
  shoppingItems: {},
  shopping_list_locks: {},
  consolidatedShoppingItems: {},
  meals: {},
  sections: {},
  announcements: {},
};

/**
 * Trip fields recreated for the new trip (owner, members, invite code,
 * banner, counters maintained by triggers, history of the record).
 */
const TRIP_FIELDS_NOT_TRANSFERRED = [
  'ownerId',
  'memberUserIds',
  'adminMemberIds',
  'inviteToken',
  'participantCount',
  'bannerImageUrl',
  'bannerImagePath',
  'bannerUpdatedAt',
  'createdAt',
  'updatedAt',
  'permissionsBackfilledAt',
  'permissionsBackfilledBy',
];

/** Who created or last changed a record: always the exporter / importer. */
const AUTHOR_KEYS = new Set(['createdBy', 'updatedBy', 'authorId', 'createdByUserId']);

/**
 * A given traveler (slot owner, shopping claim, meal component lock, potluck
 * contribution): kept for the exporter only, dropped for anyone else.
 */
const TRAVELER_KEYS = new Set(['userId', 'claimedBy', 'lockedBy', 'addedBy']);

/** Lists of travelers (activity votes): the exporter's entry only is kept. */
const TRAVELER_LIST_KEYS = new Set(['votes']);

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

/** `0.5.2` from `0.5.2`, `v0.5.2` or `0.5.2+29`; '' when not a version. */
function normalizeAppVersion(raw) {
  const version = normalizeString(raw).replace(/^v/i, '').split('+')[0];
  return SEMVER.test(version) ? version : '';
}

async function requireApplicationOwner(uid) {
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }
  const snap = await admin.firestore().collection('users').doc(uid).get();
  if (!snap.exists || snap.data()?.isApplicationOwner !== true) {
    throw new HttpsError('permission-denied', 'Accès réservé aux administrateurs');
  }
}

// ---------------------------------------------------------------------------
// Journal
// ---------------------------------------------------------------------------

/** JSON-safe copy of [value] (Firestore refuses undefined). */
function plain(value) {
  if (value === undefined) return null;
  try {
    return JSON.parse(JSON.stringify(value));
  } catch {
    return String(value);
  }
}

/** What to keep of an error in a journal. */
function errorSummary(error) {
  return {
    code: normalizeString(error?.code) || null,
    message: String(error?.message ?? error),
    details: plain(error?.details ?? null),
    stack: typeof error?.stack === 'string' ? error.stack.slice(0, 4000) : null,
  };
}

/**
 * Journal of one export or import, saved in tripTransferLogs/{id} for the
 * administration section (copied from there to investigate a problem) and
 * mirrored to Cloud Logging under the same id. Saved after each phase, so a
 * run cut short (timeout, memory) still leaves the steps it went through.
 */
class TransferLog {
  constructor(db, { kind, uid }) {
    this.ref = db.collection(TRANSFER_LOGS_COLLECTION).doc();
    this.id = this.ref.id;
    this.kind = kind;
    this.startedMs = Date.now();
    this.fields = { kind, uid, status: 'running', startedAt: Timestamp.now() };
    this.steps = [];
    this.droppedSteps = 0;
  }

  add(level, message, details) {
    const entry = { at: new Date().toISOString(), level, message };
    if (details !== undefined) entry.details = plain(details);
    if (this.steps.length < MAX_LOG_STEPS) {
      this.steps.push(entry);
    } else {
      this.droppedSteps++;
    }
    const write = level === 'error' ? logger.error : level === 'warn' ? logger.warn : logger.info;
    write(`tripTransfer ${this.kind}: ${message}`, {
      transferLogId: this.id,
      ...(details !== undefined ? { details: plain(details) } : {}),
    });
  }

  info(message, details) {
    this.add('info', message, details);
  }

  warn(message, details) {
    this.add('warn', message, details);
  }

  error(message, details) {
    this.add('error', message, details);
  }

  /** Summary fields shown in the list (trip ids and title, sizes…). */
  set(fields) {
    Object.assign(this.fields, plain(fields));
  }

  async save(extra = {}) {
    try {
      await this.ref.set({
        ...this.fields,
        ...extra,
        durationMs: Date.now() - this.startedMs,
        steps: this.steps,
        droppedSteps: this.droppedSteps,
      });
    } catch (e) {
      logger.error('tripTransfer: journal not saved', { transferLogId: this.id, error: String(e) });
    }
  }

  async finish(status, extra = {}) {
    await this.save({ status, finishedAt: Timestamp.now(), ...extra });
  }

  /**
   * Records [error], then the error to send back: HttpsErrors keep their
   * code and message; anything else becomes an internal error. Both carry
   * the journal id.
   */
  async fail(error) {
    this.error('Échec', errorSummary(error));
    await this.finish('error', { error: errorSummary(error) });
    if (error instanceof HttpsError) {
      return new HttpsError(error.code, error.message, {
        ...(error.details && typeof error.details === 'object' ? error.details : {}),
        logId: this.id,
      });
    }
    return new HttpsError('internal', 'Erreur inattendue, voir le journal du transfert', {
      reason: 'internal',
      logId: this.id,
    });
  }
}

// ---------------------------------------------------------------------------
// Firestore values ↔ JSON
// ---------------------------------------------------------------------------

/** Firestore value → JSON value (timestamps and GPS points tagged). */
function toTransferValue(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof Timestamp) {
    return { __type: 'timestamp', seconds: value.seconds, nanoseconds: value.nanoseconds };
  }
  if (value instanceof GeoPoint) {
    return { __type: 'geopoint', latitude: value.latitude, longitude: value.longitude };
  }
  if (Array.isArray(value)) return value.map(toTransferValue);
  if (typeof value === 'object') {
    // Document references and bytes are not used in trip data.
    if (Object.getPrototypeOf(value) !== Object.prototype) return null;
    const out = {};
    for (const [key, entry] of Object.entries(value)) {
      out[key] = toTransferValue(entry);
    }
    return out;
  }
  return value;
}

function invalidFile(detail) {
  return new HttpsError('invalid-argument', 'Fichier de voyage invalide', {
    reason: 'invalid-file',
    detail,
  });
}

/** JSON value → Firestore value; throws on malformed tagged values. */
function fromTransferValue(value) {
  if (value === null || value === undefined) return null;
  if (Array.isArray(value)) return value.map(fromTransferValue);
  if (typeof value === 'object') {
    if (value.__type === 'timestamp') {
      const { seconds, nanoseconds } = value;
      if (!Number.isInteger(seconds) || !Number.isInteger(nanoseconds)) {
        throw invalidFile('timestamp');
      }
      return new Timestamp(seconds, nanoseconds);
    }
    if (value.__type === 'geopoint') {
      const { latitude, longitude } = value;
      if (typeof latitude !== 'number' || typeof longitude !== 'number') {
        throw invalidFile('geopoint');
      }
      return new GeoPoint(latitude, longitude);
    }
    if (value.__type !== undefined) throw invalidFile('value type');
    const out = {};
    for (const [key, entry] of Object.entries(value)) {
      out[key] = fromTransferValue(entry);
    }
    return out;
  }
  return value;
}

// ---------------------------------------------------------------------------
// Account references
// ---------------------------------------------------------------------------

/**
 * Copy of a document's data where account ids are rewritten: [from] (the
 * exporter, or the placeholder on import) becomes [to]; any other account
 * is dropped, except as author, which always becomes [to].
 * @param {unknown} value
 * @param {{ from: string, to: string }} accounts
 */
function remapAccountIds(value, accounts) {
  if (Array.isArray(value)) return value.map((entry) => remapAccountIds(entry, accounts));
  if (value === null || typeof value !== 'object') return value;
  const out = {};
  for (const [key, entry] of Object.entries(value)) {
    if (AUTHOR_KEYS.has(key) && typeof entry === 'string') {
      if (entry.trim()) out[key] = accounts.to;
      continue;
    }
    if (TRAVELER_KEYS.has(key) && typeof entry === 'string') {
      if (entry.trim() === accounts.from) out[key] = accounts.to;
      continue;
    }
    if (TRAVELER_LIST_KEYS.has(key) && Array.isArray(entry)) {
      out[key] = entry.some((id) => typeof id === 'string' && id.trim() === accounts.from)
        ? [accounts.to]
        : [];
      continue;
    }
    out[key] = remapAccountIds(entry, accounts);
  }
  return out;
}

/** Firestore data of a stored document → file data, account ids rewritten. */
function exportedData(data, accounts) {
  return remapAccountIds(toTransferValue(data || {}), accounts);
}

/** File data → Firestore data, account ids rewritten. */
function importedData(data, accounts) {
  return fromTransferValue(remapAccountIds(data, accounts));
}

/** Participant slot as imported: Cupidon starts over (its data stays behind). */
function participantForImport(data) {
  const out = { ...data, cupidonEnabled: false };
  delete out.cupidonUpdatedAt;
  return out;
}

/** Trip document data carried over, without the fields recreated on import. */
function tripDataForTransfer(data) {
  const out = { ...data };
  for (const field of TRIP_FIELDS_NOT_TRANSFERRED) delete out[field];
  return out;
}

/**
 * What a transferred photo is attached to, when it is part of the trip: its
 * activity or its meal.
 * @returns {{ activityId: string } | { mealId: string } | null}
 * @param {object} raw photo record or exported photo
 * @param {{ activityIds: Set<string>, mealIds: Set<string> }} subjects
 */
function photoSubjectForTransfer(raw, { activityIds, mealIds }) {
  const mealId = normalizeString(raw?.mealId);
  if (mealId) return mealIds.has(mealId) ? { mealId } : null;
  const activityId = normalizeString(raw?.activityId);
  return activityIds.has(activityId) ? { activityId } : null;
}

/** Firestore constraints on a document id (no path traversal). */
function isValidDocId(id) {
  return typeof id === 'string'
    && id.length > 0
    && Buffer.byteLength(id, 'utf8') <= 1500
    && !id.includes('/')
    && id !== '.'
    && id !== '..'
    && !/^__.*__$/.test(id);
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/** Same alphabet and shape as the app (`ABC-123`). */
function generateInviteToken() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const segment = () =>
    Array.from({ length: 3 }, () => chars[crypto.randomInt(chars.length)]).join('');
  return `${segment()}-${segment()}`;
}

/** An invite code no other trip uses (a shared code makes joining fail). */
async function generateUniqueInviteToken(db) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const token = generateInviteToken();
    const taken = await db.collection('trips').where('inviteToken', '==', token).limit(1).get();
    if (taken.empty) return token;
  }
  throw new Error('No free invite code found');
}

/** Marks the imported trip as a copy, once (re-importing keeps one mark). */
function importedTripTitle(title) {
  const clean = normalizeString(title);
  if (clean.endsWith(IMPORTED_TITLE_SUFFIX)) return clean;
  return clean ? `${clean} ${IMPORTED_TITLE_SUFFIX}` : IMPORTED_TITLE_SUFFIX;
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

function transferFolder(uid) {
  return `users/${uid}/${TRANSFER_FOLDER}/`;
}

/** Whether [path] is one of [uid]'s transfer files. */
function isOwnTransferPath(path, uid) {
  const folder = transferFolder(uid);
  return typeof path === 'string'
    && path.startsWith(folder)
    && SAFE_FILE_NAME.test(path.slice(folder.length));
}

/** Saves [bytes] at [path] with a download token, as the client SDK does. */
async function saveWithDownloadUrl(bucket, path, bytes, contentType) {
  const token = crypto.randomUUID();
  await bucket.file(path).save(bytes, {
    resumable: false,
    contentType,
    metadata: { metadata: { firebaseStorageDownloadTokens: token } },
  });
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
}

async function deleteQuietly(file) {
  try {
    await file.delete();
  } catch (e) {
    const code = String(e?.code ?? '');
    if (code !== '404' && code !== 'not-found') {
      logger.warn('tripTransfer: file not deleted', { file: file.name, error: String(e) });
    }
  }
}

async function deletePrefixQuietly(bucket, prefix) {
  const [files] = await bucket.getFiles({ prefix, autoPaginate: true });
  await Promise.all((files || []).map(deleteQuietly));
}

/** Best effort: removes [uid]'s transfer files older than a day. */
async function deleteStaleTransferFiles(bucket, uid, now = Date.now()) {
  try {
    const [files] = await bucket.getFiles({ prefix: transferFolder(uid), autoPaginate: true });
    await Promise.all(
      (files || [])
        .filter((file) => {
          const created = Date.parse(file.metadata?.timeCreated ?? '');
          return Number.isFinite(created) && now - created > STALE_TRANSFER_FILE_AGE_MS;
        })
        .map(deleteQuietly)
    );
  } catch (e) {
    logger.warn('tripTransfer: stale files cleanup failed', { uid, error: String(e) });
  }
}

/**
 * Embedded copy of a stored file, or null when its type is not one of
 * [allowedTypes] (the import would refuse it).
 */
async function downloadAsTransferFile(file, allowedTypes) {
  const [metadata] = await file.getMetadata();
  const contentType = normalizeString(metadata?.contentType).toLowerCase();
  if (!allowedTypes.includes(contentType)) return null;
  const [bytes] = await file.download();
  return { contentType, data: bytes.toString('base64') };
}

/** Bytes of an embedded file, checked against [allowedTypes] and [maxBytes]. */
function decodeTransferFile(raw, allowedTypes, maxBytes) {
  const contentType = normalizeString(raw?.contentType).toLowerCase();
  if (!allowedTypes.includes(contentType) || typeof raw?.data !== 'string') {
    throw invalidFile('file type');
  }
  const bytes = Buffer.from(raw.data, 'base64');
  if (bytes.length === 0 || bytes.length > maxBytes) throw invalidFile('file size');
  return { contentType, bytes };
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

/**
 * Documents of [collectionRef] (and of the carried-over [nested]
 * subcollections), keyed by id, with account ids rewritten.
 */
async function exportCollection(collectionRef, nested, accounts) {
  const snap = await collectionRef.get();
  const out = {};
  for (const doc of snap.docs) {
    const node = { data: exportedData(doc.data(), accounts) };
    const nestedNames = Object.keys(nested);
    if (nestedNames.length > 0) {
      node.collections = {};
      for (const name of nestedNames) {
        node.collections[name] = await exportCollection(
          doc.ref.collection(name),
          nested[name],
          accounts
        );
      }
    }
    out[doc.id] = node;
  }
  return out;
}

/**
 * Activity and meal photos with their files: every photo of the exporter,
 * shared or not, and the photos the other travelers shared with the group.
 */
async function exportActivityPhotos({ db, bucket, tripId, activityIds, mealIds, exporterUid, log }) {
  const moduleRefs = await db
    .collection('trips')
    .doc(tripId)
    .collection('travelerModules')
    .listDocuments();
  const photos = [];
  let ownCount = 0;
  let skipped = 0;
  for (const moduleRef of moduleRefs) {
    const ownerUid = moduleRef.id;
    if (!SAFE_SEGMENT.test(ownerUid)) continue;
    const own = ownerUid === exporterUid;
    const query = own
      ? moduleRef.collection('activityPhotos')
      : moduleRef.collection('activityPhotos').where('shared', '==', true);
    const snap = await query.get();
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const subject = photoSubjectForTransfer(data, { activityIds, mealIds });
      if (!SAFE_SEGMENT.test(doc.id) || !subject) {
        skipped++;
        log.warn('Photo ignorée (activité ou repas absent)', {
          photoId: doc.id,
          activityId: normalizeString(data.activityId),
          mealId: normalizeString(data.mealId),
          own,
        });
        continue;
      }
      const folder = `users/${ownerUid}/activityPhotos/${tripId}/`;
      try {
        const [photo, thumbnail] = await Promise.all([
          downloadAsTransferFile(bucket.file(`${folder}${doc.id}.jpg`), ['image/jpeg']),
          downloadAsTransferFile(bucket.file(`${folder}${doc.id}_thumb.jpg`), ['image/jpeg']),
        ]);
        if (!photo || !thumbnail) {
          skipped++;
          log.warn('Photo ignorée (format)', { photoId: doc.id, own });
          continue;
        }
        photos.push({
          id: doc.id,
          ...subject,
          caption: normalizeString(data.caption),
          shared: data.shared === true,
          createdAt: toTransferValue(data.createdAt ?? null),
          photo,
          thumbnail,
        });
        if (own) ownCount++;
      } catch (e) {
        // A photo whose files are gone is left out rather than failing the export.
        skipped++;
        log.warn('Photo ignorée (fichiers illisibles)', { photoId: doc.id, own, error: String(e) });
      }
    }
  }
  log.info('Photos d\'activités et de repas', {
    exported: photos.length,
    exporterPhotos: ownCount,
    sharedByOthers: photos.length - ownCount,
    skipped,
  });
  return photos;
}

/**
 * The exporter's private data of the trip, or null when they have none
 * (e.g. not a traveler of this trip).
 */
async function exportPersonalData({ db, bucket, tripId, exporterUid, exporterParticipantId, photoIds, log }) {
  const accounts = { from: exporterUid, to: EXPORTER_PLACEHOLDER };
  const tripRef = db.collection('trips').doc(tripId);
  const moduleRef = tripRef.collection('travelerModules').doc(exporterUid);

  const modulesSnap = await moduleRef.get();
  const modules = modulesSnap.exists ? exportedData(modulesSnap.data(), accounts) : null;

  const walletDocuments = {};
  let walletSkipped = 0;
  const walletSnap = await moduleRef.collection('walletDocuments').get();
  for (const doc of walletSnap.docs) {
    const data = doc.data() || {};
    const node = { data: exportedData(data, accounts) };
    if (data.kind === 'file') {
      const path = normalizeString(data.file?.storagePath);
      try {
        node.file = path.startsWith(`users/${exporterUid}/wallet/${tripId}/`)
          ? await downloadAsTransferFile(bucket.file(path), WALLET_CONTENT_TYPES)
          : null;
      } catch (e) {
        node.file = null;
        log.warn('Document illisible', { documentId: doc.id, error: String(e) });
      }
      if (!node.file) {
        // A file document without its file would be broken: left out.
        walletSkipped++;
        log.warn('Document ignoré (fichier absent ou format)', { documentId: doc.id, path });
        continue;
      }
      // The path holds the exporter's account id: only the file name goes,
      // the import rebuilds the path for the importer.
      node.data.file = { ...node.data.file, storagePath: path.split('/').pop() };
    }
    walletDocuments[doc.id] = node;
  }

  const activityFavorites = {};
  const favoritesSnap = await moduleRef.collection('activityFavorites').get();
  for (const doc of favoritesSnap.docs) {
    const photoId = normalizeString(doc.data()?.photoId);
    // The photo owner becomes the importer, like every imported photo.
    if (photoIds.has(photoId)) activityFavorites[doc.id] = { photoId };
  }

  let packingList = null;
  if (exporterParticipantId) {
    const listRef = tripRef.collection('packingLists').doc(exporterParticipantId);
    const [listSnap, itemsSnap] = await Promise.all([
      listRef.get(),
      listRef.collection('items').get(),
    ]);
    if (listSnap.exists || !itemsSnap.empty) {
      packingList = {
        data: exportedData(listSnap.exists ? listSnap.data() : {}, accounts),
        items: Object.fromEntries(
          itemsSnap.docs.map((doc) => [doc.id, { data: exportedData(doc.data(), accounts) }])
        ),
      };
    }
  }

  const archived = (
    await db.collection('users').doc(exporterUid).collection('archivedTrips').doc(tripId).get()
  ).exists;

  const counts = {
    modules: modules !== null,
    walletDocuments: Object.keys(walletDocuments).length,
    walletFiles: Object.values(walletDocuments).filter((d) => d.file).length,
    walletSkipped,
    activityFavorites: Object.keys(activityFavorites).length,
    packingItems: packingList ? Object.keys(packingList.items).length : 0,
    archived,
  };
  log.info('Données privées de l\'exportateur', counts);
  const empty = !modules && counts.walletDocuments === 0 && counts.activityFavorites === 0
    && !packingList && !archived;
  return empty ? null : { modules, walletDocuments, activityFavorites, packingList, archived };
}

/** The whole transfer file of a trip, for [exporterUid]. */
async function buildTripTransferPayload({ db, bucket, tripId, tripData, exporterUid, appVersion, log }) {
  const accounts = { from: exporterUid, to: EXPORTER_PLACEHOLDER };
  const tripRef = db.collection('trips').doc(tripId);

  const collections = {};
  const counts = {};
  for (const [name, nested] of Object.entries(TRANSFERRED_COLLECTIONS)) {
    collections[name] = await exportCollection(tripRef.collection(name), nested, accounts);
    counts[name] = Object.keys(collections[name]).length;
  }
  log.info('Documents du voyage', counts);

  const exporterParticipantId = Object.entries(collections.participants)
    .find(([, node]) => node.data?.userId === EXPORTER_PLACEHOLDER)?.[0] ?? null;
  log.info('Place de l\'exportateur', { participantId: exporterParticipantId });

  let banner = null;
  const bannerPath = normalizeString(tripData.bannerImagePath);
  if (bannerPath.startsWith(`trips/${tripId}/`)) {
    try {
      banner = await downloadAsTransferFile(
        bucket.file(bannerPath),
        Object.keys(BANNER_CONTENT_TYPES)
      );
    } catch (e) {
      log.warn('Bannière illisible', { path: bannerPath, error: String(e) });
    }
  }
  log.info('Bannière', { included: banner !== null, path: bannerPath || null });

  const activityPhotos = await exportActivityPhotos({
    db,
    bucket,
    tripId,
    activityIds: new Set(Object.keys(collections.activities)),
    mealIds: new Set(Object.keys(collections.meals)),
    exporterUid,
    log,
  });

  const personal = await exportPersonalData({
    db,
    bucket,
    tripId,
    exporterUid,
    exporterParticipantId,
    photoIds: new Set(activityPhotos.map((p) => p.id)),
    log,
  });

  const lifecycleSnap = await db.collection('tripLifecycle').doc(tripId).get();
  const lifecycle = lifecycleSnap.exists ? exportedData(lifecycleSnap.data(), accounts) : null;
  log.info('Cycle de vie', { included: lifecycle !== null });

  return {
    format: TRANSFER_FORMAT,
    formatVersion: TRANSFER_FORMAT_VERSION,
    appVersion,
    exportedAt: new Date().toISOString(),
    trip: {
      data: exportedData(tripDataForTransfer(tripData), accounts),
      collections,
    },
    banner,
    activityPhotos,
    personal,
    lifecycle,
  };
}

const exportTrip = onCall(
  {
    timeoutSeconds: 540,
    memory: '2GiB',
  },
  async (request) => {
    const uid = normalizeString(request.auth?.uid);
    await requireApplicationOwner(uid);
    const tripId = normalizeString(request.data?.tripId);
    const appVersion = normalizeAppVersion(request.data?.appVersion);
    if (!SAFE_SEGMENT.test(tripId) || !appVersion) {
      throw new HttpsError('invalid-argument', 'Paramètres invalides');
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const log = new TransferLog(db, { kind: 'export', uid });
    log.set({ appVersion, sourceTripId: tripId });
    log.info('Début de l\'export', { tripId, appVersion });
    await log.save();
    try {
      const tripSnap = await db.collection('trips').doc(tripId).get();
      if (!tripSnap.exists) {
        throw new HttpsError('not-found', 'Voyage introuvable');
      }
      const tripData = tripSnap.data() || {};
      log.set({ tripTitle: normalizeString(tripData.title) });

      await deleteStaleTransferFiles(bucket, uid);

      const payload = await buildTripTransferPayload({
        db,
        bucket,
        tripId,
        tripData,
        exporterUid: uid,
        appVersion,
        log,
      });
      await log.save();

      const bytes = Buffer.from(JSON.stringify(payload), 'utf8');
      const storagePath = `${transferFolder(uid)}export-${tripId}-${Date.now()}.json`;
      await bucket.file(storagePath).save(bytes, {
        resumable: false,
        contentType: 'application/json',
      });
      log.set({ fileSizeBytes: bytes.length });
      log.info('Fichier écrit', { storagePath, sizeBytes: bytes.length });
      await log.finish('success');
      return { storagePath, sizeBytes: bytes.length, logId: log.id };
    } catch (e) {
      throw await log.fail(e);
    }
  }
);

// ---------------------------------------------------------------------------
// Import
// ---------------------------------------------------------------------------

/** Parsed transfer file, checked for shape and app version. */
function parseTransferFile(text, appVersion) {
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    throw invalidFile('json');
  }
  if (
    !isPlainObject(payload)
    || payload.format !== TRANSFER_FORMAT
    || payload.formatVersion !== TRANSFER_FORMAT_VERSION
  ) {
    throw invalidFile('format');
  }
  const fileVersion = normalizeAppVersion(payload.appVersion);
  if (!fileVersion || fileVersion !== appVersion) {
    throw new HttpsError(
      'failed-precondition',
      'Version du fichier différente de la version de l\'application',
      { reason: 'version-mismatch', fileVersion: normalizeString(payload.appVersion), appVersion }
    );
  }
  if (!isPlainObject(payload.trip) || !isPlainObject(payload.trip.data)) {
    throw invalidFile('trip');
  }
  return payload;
}

/**
 * Flat list of the writes recreating the carried-over subcollections under
 * [tripRef], account ids rewritten for the importer.
 */
function collectionWrites(tripRef, collections, allowed, accounts, writes = []) {
  if (!isPlainObject(collections)) return writes;
  for (const [name, docs] of Object.entries(collections)) {
    if (!Object.prototype.hasOwnProperty.call(allowed, name)) continue;
    if (!isPlainObject(docs)) throw invalidFile(name);
    for (const [docId, node] of Object.entries(docs)) {
      if (!isValidDocId(docId) || !isPlainObject(node?.data)) {
        throw invalidFile(name);
      }
      const ref = tripRef.collection(name).doc(docId);
      let data = importedData(node.data, accounts);
      if (name === 'participants') data = participantForImport(data);
      writes.push({ ref, data });
      collectionWrites(ref, node.collections, allowed[name], accounts, writes);
    }
  }
  return writes;
}

/** Writes and uploads recreating the importer's private data. */
async function personalDataWrites({ db, bucket, tripRef, personal, importerUid, slotId, photoIds, accounts, log }) {
  const writes = [];
  if (!isPlainObject(personal)) return writes;
  const moduleRef = tripRef.collection('travelerModules').doc(importerUid);

  if (isPlainObject(personal.modules)) {
    writes.push({ ref: moduleRef, data: importedData(personal.modules, accounts) });
  }

  let walletFiles = 0;
  const walletFolder = `users/${importerUid}/wallet/${tripRef.id}/`;
  for (const [docId, node] of Object.entries(
    isPlainObject(personal.walletDocuments) ? personal.walletDocuments : {}
  )) {
    if (!isValidDocId(docId) || !isPlainObject(node?.data)) throw invalidFile('walletDocuments');
    const data = importedData(node.data, accounts);
    if (data.kind === 'file') {
      const { contentType, bytes } = decodeTransferFile(
        node.file,
        WALLET_CONTENT_TYPES,
        WALLET_FILE_MAX_BYTES
      );
      const originalName = normalizeString(data.file?.storagePath).split('/').pop();
      const fileName = SAFE_FILE_NAME.test(originalName) ? originalName : `${docId}.bin`;
      const storagePath = `${walletFolder}${fileName}`;
      await bucket.file(storagePath).save(bytes, { resumable: false, contentType });
      data.file = { ...(isPlainObject(data.file) ? data.file : {}), storagePath, contentType, sizeBytes: bytes.length };
      walletFiles++;
    }
    writes.push({ ref: moduleRef.collection('walletDocuments').doc(docId), data });
  }

  let favorites = 0;
  for (const [activityId, node] of Object.entries(
    isPlainObject(personal.activityFavorites) ? personal.activityFavorites : {}
  )) {
    const photoId = normalizeString(node?.photoId);
    if (!isValidDocId(activityId) || !photoIds.has(photoId)) continue;
    writes.push({
      ref: moduleRef.collection('activityFavorites').doc(activityId),
      data: { ownerId: importerUid, photoId, updatedAt: FieldValue.serverTimestamp() },
    });
    favorites++;
  }

  let packingItems = 0;
  if (slotId && isPlainObject(personal.packingList)) {
    const listRef = tripRef.collection('packingLists').doc(slotId);
    const listData = isPlainObject(personal.packingList.data) ? personal.packingList.data : {};
    writes.push({ ref: listRef, data: importedData(listData, accounts) });
    for (const [itemId, node] of Object.entries(
      isPlainObject(personal.packingList.items) ? personal.packingList.items : {}
    )) {
      if (!isValidDocId(itemId) || !isPlainObject(node?.data)) throw invalidFile('packingList');
      writes.push({ ref: listRef.collection('items').doc(itemId), data: importedData(node.data, accounts) });
      packingItems++;
    }
  }

  if (personal.archived === true) {
    writes.push({
      ref: db.collection('users').doc(importerUid).collection('archivedTrips').doc(tripRef.id),
      data: { archivedAt: FieldValue.serverTimestamp() },
    });
  }

  log.info('Données privées de l\'importeur', {
    modules: isPlainObject(personal.modules),
    walletDocuments: Object.keys(personal.walletDocuments || {}).length,
    walletFiles,
    activityFavorites: favorites,
    packingItems,
    packingSlot: slotId,
    archived: personal.archived === true,
  });
  return writes;
}

async function commitWrites(db, writes) {
  for (let offset = 0; offset < writes.length; offset += BATCH_SIZE) {
    const batch = db.batch();
    for (const { ref, data } of writes.slice(offset, offset + BATCH_SIZE)) {
      batch.set(ref, data);
    }
    await batch.commit();
  }
}

/** Removes a partially imported trip (records, files, personal traces). */
async function deleteImportedTrip({ db, bucket, tripRef, importerUid, log }) {
  try {
    await db.recursiveDelete(tripRef);
    await db.collection('tripLifecycle').doc(tripRef.id).delete();
    await db.collection('users').doc(importerUid).collection('archivedTrips').doc(tripRef.id).delete();
    for (const prefix of [
      `trips/${tripRef.id}/`,
      `users/${importerUid}/activityPhotos/${tripRef.id}/`,
      `users/${importerUid}/wallet/${tripRef.id}/`,
    ]) {
      await deletePrefixQuietly(bucket, prefix);
    }
    log.info('Import annulé : voyage partiel supprimé', { tripId: tripRef.id });
  } catch (e) {
    log.error('Annulation incomplète, voyage partiel à supprimer à la main', {
      tripId: tripRef.id,
      error: String(e),
    });
  }
}

async function importTripPayload({ db, bucket, payload, importerUid, importerEmail, log }) {
  const accounts = { from: EXPORTER_PLACEHOLDER, to: importerUid };
  const tripRef = db.collection('trips').doc();
  log.set({ newTripId: tripRef.id });

  const writes = collectionWrites(
    tripRef,
    payload.trip.collections,
    TRANSFERRED_COLLECTIONS,
    accounts
  );
  const counts = {};
  for (const { ref } of writes) {
    const path = ref.path.slice(tripRef.path.length + 1).replace(/\/[^/]+(\/|$)/g, '$1');
    counts[path] = (counts[path] || 0) + 1;
  }
  log.info('Documents du voyage à écrire', counts);

  const idsOf = (collection) => new Set(
    writes
      .filter(({ ref }) => ref.parent.id === collection && ref.parent.parent.id === tripRef.id)
      .map(({ ref }) => ref.id)
  );
  const activityIds = idsOf('activities');
  const mealIds = idsOf('meals');
  let slotId = writes.find(
    ({ ref, data }) => ref.parent.id === 'participants' && data.userId === importerUid
  )?.ref.id ?? null;

  try {
    const tripData = tripDataForTransfer(importedData(payload.trip.data, accounts));
    tripData.title = importedTripTitle(tripData.title);
    if (payload.banner) {
      const { contentType, bytes } = decodeTransferFile(
        payload.banner,
        Object.keys(BANNER_CONTENT_TYPES),
        BANNER_MAX_BYTES
      );
      const path = `trips/${tripRef.id}/banner_${Date.now()}.${BANNER_CONTENT_TYPES[contentType]}`;
      tripData.bannerImageUrl = await saveWithDownloadUrl(bucket, path, bytes, contentType);
      tripData.bannerImagePath = path;
      tripData.bannerUpdatedAt = FieldValue.serverTimestamp();
      log.info('Bannière déposée', { path, sizeBytes: bytes.length });
    }

    // The trip first: participant triggers update it (participant count).
    const inviteToken = await generateUniqueInviteToken(db);
    await tripRef.set({
      ...tripData,
      ownerId: importerUid,
      memberUserIds: [importerUid],
      inviteToken,
      createdAt: FieldValue.serverTimestamp(),
    });
    log.info('Voyage créé', { tripId: tripRef.id, title: tripData.title, inviteToken });

    if (!slotId) {
      // The exporter had no participant slot: the importer gets a new one.
      const ref = tripRef.collection('participants').doc();
      slotId = ref.id;
      writes.push({
        ref,
        data: {
          participantName: normalizeString(importerEmail).split('@')[0] || 'Moi',
          userId: importerUid,
          useProfileName: true,
          cupidonEnabled: false,
          phoneVisibility: 'nobody',
          createdAt: FieldValue.serverTimestamp(),
        },
      });
      log.info('Nouvelle place créée pour l\'importeur', { participantId: slotId });
    } else {
      log.info('Place de l\'exportateur reprise', { participantId: slotId });
    }

    const photos = Array.isArray(payload.activityPhotos) ? payload.activityPhotos : [];
    const photosRef = tripRef
      .collection('travelerModules')
      .doc(importerUid)
      .collection('activityPhotos');
    const photoFolder = `users/${importerUid}/activityPhotos/${tripRef.id}/`;
    const photoIds = new Set();
    for (const raw of photos) {
      const photoId = normalizeString(raw?.id);
      const subject = photoSubjectForTransfer(raw, { activityIds, mealIds });
      if (!SAFE_SEGMENT.test(photoId) || !subject) {
        log.warn('Photo ignorée', {
          photoId,
          activityId: normalizeString(raw?.activityId),
          mealId: normalizeString(raw?.mealId),
        });
        continue;
      }
      const photo = decodeTransferFile(raw.photo, ['image/jpeg'], ACTIVITY_PHOTO_MAX_BYTES);
      const thumbnail = decodeTransferFile(raw.thumbnail, ['image/jpeg'], ACTIVITY_PHOTO_MAX_BYTES);
      const [url, thumbUrl] = await Promise.all([
        saveWithDownloadUrl(bucket, `${photoFolder}${photoId}.jpg`, photo.bytes, 'image/jpeg'),
        saveWithDownloadUrl(bucket, `${photoFolder}${photoId}_thumb.jpg`, thumbnail.bytes, 'image/jpeg'),
      ]);
      const caption = normalizeString(raw.caption).slice(0, ACTIVITY_PHOTO_CAPTION_MAX_LENGTH);
      const createdAt = fromTransferValue(raw.createdAt ?? null);
      writes.push({
        ref: photosRef.doc(photoId),
        data: {
          ...subject,
          url,
          thumbUrl,
          ...(caption ? { caption } : {}),
          // Private photos (the importer's own) have no flag, like in the app.
          ...(raw.shared === true ? { shared: true } : {}),
          createdAt: createdAt instanceof Timestamp ? createdAt : FieldValue.serverTimestamp(),
        },
      });
      photoIds.add(photoId);
    }
    log.info('Photos d\'activités et de repas déposées', {
      count: photoIds.size,
      private: photos.filter((p) => photoIds.has(normalizeString(p?.id)) && p.shared !== true).length,
    });

    writes.push(
      ...(await personalDataWrites({
        db,
        bucket,
        tripRef,
        personal: payload.personal,
        importerUid,
        slotId,
        photoIds,
        accounts,
        log,
      }))
    );

    if (isPlainObject(payload.lifecycle)) {
      writes.push({
        ref: db.collection('tripLifecycle').doc(tripRef.id),
        data: importedData(payload.lifecycle, accounts),
      });
    }

    await log.save();
    await commitWrites(db, writes);
    log.info('Écritures validées', { documents: writes.length });
  } catch (e) {
    log.error('Erreur pendant l\'import', errorSummary(e));
    await deleteImportedTrip({ db, bucket, tripRef, importerUid, log });
    throw e;
  }
  return tripRef.id;
}

const importTrip = onCall(
  {
    timeoutSeconds: 540,
    memory: '2GiB',
  },
  async (request) => {
    const uid = normalizeString(request.auth?.uid);
    await requireApplicationOwner(uid);
    const storagePath = normalizeString(request.data?.storagePath);
    const appVersion = normalizeAppVersion(request.data?.appVersion);
    if (!isOwnTransferPath(storagePath, uid) || !appVersion) {
      throw new HttpsError('invalid-argument', 'Paramètres invalides');
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const log = new TransferLog(db, { kind: 'import', uid });
    log.set({ appVersion });
    log.info('Début de l\'import', { storagePath, appVersion });
    await log.save();
    try {
      const file = bucket.file(storagePath);
      let text;
      try {
        const [bytes] = await file.download();
        text = bytes.toString('utf8');
      } catch (e) {
        log.error('Fichier déposé illisible', { storagePath, error: String(e) });
        throw new HttpsError('not-found', 'Fichier introuvable');
      } finally {
        await deleteQuietly(file);
      }
      log.set({ fileSizeBytes: Buffer.byteLength(text, 'utf8') });
      log.info('Fichier lu', { sizeBytes: Buffer.byteLength(text, 'utf8') });
      await deleteStaleTransferFiles(bucket, uid);

      const payload = parseTransferFile(text, appVersion);
      text = null;
      log.set({ tripTitle: normalizeString(payload.trip.data.title) });
      log.info('Fichier valide', {
        fileVersion: payload.appVersion,
        exportedAt: payload.exportedAt ?? null,
        photos: Array.isArray(payload.activityPhotos) ? payload.activityPhotos.length : 0,
        banner: Boolean(payload.banner),
        personal: Boolean(payload.personal),
        lifecycle: Boolean(payload.lifecycle),
      });
      await log.save();

      const tripId = await importTripPayload({
        db,
        bucket,
        payload,
        importerUid: uid,
        importerEmail: request.auth?.token?.email,
        log,
      });
      await log.finish('success');
      return { tripId, logId: log.id };
    } catch (e) {
      throw await log.fail(e);
    }
  }
);

module.exports = {
  EXPORTER_PLACEHOLDER,
  TRANSFERRED_COLLECTIONS,
  TransferLog,
  normalizeAppVersion,
  toTransferValue,
  fromTransferValue,
  remapAccountIds,
  participantForImport,
  tripDataForTransfer,
  photoSubjectForTransfer,
  isValidDocId,
  isOwnTransferPath,
  generateInviteToken,
  importedTripTitle,
  parseTransferFile,
  collectionWrites,
  buildTripTransferPayload,
  importTripPayload,
  exportTrip,
  importTrip,
};
