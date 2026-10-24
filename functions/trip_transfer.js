'use strict';

/**
 * Trip transfer between environments (typically preview → prod): the trip
 * owner exports a trip as a JSON file, and anyone imports such a file from
 * the trip list as a new trip they own.
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
 * Not transferred: messages, personal data of each traveler (documents,
 * private photos, packing lists, favorites, module toggles), Cupidon, read
 * states, photo reports and AI quotas. The banner and the shared activity
 * photos travel inside the file, base64-encoded; the shared photos are
 * attributed to the importer.
 *
 * The file goes through Storage (users/{uid}/tripTransfers/) both ways, since
 * the embedded photos can exceed the size of a callable request or response.
 */

const crypto = require('crypto');
const admin = require('firebase-admin');
const { FieldValue, GeoPoint, Timestamp } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

const TRANSFER_FORMAT = 'planerz-trip';
const TRANSFER_FORMAT_VERSION = 1;
const TRANSFER_FOLDER = 'tripTransfers';

/** Stands for the exporter in the file, and becomes the importer. */
const EXPORTER_PLACEHOLDER = '$exporter';

/** Transfer files left behind (download or import interrupted). */
const STALE_TRANSFER_FILE_AGE_MS = 24 * 60 * 60 * 1000;

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

/** Same alphabet and shape as the app (`ABC-123`). */
function generateInviteToken() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const segment = () =>
    Array.from({ length: 3 }, () => chars[crypto.randomInt(chars.length)]).join('');
  return `${segment()}-${segment()}`;
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
      console.warn('trip transfer: file not deleted', file.name, String(e));
    }
  }
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
    console.warn('trip transfer: stale files cleanup failed', uid, String(e));
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
    const node = { data: remapAccountIds(toTransferValue(doc.data()), accounts) };
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

/** Every traveler's shared photos of the trip's activities, with their files. */
async function exportSharedActivityPhotos(db, bucket, tripId, activityIds) {
  const moduleRefs = await db
    .collection('trips')
    .doc(tripId)
    .collection('travelerModules')
    .listDocuments();
  const photos = [];
  for (const moduleRef of moduleRefs) {
    const ownerUid = moduleRef.id;
    if (!SAFE_SEGMENT.test(ownerUid)) continue;
    const snap = await moduleRef.collection('activityPhotos').where('shared', '==', true).get();
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const activityId = normalizeString(data.activityId);
      if (!SAFE_SEGMENT.test(doc.id) || !activityIds.has(activityId)) continue;
      const folder = `users/${ownerUid}/activityPhotos/${tripId}/`;
      try {
        const [photo, thumbnail] = await Promise.all([
          downloadAsTransferFile(bucket.file(`${folder}${doc.id}.jpg`), ['image/jpeg']),
          downloadAsTransferFile(bucket.file(`${folder}${doc.id}_thumb.jpg`), ['image/jpeg']),
        ]);
        if (!photo || !thumbnail) continue;
        photos.push({
          id: doc.id,
          activityId,
          caption: normalizeString(data.caption),
          createdAt: toTransferValue(data.createdAt ?? null),
          photo,
          thumbnail,
        });
      } catch (e) {
        // A photo whose files are gone is left out rather than failing the export.
        console.warn('exportTrip: activity photo skipped', tripId, ownerUid, doc.id, String(e));
      }
    }
  }
  return photos;
}

/** The whole transfer file of a trip, for [exporterUid]. */
async function buildTripTransferPayload({ db, bucket, tripId, tripData, exporterUid, appVersion }) {
  const accounts = { from: exporterUid, to: EXPORTER_PLACEHOLDER };
  const tripRef = db.collection('trips').doc(tripId);

  const collections = {};
  for (const [name, nested] of Object.entries(TRANSFERRED_COLLECTIONS)) {
    collections[name] = await exportCollection(tripRef.collection(name), nested, accounts);
  }

  let banner = null;
  const bannerPath = normalizeString(tripData.bannerImagePath);
  if (bannerPath.startsWith(`trips/${tripId}/`)) {
    try {
      banner = await downloadAsTransferFile(
        bucket.file(bannerPath),
        Object.keys(BANNER_CONTENT_TYPES)
      );
    } catch (e) {
      console.warn('exportTrip: banner skipped', tripId, String(e));
    }
  }

  const activityPhotos = await exportSharedActivityPhotos(
    db,
    bucket,
    tripId,
    new Set(Object.keys(collections.activities))
  );

  return {
    format: TRANSFER_FORMAT,
    formatVersion: TRANSFER_FORMAT_VERSION,
    appVersion,
    exportedAt: new Date().toISOString(),
    trip: {
      data: remapAccountIds(toTransferValue(tripDataForTransfer(tripData)), accounts),
      collections,
    },
    banner,
    activityPhotos,
  };
}

const exportTrip = onCall(
  {
    timeoutSeconds: 540,
    memory: '2GiB',
  },
  async (request) => {
    const uid = normalizeString(request.auth?.uid);
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }
    const tripId = normalizeString(request.data?.tripId);
    const appVersion = normalizeAppVersion(request.data?.appVersion);
    if (!SAFE_SEGMENT.test(tripId) || !appVersion) {
      throw new HttpsError('invalid-argument', 'Paramètres invalides');
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const tripSnap = await db.collection('trips').doc(tripId).get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const tripData = tripSnap.data() || {};
    if (normalizeString(tripData.ownerId) !== uid) {
      throw new HttpsError(
        'permission-denied',
        'Seul le propriétaire peut exporter ce voyage'
      );
    }

    await deleteStaleTransferFiles(bucket, uid);

    const payload = await buildTripTransferPayload({
      db,
      bucket,
      tripId,
      tripData,
      exporterUid: uid,
      appVersion,
    });
    const bytes = Buffer.from(JSON.stringify(payload), 'utf8');
    const storagePath = `${transferFolder(uid)}export-${tripId}-${Date.now()}.json`;
    await bucket.file(storagePath).save(bytes, {
      resumable: false,
      contentType: 'application/json',
    });

    return { storagePath, sizeBytes: bytes.length };
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
    !payload
    || typeof payload !== 'object'
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
  const trip = payload.trip;
  if (!trip || typeof trip.data !== 'object' || trip.data === null) {
    throw invalidFile('trip');
  }
  return payload;
}

/**
 * Flat list of the writes recreating the carried-over subcollections under
 * [tripRef], account ids rewritten for [importerUid].
 */
function collectionWrites(tripRef, collections, allowed, accounts, writes = []) {
  if (!collections || typeof collections !== 'object') return writes;
  for (const [name, docs] of Object.entries(collections)) {
    if (!Object.prototype.hasOwnProperty.call(allowed, name)) continue;
    if (!docs || typeof docs !== 'object') throw invalidFile(name);
    for (const [docId, node] of Object.entries(docs)) {
      if (!isValidDocId(docId) || !node || typeof node.data !== 'object' || node.data === null) {
        throw invalidFile(name);
      }
      const ref = tripRef.collection(name).doc(docId);
      let data = fromTransferValue(remapAccountIds(node.data, accounts));
      if (name === 'participants') data = participantForImport(data);
      writes.push({ ref, data });
      collectionWrites(ref, node.collections, allowed[name], accounts, writes);
    }
  }
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

/** Removes a partially imported trip (records and files). */
async function deleteImportedTrip(db, bucket, tripRef, importerUid) {
  try {
    await db.recursiveDelete(tripRef);
    for (const prefix of [
      `trips/${tripRef.id}/`,
      `users/${importerUid}/activityPhotos/${tripRef.id}/`,
    ]) {
      const [files] = await bucket.getFiles({ prefix, autoPaginate: true });
      await Promise.all((files || []).map(deleteQuietly));
    }
  } catch (e) {
    console.error('importTrip: rollback failed', tripRef.id, String(e));
  }
}

async function importTripPayload({ db, bucket, payload, importerUid, importerEmail }) {
  const accounts = { from: EXPORTER_PLACEHOLDER, to: importerUid };
  const tripRef = db.collection('trips').doc();
  const writes = collectionWrites(
    tripRef,
    payload.trip.collections,
    TRANSFERRED_COLLECTIONS,
    accounts
  );
  const activityIds = new Set(
    writes
      .filter(({ ref }) => ref.parent.id === 'activities' && ref.parent.parent.id === tripRef.id)
      .map(({ ref }) => ref.id)
  );
  const hasImporterSlot = writes.some(
    ({ ref, data }) => ref.parent.id === 'participants' && data.userId === importerUid
  );

  try {
    const tripData = tripDataForTransfer(
      fromTransferValue(remapAccountIds(payload.trip.data, accounts))
    );
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
    }

    // The trip first: participant triggers update it (participant count).
    await tripRef.set({
      ...tripData,
      ownerId: importerUid,
      memberUserIds: [importerUid],
      inviteToken: generateInviteToken(),
      createdAt: FieldValue.serverTimestamp(),
    });

    if (!hasImporterSlot) {
      // The exporter had no participant slot: the importer gets a new one.
      writes.push({
        ref: tripRef.collection('participants').doc(),
        data: {
          participantName: normalizeString(importerEmail).split('@')[0] || 'Moi',
          userId: importerUid,
          useProfileName: true,
          cupidonEnabled: false,
          phoneVisibility: 'nobody',
          createdAt: FieldValue.serverTimestamp(),
        },
      });
    }

    const photos = Array.isArray(payload.activityPhotos) ? payload.activityPhotos : [];
    const photosRef = tripRef
      .collection('travelerModules')
      .doc(importerUid)
      .collection('activityPhotos');
    const photoFolder = `users/${importerUid}/activityPhotos/${tripRef.id}/`;
    for (const raw of photos) {
      const photoId = normalizeString(raw?.id);
      const activityId = normalizeString(raw?.activityId);
      if (!SAFE_SEGMENT.test(photoId) || !activityIds.has(activityId)) continue;
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
          activityId,
          url,
          thumbUrl,
          ...(caption ? { caption } : {}),
          shared: true,
          createdAt: createdAt instanceof Timestamp ? createdAt : FieldValue.serverTimestamp(),
        },
      });
    }

    await commitWrites(db, writes);
  } catch (e) {
    await deleteImportedTrip(db, bucket, tripRef, importerUid);
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
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }
    const storagePath = normalizeString(request.data?.storagePath);
    const appVersion = normalizeAppVersion(request.data?.appVersion);
    if (!isOwnTransferPath(storagePath, uid) || !appVersion) {
      throw new HttpsError('invalid-argument', 'Paramètres invalides');
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    let text;
    try {
      const [bytes] = await file.download();
      text = bytes.toString('utf8');
    } catch (e) {
      throw new HttpsError('not-found', 'Fichier introuvable');
    } finally {
      await deleteQuietly(file);
    }
    await deleteStaleTransferFiles(bucket, uid);

    const payload = parseTransferFile(text, appVersion);
    text = null;
    const tripId = await importTripPayload({
      db,
      bucket,
      payload,
      importerUid: uid,
      importerEmail: request.auth?.token?.email,
    });
    return { tripId };
  }
);

module.exports = {
  EXPORTER_PLACEHOLDER,
  TRANSFERRED_COLLECTIONS,
  normalizeAppVersion,
  toTransferValue,
  fromTransferValue,
  remapAccountIds,
  participantForImport,
  tripDataForTransfer,
  isValidDocId,
  isOwnTransferPath,
  generateInviteToken,
  parseTransferFile,
  collectionWrites,
  buildTripTransferPayload,
  importTripPayload,
  exportTrip,
  importTrip,
};
