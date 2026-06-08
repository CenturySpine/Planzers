const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const cheerio = require('cheerio');

const { setGlobalOptions } = require('firebase-functions/v2');
const { insertApplicationLog } = require('./application_logs');
const { collectOrphanDismissDocs } = require('./orphan_admin_dismiss_cleanup');
const { withAiQuota, reserveQuota, refundQuota } = require('./utils/aiQuotaGate');
const {
  buildNotificationQueueDocId,
  enqueueTripNotification,
  claimAndDeleteNotificationQueueDoc,
} = require('./notification_queue');

admin.initializeApp();
setGlobalOptions({ region: 'europe-west9' });

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function safeUrl(v) {
  const s = normalizeString(v);
  if (!s) return null;
  try {
    const u = new URL(s);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    return u;
  } catch {
    return null;
  }
}

function pickFirst(...values) {
  for (const v of values) {
    const s = normalizeString(v);
    if (s) return s;
  }
  return '';
}

function normalizeLanguageCode(value) {
  const rawCode = normalizeString(value).replace(/_/g, '-');
  if (!rawCode) return '';
  if (!/^[A-Za-z]{2,3}(-[A-Za-z]{2,4})?$/.test(rawCode)) return '';
  return rawCode;
}

/** Text before @ for public trip member chips (empty if unusable). */
function emailLocalPart(email) {
  const e = normalizeString(email);
  if (!e) return '';
  const at = e.indexOf('@');
  return at > 0 ? e.slice(0, at).trim() : e;
}

const PARTICIPANT_NAME_MIN_LEN = 2;
const PARTICIPANT_NAME_MAX_LEN = 50;

/** Required when joining without claiming a pre-planned participant slot. */
function assertParticipantNameForNewJoin(rawName) {
  const name = normalizeString(rawName);
  if (
    name.length < PARTICIPANT_NAME_MIN_LEN ||
    name.length > PARTICIPANT_NAME_MAX_LEN
  ) {
    throw new HttpsError(
      'invalid-argument',
      'Indique ton prénom ou pseudo pour rejoindre ce voyage (2 à 50 caractères).'
    );
  }
  return name;
}

async function fetchHtml(url) {
  const res = await fetch(url.toString(), {
    redirect: 'follow',
    headers: {
      'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      accept:
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'accept-language': 'fr-FR,fr;q=0.9,en;q=0.8',
    },
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  const finalUrl = safeUrl(res.url) || url;
  return { html: await res.text(), finalUrl };
}

function isGoogleMapsUrl(url) {
  const h = url.hostname;
  const p = url.pathname || '';
  return (
    h === 'maps.google.com' ||
    (h === 'www.google.com' && p.startsWith('/maps')) ||
    h === 'maps.app.goo.gl' ||
    (h === 'goo.gl' && p.startsWith('/maps'))
  );
}

function extractGoogleMapsPreview(url) {
  const p = url.pathname;

  let title = '';
  // /maps/place/NAME/@lat,lng  or  /maps/search/NAME/@...
  const placeMatch = p.match(/\/maps\/(?:place|search)\/([^/@?]+)/);
  if (placeMatch) {
    title = decodeURIComponent(placeMatch[1].replace(/\+/g, ' '));
  }
  // ?q=NAME fallback
  if (!title) {
    const q = url.searchParams.get('q');
    if (q) title = q;
  }

  let description = '';
  let lat = null;
  let lng = null;
  // Coordinates as human-readable fallback description
  const coordMatch = p.match(/@(-?\d+\.?\d*),(-?\d+\.?\d*)/);
  if (coordMatch) {
    lat = parseFloat(coordMatch[1]);
    lng = parseFloat(coordMatch[2]);
    description = `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
  }

  return { title, description, siteName: 'Google Maps', imageUrl: '', lat, lng };
}

function extractJsonLd($) {
  let title = '';
  let description = '';
  let imageUrl = '';

  $('script[type="application/ld+json"]').each((_, el) => {
    if (title && description && imageUrl) return;
    try {
      const data = JSON.parse($(el).html() || '');
      const nodes =
        data && Array.isArray(data['@graph']) ? data['@graph'] : [data];
      for (const node of nodes) {
        if (!node || typeof node !== 'object') continue;
        if (!title) title = normalizeString(node.name);
        if (!description) description = normalizeString(node.description);
        if (!imageUrl) {
          const img = node.image;
          if (typeof img === 'string') imageUrl = img;
          else if (img && !Array.isArray(img))
            imageUrl = normalizeString(img.url);
          else if (Array.isArray(img) && img.length > 0) {
            const first = img[0];
            imageUrl =
              typeof first === 'string'
                ? first
                : normalizeString((first || {}).url);
          }
        }
      }
    } catch {}
  });

  return { title, description, imageUrl };
}

const _GOOGLE_MAPS_GENERIC_DESC =
  'Find local businesses, view maps and get driving directions in Google Maps.';

function isGoogleMapsGenericDesc(desc) {
  return normalizeString(desc) === _GOOGLE_MAPS_GENERIC_DESC;
}

function parsePreviewFromHtml(finalUrl, html) {
  const $ = cheerio.load(html);

  const meta = (key) =>
    pickFirst(
      $(`meta[property="${key}"]`).attr('content'),
      $(`meta[name="${key}"]`).attr('content')
    );

  const ogTitle = meta('og:title');
  const ogDescription = meta('og:description');
  const ogImage = meta('og:image');
  const ogSiteName = meta('og:site_name');

  const twitterTitle = meta('twitter:title');
  const twitterDescription = meta('twitter:description');
  const twitterImage = meta('twitter:image');

  const titleTag = normalizeString($('title').first().text());
  const jsonLd = extractJsonLd($);

  const title = pickFirst(ogTitle, twitterTitle, jsonLd.title, titleTag);
  const description = pickFirst(
    ogDescription,
    twitterDescription,
    jsonLd.description
  );
  const siteName = pickFirst(ogSiteName, finalUrl.hostname);
  const imageRaw = pickFirst(ogImage, twitterImage, jsonLd.imageUrl);

  let imageUrl = '';
  if (imageRaw) {
    try {
      imageUrl = new URL(imageRaw, finalUrl).toString();
    } catch {
      imageUrl = '';
    }
  }

  const result = { title, description, siteName, imageUrl };

  // For Google Maps URLs, override generic og data with URL-extracted values.
  if (isGoogleMapsUrl(finalUrl)) {
    const maps = extractGoogleMapsPreview(finalUrl);

    // og:title is usually correct (place name), but override if missing/generic.
    if (maps.title && (!result.title || result.title === 'Google Maps')) {
      result.title = maps.title;
    }

    // og:description is always Google's generic app tagline — discard it.
    result.description =
      isGoogleMapsGenericDesc(result.description) || !result.description
        ? maps.description
        : result.description;

    // og:image is a generic static-map thumbnail, never a place photo — drop it.
    result.imageUrl = '';

    // "Google Maps" as siteName is redundant alongside the place name.
    result.siteName = '';
  }

  return result;
}

/**
 * Enriches a Google Maps preview with data from the Places API (New).
 * Returns { title, description, imageUrl } overrides, or null on failure.
 */
async function enrichWithGooglePlaces(name, lat, lng) {
  const apiKey = process.env.GOOGLE_PLACES_API_KEY;
  if (!apiKey || !name) return null;

  try {
    const searchBody = { textQuery: name };
    if (lat != null && lng != null) {
      searchBody.locationBias = {
        circle: {
          center: { latitude: lat, longitude: lng },
          radius: 500.0,
        },
      };
    }

    const searchRes = await fetch('https://places.googleapis.com/v1/places:searchText', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'places.id,places.displayName,places.shortFormattedAddress,places.photos',
      },
      body: JSON.stringify(searchBody),
    });
    if (!searchRes.ok) return null;

    const searchData = await searchRes.json();
    const places = searchData.places;
    if (!places || places.length === 0) return null;

    const place = places[0];
    const title = place.displayName?.text || name;
    const description = place.shortFormattedAddress || '';

    let imageUrl = '';
    if (place.photos && place.photos.length > 0) {
      const photoName = place.photos[0].name;
      const photoRes = await fetch(`https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=800`, {
        headers: { 'X-Goog-Api-Key': apiKey },
        redirect: 'follow',
      });
      if (photoRes.ok) {
        const resolvedImageUrl = new URL(photoRes.url);
        resolvedImageUrl.searchParams.delete('key');
        imageUrl = resolvedImageUrl.toString();
      }
    }

    return { title, description, imageUrl };
  } catch {
    return null;
  }
}

/** @param {FirebaseFirestore.DocumentData} data */
function memberUserIdsAsSet(data) {
  const raw = data.memberUserIds;
  if (!Array.isArray(raw)) return new Set();
  return new Set(raw.map((v) => String(v)));
}

/** Co-admin uids on the trip document (creator is always admin via ownerId). */
function tripAdminMemberIdSet(data) {
  const raw = data.adminMemberIds;
  if (!Array.isArray(raw)) return new Set();
  return new Set(raw.map((v) => String(v)));
}

function isTripAdminUser(data, uid) {
  const u = normalizeString(uid);
  if (!u) return false;
  if (normalizeString(data.ownerId) === u) return true;
  return tripAdminMemberIdSet(data).has(u);
}

function roleRank(roleName) {
  const role = normalizeString(roleName);
  if (role === 'owner') return 3;
  if (role === 'admin') return 2;
  if (role === 'chef') return 1;
  return 0;
}

function tripCallerRoleRank(data, uid) {
  const cleanUid = normalizeString(uid);
  if (!cleanUid) return -1;
  if (normalizeString(data.ownerId) === cleanUid) return 3;
  return tripAdminMemberIdSet(data).has(cleanUid) ? 2 : 0;
}

function tripParticipantPermissionMinRole(data, key, fallbackRole) {
  const perms =
    data && typeof data.permissions === 'object' ? data.permissions : {};
  const participantPerms =
    perms && typeof perms.participants === 'object' ? perms.participants : {};
  const configured = normalizeString(participantPerms[key]);
  return configured || fallbackRole;
}

function defaultTripPermissions() {
  return {
    tripGeneral: {
      editGeneralInfo: 'admin',
      manageBanner: 'admin',
      publishAnnouncements: 'admin',
      shareAccess: 'participant',
      manageTripSettings: 'owner',
      deleteTrip: 'owner',
    },
    participants: {
      createParticipant: 'owner',
      editPlaceholderParticipant: 'owner',
      deletePlaceholderParticipant: 'owner',
      deleteRegisteredParticipant: 'owner',
      toggleAdminRole: 'owner',
    },
    expenses: {
      createExpensePost: 'participant',
      editExpensePost: 'participant',
      deleteExpensePost: 'participant',
      createExpense: 'participant',
      editExpense: 'participant',
      deleteExpense: 'participant',
    },
    activities: {
      suggestActivity: 'participant',
      planActivity: 'admin',
      editActivity: 'participant',
      deleteActivity: 'admin',
    },
    meals: {
      createMeal: 'admin',
      deleteMeal: 'admin',
      editMeal: 'admin',
      suggestRestaurant: 'admin',
      addContribution: 'participant',
      manageRecipe: 'chef',
    },
    shopping: {
      deleteCheckedItems: 'admin',
    },
    carpool: {
      proposeCarpool: 'participant',
      editCarpools: 'admin',
      updateShoppingMeetupPoint: 'admin',
    },
  };
}

function mergedTripPermissionsWithDefaults(existingPermissions) {
  const defaults = defaultTripPermissions();
  const base =
    existingPermissions &&
    typeof existingPermissions === 'object' &&
    !Array.isArray(existingPermissions)
      ? existingPermissions
      : {};

  /** @type {Record<string, unknown>} */
  const next = {};

  for (const [sectionKey, sectionDefaults] of Object.entries(defaults)) {
    const existingSection =
      base[sectionKey] &&
      typeof base[sectionKey] === 'object' &&
      !Array.isArray(base[sectionKey])
        ? base[sectionKey]
        : {};

    /** @type {Record<string, string>} */
    const mergedSection = {};
    for (const [actionKey, defaultRole] of Object.entries(sectionDefaults)) {
      const configured = normalizeString(existingSection[actionKey]);
      mergedSection[actionKey] = configured || defaultRole;
    }
    next[sectionKey] = mergedSection;
  }

  return next;
}

function tripPermissionsEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

async function userIsApplicationOwner(uid) {
  const snap = await admin.firestore().collection('users').doc(uid).get();
  return snap.exists && snap.data()?.isApplicationOwner === true;
}

async function assertTripParticipantPermission({
  tripData,
  uid,
  permissionKey,
  fallbackRole,
  deniedMessage,
}) {
  if (await userIsApplicationOwner(uid)) {
    return;
  }
  const memberUserIds = Array.isArray(tripData.memberUserIds)
    ? tripData.memberUserIds.map((v) => String(v))
    : [];
  if (!memberUserIds.includes(uid)) {
    throw new HttpsError('permission-denied', deniedMessage);
  }
  const minRole = tripParticipantPermissionMinRole(
    tripData,
    permissionKey,
    fallbackRole
  );
  if (tripCallerRoleRank(tripData, uid) < roleRank(minRole)) {
    throw new HttpsError('permission-denied', deniedMessage);
  }
}

function assertTripInviteToken(data, token) {
  const expectedToken = normalizeString(data.inviteToken);
  if (!expectedToken || expectedToken !== token) {
    throw new HttpsError(
      'permission-denied',
      'Lien d invitation invalide ou expire'
    );
  }
}


/**
 * @param {unknown} raw
 * @returns {string[]}
 */
function normalizedIdList(raw) {
  return (Array.isArray(raw) ? raw : [])
    .map((v) => String(v).trim())
    .filter((id) => id.length > 0);
}

/**
 * @param {unknown} raw
 * @param {string} memberId
 * @returns {boolean}
 */
function participantSharesContainsMember(raw, memberId) {
  return (
    raw &&
    typeof raw === 'object' &&
    !Array.isArray(raw) &&
    Object.prototype.hasOwnProperty.call(raw, memberId)
  );
}

/**
 * @param {FirebaseFirestore.QueryDocumentSnapshot[]} expenseDocs
 * @param {string} memberId
 */
function assertMemberNotUsedInExpenses(expenseDocs, memberId) {
  for (const doc of expenseDocs) {
    const exp = doc.data() || {};
    const participants = normalizedIdList(exp.participantIds);
    const paidBy = normalizeString(exp.paidBy);
    const inShares = participantSharesContainsMember(
      exp.participantShares,
      memberId
    );
    if (participants.includes(memberId) || paidBy === memberId || inShares) {
      throw new HttpsError(
        'failed-precondition',
        'Ce membre est encore utilisé dans des dépenses. Retire-le des dépenses avant de le supprimer.'
      );
    }
  }
}

/**
 * @param {FirebaseFirestore.QueryDocumentSnapshot[]} roomDocs
 * @param {string} memberId
 */
function assertMemberNotAssignedInRooms(roomDocs, memberId) {
  for (const doc of roomDocs) {
    const data = doc.data() || {};
    const bedsRaw = Array.isArray(data.beds) ? data.beds : [];
    for (const bed of bedsRaw) {
      if (!bed || typeof bed !== 'object') continue;
      const ids = normalizedIdList(bed.assignedMemberIds);
      if (ids.includes(memberId)) {
        throw new HttpsError(
          'failed-precondition',
          'Ce membre est encore assigné à une chambre. Retire son assignation avant de le supprimer.'
        );
      }
    }
  }
}

/**
 * @param {FirebaseFirestore.QueryDocumentSnapshot[]} mealDocs
 * @param {string} memberId
 */
function assertMemberNotUsedInMeals(mealDocs, memberId) {
  for (const doc of mealDocs) {
    const meal = doc.data() || {};
    const participants = normalizedIdList(meal.participantIds);
    const chefParticipantId = normalizeString(meal.chefParticipantId);
    if (participants.includes(memberId) || chefParticipantId === memberId) {
      throw new HttpsError(
        'failed-precondition',
        'Ce membre est encore affecté à un repas. Retire-le des repas avant de le supprimer.'
      );
    }
  }
}

/**
 * @param {FirebaseFirestore.QueryDocumentSnapshot[]} expenseGroupDocs
 * @param {string} memberId
 */
function assertMemberNotCreatorOfNonDefaultExpensePost(expenseGroupDocs, memberId) {
  for (const doc of expenseGroupDocs) {
    const data = doc.data() || {};
    const createdBy = normalizeString(data.createdBy);
    const isDefault = data.isDefault === true;
    if (!isDefault && createdBy === memberId) {
      throw new HttpsError(
        'failed-precondition',
        'Ce membre est créateur d\'un poste de dépense. Transfère ou supprime ce poste avant de le supprimer.'
      );
    }
  }
}

/**
 * @param {FirebaseFirestore.DocumentData} tripData
 * @param {string} memberId
 */
function assertMemberIsNotTripAdmin(tripData, memberId) {
  if (tripAdminMemberIdSet(tripData).has(memberId)) {
    throw new HttpsError(
      'failed-precondition',
      'Ce membre est administrateur du voyage. Rétrograde-le avant de le supprimer.'
    );
  }
}

/**
 * @param {FirebaseFirestore.QueryDocumentSnapshot[]} participantGroupDocs
 * @param {string} memberId
 */
function assertMemberNotInParticipantGroup(participantGroupDocs, memberId) {
  for (const doc of participantGroupDocs) {
    const data = doc.data() || {};
    const memberIds = normalizedIdList(data.memberIds);
    if (memberIds.includes(memberId)) {
      const label = normalizeString(data.label) || 'un groupe';
      throw new HttpsError(
        'failed-precondition',
        `Ce membre appartient au groupe "${label}". Retire-le du groupe avant de le supprimer du voyage.`
      );
    }
  }
}

/**
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} memberId
 * @param {FirebaseFirestore.DocumentData} tripData
 */
async function assertMemberRemovalBlockingDependencies({
  tripRef,
  memberId,
  tripData,
}) {
  const [expensesSnap, roomsSnap, mealsSnap, groupsSnap, participantGroupsSnap] = await Promise.all([
    tripRef.collection('expenses').get(),
    tripRef.collection('rooms').get(),
    tripRef.collection('meals').get(),
    tripRef.collection('expenseGroups').get(),
    tripRef.collection('participantGroups').get(),
  ]);
  assertMemberNotInParticipantGroup(participantGroupsSnap.docs, memberId);
  assertMemberNotUsedInExpenses(expensesSnap.docs, memberId);
  assertMemberNotAssignedInRooms(roomsSnap.docs, memberId);
  assertMemberNotUsedInMeals(mealsSnap.docs, memberId);
  assertMemberIsNotTripAdmin(tripData, memberId);
  assertMemberNotCreatorOfNonDefaultExpensePost(groupsSnap.docs, memberId);
}

/**
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} memberId
 */
async function cleanupNonBlockingMemberReferences(tripRef, memberId) {
  const db = admin.firestore();
  const [activitiesSnap, mealsSnap, shoppingSnap] = await Promise.all([
    tripRef.collection('activities').get(),
    tripRef.collection('meals').get(),
    tripRef.collection('shoppingItems').get(),
  ]);

  /** @type {{ ref: FirebaseFirestore.DocumentReference, data: Record<string, unknown> }[]} */
  const updates = [];

  for (const doc of activitiesSnap.docs) {
    const votes = normalizedIdList(doc.data().votes);
    if (!votes.includes(memberId)) continue;
    updates.push({
      ref: doc.ref,
      data: { votes: FieldValue.arrayRemove(memberId) },
    });
  }

  for (const doc of mealsSnap.docs) {
    const meal = doc.data() || {};
    const rawPotluckItems = Array.isArray(meal.potluckItems) ? meal.potluckItems : [];
    const nextPotluckItems = rawPotluckItems.filter((raw) => {
      if (!raw || typeof raw !== 'object') return true;
      const addedBy = normalizeString(raw.addedBy);
      return addedBy !== memberId;
    });
    if (nextPotluckItems.length === rawPotluckItems.length) continue;
    updates.push({
      ref: doc.ref,
      data: { potluckItems: nextPotluckItems },
    });
  }

  for (const doc of shoppingSnap.docs) {
    const claimedBy = normalizeString(doc.data().claimedBy);
    if (claimedBy !== memberId) continue;
    updates.push({
      ref: doc.ref,
      data: { claimedBy: FieldValue.delete() },
    });
  }

  let batch = db.batch();
  let n = 0;
  for (const { ref, data } of updates) {
    batch.update(ref, data);
    n++;
    if (n >= 450) {
      await batch.commit();
      batch = db.batch();
      n = 0;
    }
  }
  if (n > 0) {
    await batch.commit();
  }
}

/**
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @returns {Promise<FirebaseFirestore.QueryDocumentSnapshot | null>}
 */
async function getDefaultExpenseGroupDoc(tripRef) {
  const snap = await tripRef
    .collection('expenseGroups')
    .where('isDefault', '==', true)
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0];
}

/**
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} participantId TripMember doc id
 */
async function addParticipantIdToDefaultExpensePost(tripRef, participantId) {
  const defaultGroupDoc = await getDefaultExpenseGroupDoc(tripRef);
  if (!defaultGroupDoc) {
    return;
  }

  await defaultGroupDoc.ref.update({
    visibleToMemberIds: FieldValue.arrayUnion(participantId),
  });
}

/**
 * When someone joins the trip (memberUserIds), add their participant doc id to the
 * default expense post visibility only — not other posts, not existing expenses.
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} uid
 */
async function addTripMemberToDefaultExpensePost(tripRef, uid) {
  const participantsSnap = await tripRef
    .collection('participants')
    .where('userId', '==', uid)
    .limit(1)
    .get();
  if (participantsSnap.empty) {
    console.warn(
      'addTripMemberToDefaultExpensePost: no participant found for uid',
      uid,
      tripRef.id,
    );
    return;
  }
  await addParticipantIdToDefaultExpensePost(
    tripRef,
    participantsSnap.docs[0].id
  );
}

const FCM_INVALID_TOKEN_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

const TRIP_NOTIFICATION_CHANNELS = Object.freeze({
  MESSAGES: 'messages',
  ACTIVITIES: 'activities',
  ANNOUNCEMENTS: 'announcements',
  EXPENSES: 'expenses',
  CUPIDON: 'cupidon',
});

const ANDROID_CHANNEL_IDS = Object.freeze({
  messages: 'planerz_messages',
  activities: 'planerz_activities',
  announcements: 'planerz_announcements',
  expenses: 'planerz_expenses',
  cupidon: 'planerz_cupidon',
});

const CHANNEL_PRESENCE_MAX_AGE_MS = 120000;
const CUPIDON_MATCH_TYPE = 'cupidon_match';

function tripCounterRef(uid, tripId) {
  return admin
    .firestore()
    .collection('users')
    .doc(uid)
    .collection('tripNotificationCounters')
    .doc(tripId);
}

function tripPresenceRef(uid, tripId) {
  return admin
    .firestore()
    .collection('users')
    .doc(uid)
    .collection('tripNotificationPresence')
    .doc(tripId);
}

async function recipientsNotActivelyViewingChannel({
  tripId,
  recipients,
  channel,
}) {
  const nowMs = Date.now();
  const checks = recipients.map(async (uid) => {
    const cleanUid = normalizeString(uid);
    if (!cleanUid) return null;
    try {
      const snap = await tripPresenceRef(cleanUid, tripId).get();
      if (!snap.exists) return cleanUid;
      const data = snap.data() || {};
      const openChannel = normalizeString(data.openChannel);
      const updatedAt = data.updatedAt;
      const updatedAtMs =
        updatedAt instanceof Timestamp
          ? updatedAt.toMillis()
          : 0;
      const isFresh = nowMs - updatedAtMs <= CHANNEL_PRESENCE_MAX_AGE_MS;
      if (isFresh && openChannel === channel) {
        return null;
      }
      return cleanUid;
    } catch (e) {
      console.warn('recipientsNotActivelyViewingChannel', cleanUid, e);
      return cleanUid;
    }
  });
  const result = await Promise.all(checks);
  return result.filter((uid) => !!uid);
}

async function incrementTripUnreadCounters({ tripId, recipients, channel }) {
  if (!Array.isArray(recipients) || recipients.length === 0) return;
  let batch = admin.firestore().batch();
  let n = 0;
  for (const uid of recipients) {
    const cleanUid = normalizeString(uid);
    if (!cleanUid) continue;
    /** @type {Record<string, unknown>} */
    const payload = {
      channels: {
        [channel]: FieldValue.increment(1),
      },
      updatedAt: FieldValue.serverTimestamp(),
    };
    // Cupidon unread is shown on the profile only; do not bump trip-level total.
    if (channel !== TRIP_NOTIFICATION_CHANNELS.CUPIDON) {
      payload.total = FieldValue.increment(1);
    }
    batch.set(
      tripCounterRef(cleanUid, tripId),
      payload,
      { merge: true }
    );
    n++;
    if (n >= 400) {
      await batch.commit();
      batch = admin.firestore().batch();
      n = 0;
    }
  }
  if (n > 0) {
    await batch.commit();
  }
}

async function collectRecipientTokenEntries(db, recipients) {
  /** @type {{ token: string, ref: FirebaseFirestore.DocumentReference, platform: string }[]} */
  const tokenEntries = [];
  /** @type {Map<string, { ref: FirebaseFirestore.DocumentReference, platform: string }>} */
  const byToken = new Map();
  await Promise.all(
    [...new Set(recipients.map((uid) => normalizeString(uid)).filter(Boolean))].map(
      async (uid) => {
      try {
        const tokensSnap = await db
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .get();
        for (const doc of tokensSnap.docs) {
          const docData = doc.data() || {};
          const t = normalizeString(docData.token);
          if (t && !byToken.has(t)) {
            byToken.set(t, {
              ref: doc.ref,
              platform: normalizeString(docData.platform),
            });
          }
        }
      } catch (e) {
        console.warn('collectRecipientTokenEntries', uid, e);
      }
    })
  );
  for (const [token, entry] of byToken.entries()) {
    tokenEntries.push({
      token,
      ref: entry.ref,
      platform: entry.platform,
    });
  }
  return tokenEntries;
}

async function cleanupInvalidFcmTokens(db, sendResult, tokenEntries) {
  let batch = db.batch();
  let batchOps = 0;
  for (let i = 0; i < sendResult.responses.length; i++) {
    const r = sendResult.responses[i];
    if (r.success) continue;
    const code = r.error?.code || '';
    if (!FCM_INVALID_TOKEN_CODES.has(code)) continue;
    const ref = tokenEntries[i]?.ref;
    if (!ref) continue;
    batch.delete(ref);
    batchOps++;
    if (batchOps >= 400) {
      await batch.commit();
      batch = db.batch();
      batchOps = 0;
    }
  }
  if (batchOps > 0) {
    await batch.commit();
  }
}

/**
 * Deletes every object stored under `trips/{tripId}/` in default bucket.
 * Idempotent: ignores "not found" errors and continues best-effort.
 * @param {string} tripId
 */
async function deleteTripStorageObjects(tripId) {
  const cleanTripId = normalizeString(tripId);
  if (!cleanTripId) return;
  const bucket = admin.storage().bucket();
  const [files] = await bucket.getFiles({
    prefix: `trips/${cleanTripId}/`,
    autoPaginate: true,
  });
  if (!Array.isArray(files) || files.length === 0) {
    return;
  }
  await Promise.all(
    files.map(async (file) => {
      try {
        await file.delete();
      } catch (e) {
        const code = normalizeString(e?.code);
        if (code === '404' || code === 'not-found') {
          return;
        }
        throw e;
      }
    })
  );
}

function channelsMap(data) {
  if (!data || typeof data !== 'object') return {};
  const channels = data.channels;
  if (!channels || typeof channels !== 'object' || Array.isArray(channels)) {
    return {};
  }
  return channels;
}

/**
 * Trip list / shell badge total: messages + activities + announcements + expenses (Cupidon is profile-only).
 * @param {Record<string, unknown>} channels
 * @returns {number}
 */
function tripNotificationShellTotalFromChannels(channels) {
  if (!channels || typeof channels !== 'object') {
    return 0;
  }
  const msgsRaw = channels[TRIP_NOTIFICATION_CHANNELS.MESSAGES];
  const actsRaw = channels[TRIP_NOTIFICATION_CHANNELS.ACTIVITIES];
  const announcementsRaw = channels[TRIP_NOTIFICATION_CHANNELS.ANNOUNCEMENTS];
  const expensesRaw = channels[TRIP_NOTIFICATION_CHANNELS.EXPENSES];
  const msgs =
    typeof msgsRaw === 'number' ? msgsRaw : Number(msgsRaw) || 0;
  const acts =
    typeof actsRaw === 'number' ? actsRaw : Number(actsRaw) || 0;
  const announcements =
    typeof announcementsRaw === 'number'
      ? announcementsRaw
      : Number(announcementsRaw) || 0;
  const expenses =
    typeof expensesRaw === 'number' ? expensesRaw : Number(expensesRaw) || 0;
  return msgs + acts + announcements + expenses;
}

function channelReadTimestamp(data, channel) {
  const channels = channelsMap(data);
  const raw = channels[channel];
  if (raw instanceof Timestamp) {
    return raw;
  }
  return null;
}

async function countUnreadForChannel({ tripId, uid, channel, readAfter }) {
  const channelCollection =
    channel === TRIP_NOTIFICATION_CHANNELS.MESSAGES
      ? 'messages'
      : channel === TRIP_NOTIFICATION_CHANNELS.ACTIVITIES
      ? 'activities'
      : 'announcements';
  const actorField =
    channel === TRIP_NOTIFICATION_CHANNELS.ACTIVITIES ? 'createdBy' : 'authorId';
  const tripRef = admin.firestore().collection('trips').doc(tripId);

  const totalSnap = await tripRef
    .collection(channelCollection)
    .where('createdAt', '>', readAfter)
    .get();
  if (!uid) return totalSnap.size;

  let unread = 0;
  for (const doc of totalSnap.docs) {
    const data = doc.data() || {};
    const actorId = normalizeString(data[actorField]);
    if (!actorId || actorId !== uid) {
      unread++;
    }
  }
  return unread;
}

async function setTripChannelCounter({ tripId, uid, channel, value }) {
  const counterRef = tripCounterRef(uid, tripId);
  const snap = await counterRef.get();
  const prevData = snap.exists ? snap.data() || {} : {};
  const prevChannels = channelsMap(prevData);
  const nextChannels = { ...prevChannels, [channel]: value };
  const total = tripNotificationShellTotalFromChannels(nextChannels);
  await counterRef.set(
    {
      channels: nextChannels,
      total,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Shared trip notification payload contract used by Flutter/Web binders.
 * @param {{
 *   channel: string,
 *   tripId: string,
 *   actorId: string,
 *   type: string,
 *   targetPath: string,
 *   createdAt?: FirebaseFirestore.Timestamp,
 *   payload?: Record<string, string>,
 * }} event
 */
function buildTripNotificationEventData(event) {
  const data = {
    tripId: normalizeString(event.tripId),
    type: normalizeString(event.type),
    channel: normalizeString(event.channel),
    targetPath: normalizeString(event.targetPath),
    actorId: normalizeString(event.actorId),
    createdAtMs: String(
      event.createdAt instanceof Timestamp
        ? event.createdAt.toMillis()
        : Date.now()
    ),
  };
  if (event.payload && typeof event.payload === 'object') {
    for (const [k, v] of Object.entries(event.payload)) {
      const cleanK = normalizeString(k);
      const cleanV = normalizeString(v);
      if (!cleanK || !cleanV) continue;
      data[`payload_${cleanK}`] = cleanV;
    }
  }
  return data;
}

function cupidonLikeDocId(likerId, targetId) {
  return `${normalizeString(likerId)}__${normalizeString(targetId)}`;
}

function cupidonMatchDocId(tripId, uidA, uidB) {
  const ids = [normalizeString(uidA), normalizeString(uidB)].sort();
  return `${normalizeString(tripId)}__${ids[0]}__${ids[1]}`;
}

/**
 * Match doc ids are `${tripId}__${uidSmall}__${uidLarge}` (see cupidonMatchDocId).
 * Derives tripId when `tripId` field is missing or legacy data differs.
 * @param {string} matchDocId
 * @returns {string}
 */
function tripIdFromCupidonMatchDocId(matchDocId) {
  const clean = normalizeString(matchDocId);
  if (!clean) return '';
  const parts = clean.split('__').filter(Boolean);
  if (parts.length < 3) return '';
  return parts.slice(0, -2).join('__');
}

function hasCupidonEnabled(memberData) {
  return !!(memberData && memberData.cupidonEnabled === true);
}

function _dateKey(d) {
  const y = d.getFullYear().toString().padStart(4, '0');
  const m = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function _startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

/**
 * Builds the default stay fields for a new participant slot using the trip's calendar bounds.
 * Mirrors TripMemberStay.defaultForInviteContext() from the Flutter client.
 * @param {object} tripData - Firestore trip document data
 * @returns {object} Firestore-ready stay fields
 */
function defaultStayForTrip(tripData) {
  const parseDate = (raw) => {
    if (!raw) return null;
    const d = typeof raw.toDate === 'function' ? raw.toDate() : new Date(raw);
    if (isNaN(d.getTime())) return null;
    // Trip dates are stored as midnight local time (e.g. UTC+2), which arrives
    // as 22:00 UTC the day before on the server. Adding 12h normalises any
    // UTC offset up to ±12h before the day is extracted.
    return new Date(d.getTime() + 12 * 60 * 60 * 1000);
  };
  const tripStartDate = parseDate(tripData.startDate);
  const tripEndDate = parseDate(tripData.endDate);

  if (!tripStartDate && !tripEndDate) {
    const now = new Date();
    const start = _startOfDay(now);
    const end = new Date(start);
    end.setDate(end.getDate() + 1);
    return {
      stayStartDateKey: _dateKey(start),
      stayStartDayPart: 'evening',
      stayEndDateKey: _dateKey(end),
      stayEndDayPart: 'morning',
    };
  }

  const start = tripStartDate ? _startOfDay(tripStartDate) : _startOfDay(new Date());
  const end = tripEndDate ? _startOfDay(tripEndDate) : start;
  const later = end < start ? start : end;
  const isSingleDay = start.getTime() === later.getTime();
  return {
    stayStartDateKey: _dateKey(start),
    stayStartDayPart: isSingleDay ? 'morning' : 'evening',
    stayEndDateKey: _dateKey(later),
    stayEndDayPart: isSingleDay ? 'evening' : 'morning',
  };
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @param {string} tripId
 * @returns {Promise<number>}
 */
async function countUserCupidonMatchesForTrip(db, uid, tripId) {
  const cleanUid = normalizeString(uid);
  const cleanTripId = normalizeString(tripId);
  if (!cleanUid || !cleanTripId) return 0;

  const snap = await db
    .collection('users')
    .doc(cleanUid)
    .collection('cupidonMatches')
    .get();
  let n = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    let tid = normalizeString(data.tripId);
    if (!tid) {
      tid = tripIdFromCupidonMatchDocId(doc.id);
    }
    if (tid === cleanTripId) {
      n++;
    }
  }
  return n;
}

async function reconcileCupidonUnreadCounterForTrip(db, uid, tripId) {
  const cleanUid = normalizeString(uid);
  const cleanTripId = normalizeString(tripId);
  if (!cleanUid || !cleanTripId) return;

  const actualCupidonUnread = await countUserCupidonMatchesForTrip(
    db,
    cleanUid,
    cleanTripId
  );

  const ref = tripCounterRef(cleanUid, cleanTripId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    const channels = channelsMap(data);
    const merged = {
      ...channels,
      [TRIP_NOTIFICATION_CHANNELS.CUPIDON]: actualCupidonUnread,
    };
    const nextTotal = tripNotificationShellTotalFromChannels(merged);
    tx.set(
      ref,
      {
        channels: merged,
        total: nextTotal,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

/**
 * Removes the match from trip/users docs and clears cupidon unread counter
 * impact for both members.
 * @param {{
 *   db: FirebaseFirestore.Firestore,
 *   tripId: string,
 *   uidA: string,
 *   uidB: string,
 *   matchId: string,
 * }} params
 * @returns {Promise<boolean>} true when trip match doc existed and got removed
 */
async function removeCupidonMatchEverywhereAndCounters({
  db,
  tripId,
  uidA,
  uidB,
  matchId,
}) {
  const cleanTripId = normalizeString(tripId);
  const cleanA = normalizeString(uidA);
  const cleanB = normalizeString(uidB);
  const cleanMatchId = normalizeString(matchId);
  if (!cleanTripId || !cleanA || !cleanB || !cleanMatchId) {
    return false;
  }

  const tripMatchRef = db
    .collection('trips')
    .doc(cleanTripId)
    .collection('cupidonMatches')
    .doc(cleanMatchId);
  const userAMatchRef = db
    .collection('users')
    .doc(cleanA)
    .collection('cupidonMatches')
    .doc(cleanMatchId);
  const userBMatchRef = db
    .collection('users')
    .doc(cleanB)
    .collection('cupidonMatches')
    .doc(cleanMatchId);

  const removed = await db.runTransaction(async (tx) => {
    const tripMatchSnap = await tx.get(tripMatchRef);
    if (!tripMatchSnap.exists) {
      return false;
    }
    tx.delete(tripMatchRef);
    tx.delete(userAMatchRef);
    tx.delete(userBMatchRef);
    return true;
  });

  if (!removed) {
    // Self-heal partial states: user match docs may still exist even if trip doc
    // was already deleted by a prior operation.
    await Promise.all([userAMatchRef.delete(), userBMatchRef.delete()]);
  }

  await Promise.all([
    reconcileCupidonUnreadCounterForTrip(db, cleanA, cleanTripId),
    reconcileCupidonUnreadCounterForTrip(db, cleanB, cleanTripId),
  ]);

  return removed;
}

async function resolveTripMemberLabel(_tripData, uid) {
  try {
    const userRecord = await admin.auth().getUser(uid);
    return emailLocalPart(userRecord.email || '') || 'Utilisateur';
  } catch (e) {
    console.warn('resolveTripMemberLabel getUser', uid, e);
    return 'Utilisateur';
  }
}

/**
 * @param {Record<string, unknown>} tripData
 * @param {string} uid
 * @returns {Promise<{ label: string, photoUrl: string }>}
 */
async function resolveTripMemberProfile(tripData, uid) {
  const label = await resolveTripMemberLabel(tripData, uid);
  let photoUrl = '';
  try {
    const userSnap = await admin.firestore().collection('users').doc(uid).get();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const account =
      userData.account && typeof userData.account === 'object'
        ? userData.account
        : {};
    photoUrl = normalizeString(account.photoUrl) || normalizeString(userData.photoUrl);
  } catch (e) {
    console.warn('resolveTripMemberProfile user doc', uid, e);
  }
  return { label, photoUrl };
}

async function sendCupidonMatchPush({
  tripId,
  matchId,
  tripTitle,
  notifiedUid,
  otherLabel,
  otherPhotoUrl,
}) {
  const cleanTripId = normalizeString(tripId);
  const cleanMatchId = normalizeString(matchId);
  const cleanNotifiedUid = normalizeString(notifiedUid);
  const cleanTripTitle = normalizeString(tripTitle);
  const cleanOtherLabel = normalizeString(otherLabel);
  const cleanOtherPhotoUrl = normalizeString(otherPhotoUrl);
  if (!cleanTripId || !cleanMatchId || !cleanNotifiedUid) {
    return;
  }

  const db = admin.firestore();
  const docId = buildNotificationQueueDocId('cupidon_match', {
    tripId: cleanTripId,
    matchId: cleanMatchId,
    notifiedUid: cleanNotifiedUid,
  });
  await enqueueTripNotification(db, {
    docId,
    payload: {
      channel: TRIP_NOTIFICATION_CHANNELS.CUPIDON,
      type: CUPIDON_MATCH_TYPE,
      tripId: cleanTripId,
      actorId: cleanNotifiedUid,
      targetPath: '/account/cupidon',
      title: `Mode Cupidon · ${cleanTripTitle || 'Voyage'}`,
      body: `Match mutuel avec ${cleanOtherLabel || "quelqu'un"}`,
      candidateRecipients: [cleanNotifiedUid],
      skipPresenceCheck: true,
      androidChannelId: ANDROID_CHANNEL_IDS.cupidon,
      payload: {
        tripTitle: cleanTripTitle,
        otherLabel: cleanOtherLabel,
        ...(cleanOtherPhotoUrl ? { otherPhotoUrl: cleanOtherPhotoUrl } : {}),
      },
    },
  });
}

/**
 * Generic notification dispatcher. Atomically claims a notificationQueue document,
 * applies presence filtering (when applicable), increments per-trip unread
 * counters, and delivers FCM messages to all eligible recipient tokens.
 */
exports.dispatchNotificationQueue = onDocumentCreated(
  {
    document: 'notificationQueue/{notifId}',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const db = admin.firestore();
    const data = await claimAndDeleteNotificationQueueDoc(db, snap.ref);
    if (!data) return;

    const channel = normalizeString(data.channel);
    const type = normalizeString(data.type);
    const tripId = normalizeString(data.tripId);
    const actorId = normalizeString(data.actorId);
    const targetPath = normalizeString(data.targetPath);
    const title = normalizeString(data.title);
    const body = normalizeString(data.body);
    const candidateRecipients = Array.isArray(data.candidateRecipients)
      ? data.candidateRecipients.map((v) => String(v)).filter(Boolean)
      : [];
    const skipPresenceCheck = data.skipPresenceCheck === true;
    const androidChannelId = normalizeString(data.androidChannelId);
    const payload =
      data.payload && typeof data.payload === 'object' ? data.payload : {};

    if (!channel || !type || !title || candidateRecipients.length === 0) {
      return;
    }

    const recipients =
      skipPresenceCheck || !tripId
        ? candidateRecipients
        : await recipientsNotActivelyViewingChannel({
            tripId,
            recipients: candidateRecipients,
            channel,
          });

    if (recipients.length > 0 && tripId) {
      await incrementTripUnreadCounters({ tripId, recipients, channel });
    }

    const tokenEntries = await collectRecipientTokenEntries(db, recipients);
    if (tokenEntries.length > 0) {
      const createdAt =
        data.createdAt instanceof Timestamp
          ? data.createdAt
          : undefined;

      const messages = tokenEntries.map(({ token, platform }) => {
        const eventData = buildTripNotificationEventData({
          channel,
          tripId,
          actorId,
          type,
          targetPath,
          createdAt,
          payload,
        });
        // Web/PWA: data-only so FCM does not auto-display AND the SW does not
        // double-show (notification payload + manual showNotification).
        if (platform === 'web') {
          return {
            token,
            data: {
              ...eventData,
              title,
              body,
            },
          };
        }
        /** @type {admin.messaging.Message} */
        const msg = {
          token,
          notification: { title, body },
          data: eventData,
        };
        if (androidChannelId) {
          msg.android = { notification: { channelId: androidChannelId } };
        }
        return msg;
      });

      const result = await admin.messaging().sendEach(messages);
      await cleanupInvalidFcmTokens(db, result, tokenEntries);
    }
  }
);

/**
 * Sends a push notification to other trip members when a message is created.
 * Tokens live under users/{uid}/fcmTokens (written by the Flutter app).
 */
exports.notifyTripMessageRecipients = onDocumentCreated(
  {
    document: 'trips/{tripId}/messages/{messageId}',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const tripId = event.params.tripId;
    const messageId = event.params.messageId;
    const msg = snap.data() || {};
    const authorId = normalizeString(msg.authorId);
    const isImageMessage = normalizeString(msg.type) === 'image';
    const text = isImageMessage
      ? normalizeString(msg.text).slice(0, 180)
      : normalizeString(msg.text).slice(0, 180);

    if (!authorId) return;
    if (!text && !isImageMessage) return;

    const db = admin.firestore();
    const tripSnap = await db.collection('trips').doc(tripId).get();
    if (!tripSnap.exists) return;

    const trip = tripSnap.data() || {};
    const memberIds = Array.isArray(trip.memberUserIds)
      ? trip.memberUserIds.map((v) => String(v))
      : [];
    const threadType = normalizeString(msg.threadType);
    const visibilityType = normalizeString(msg.visibilityType);
    const isAdminsOnlyMessage =
      threadType === 'admin' || visibilityType === 'admins_only';

    const candidateRecipients = memberIds.filter((id) => {
      const cleanId = normalizeString(id);
      if (!cleanId || cleanId === authorId) return false;
      if (!isAdminsOnlyMessage) return true;
      return isTripAdminUser(trip, cleanId);
    });
    if (candidateRecipients.length === 0) return;

    const tripTitle = normalizeString(trip.title) || 'Voyage';
    let authorLabel = await resolveTripMemberLabel(trip, authorId);
    if (!authorLabel) authorLabel = "Quelqu'un";

    const docId = buildNotificationQueueDocId('trip_message', { tripId, messageId });
    await enqueueTripNotification(db, {
      docId,
      payload: {
        channel: TRIP_NOTIFICATION_CHANNELS.MESSAGES,
        type: 'trip_message',
        tripId,
        actorId: authorId,
        targetPath: isAdminsOnlyMessage
          ? `/trips/${tripId}/messages/admin`
          : `/trips/${tripId}/messages`,
        title: isAdminsOnlyMessage
          ? `Messagerie admin · ${tripTitle}`
          : `Messagerie · ${tripTitle}`,
        body: isImageMessage
          ? (text ? `${authorLabel} : ${text}` : `${authorLabel} a envoyé une photo`)
          : `${authorLabel} : ${text}`,
        candidateRecipients,
        skipPresenceCheck: false,
        androidChannelId: ANDROID_CHANNEL_IDS.messages,
        payload: {},
      },
    });
  }
);

exports.notifyTripActivityRecipients = onDocumentCreated(
  {
    document: 'trips/{tripId}/activities/{activityId}',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const tripId = event.params.tripId;
    const activityId = event.params.activityId;
    const activity = snap.data() || {};
    const actorId = normalizeString(activity.createdBy);
    const label = normalizeString(activity.label).slice(0, 180);
    if (!actorId || !label) return;

    const db = admin.firestore();
    const tripSnap = await db.collection('trips').doc(tripId).get();
    if (!tripSnap.exists) return;

    const trip = tripSnap.data() || {};
    const memberIds = Array.isArray(trip.memberUserIds)
      ? trip.memberUserIds.map((v) => String(v))
      : [];
    const candidateRecipients = memberIds.filter((id) => id && id !== actorId);
    if (candidateRecipients.length === 0) return;

    const tripTitle = normalizeString(trip.title) || 'Voyage';
    let actorLabel = await resolveTripMemberLabel(trip, actorId);
    if (!actorLabel) actorLabel = "Quelqu'un";

    const docId = buildNotificationQueueDocId('trip_activity', { tripId, activityId });
    await enqueueTripNotification(db, {
      docId,
      payload: {
        channel: TRIP_NOTIFICATION_CHANNELS.ACTIVITIES,
        type: 'trip_activity',
        tripId,
        actorId,
        targetPath: `/trips/${tripId}/activities`,
        title: `Activités · ${tripTitle}`,
        body: `${actorLabel} a proposé : ${label}`,
        candidateRecipients,
        skipPresenceCheck: false,
        androidChannelId: ANDROID_CHANNEL_IDS.activities,
        payload: {},
      },
    });
  }
);

exports.notifyTripAnnouncementRecipients = onDocumentCreated(
  {
    document: 'trips/{tripId}/announcements/{announcementId}',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const tripId = event.params.tripId;
    const announcementId = event.params.announcementId;
    const announcement = snap.data() || {};
    const actorId = normalizeString(announcement.authorId);
    const text = normalizeString(announcement.text).slice(0, 180);
    if (!actorId || !text) return;

    const db = admin.firestore();
    const tripSnap = await db.collection('trips').doc(tripId).get();
    if (!tripSnap.exists) return;

    const trip = tripSnap.data() || {};
    const memberIds = Array.isArray(trip.memberUserIds)
      ? trip.memberUserIds.map((v) => String(v))
      : [];
    const candidateRecipients = memberIds.filter((id) => id && id !== actorId);
    if (candidateRecipients.length === 0) return;

    const tripTitle = normalizeString(trip.title) || 'Voyage';
    let actorLabel = await resolveTripMemberLabel(trip, actorId);
    if (!actorLabel) actorLabel = "Quelqu'un";

    const docId = buildNotificationQueueDocId('trip_announcement', {
      tripId,
      announcementId,
    });
    await enqueueTripNotification(db, {
      docId,
      payload: {
        channel: TRIP_NOTIFICATION_CHANNELS.ANNOUNCEMENTS,
        type: 'trip_announcement',
        tripId,
        actorId,
        targetPath: `/trips/${tripId}/announcements`,
        title: `Annonces · ${tripTitle}`,
        body: `${actorLabel} : ${text}`,
        candidateRecipients,
        skipPresenceCheck: false,
        androidChannelId: ANDROID_CHANNEL_IDS.announcements,
        payload: {},
      },
    });
  }
);

exports.syncTripUnreadCountersFromReadState = onDocumentWritten(
  {
    document: 'trips/{tripId}/notificationReads/{userId}',
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (event) => {
    const afterSnap = event.data.after;
    if (!afterSnap.exists) {
      return;
    }
    const beforeSnap = event.data.before;
    const tripId = event.params.tripId;
    const userId = event.params.userId;

    const watchedChannels = [
      TRIP_NOTIFICATION_CHANNELS.MESSAGES,
      TRIP_NOTIFICATION_CHANNELS.ACTIVITIES,
      TRIP_NOTIFICATION_CHANNELS.ANNOUNCEMENTS,
      TRIP_NOTIFICATION_CHANNELS.EXPENSES,
    ];
    for (const channel of watchedChannels) {
      const beforeTs = beforeSnap.exists
        ? channelReadTimestamp(beforeSnap.data() || {}, channel)
        : null;
      const afterTs = channelReadTimestamp(afterSnap.data() || {}, channel);
      const beforeMillis = beforeTs ? beforeTs.toMillis() : 0;
      const afterMillis = afterTs ? afterTs.toMillis() : 0;
      if (beforeMillis === afterMillis) {
        continue;
      }
      if (channel === TRIP_NOTIFICATION_CHANNELS.EXPENSES) {
        await setTripChannelCounter({
          tripId,
          uid: userId,
          channel,
          value: 0,
        });
        continue;
      }
      const readAfter =
        afterTs || Timestamp.fromMillis(0);
      const unread = await countUnreadForChannel({
        tripId,
        uid: userId,
        channel,
        readAfter,
      });
      await setTripChannelCounter({
        tripId,
        uid: userId,
        channel,
        value: unread,
      });
    }
  }
);

exports.resyncMyTripUnreadCounters = onCall(
  {
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const db = admin.firestore();
    const countersSnap = await db
      .collection('users')
      .doc(uid)
      .collection('tripNotificationCounters')
      .get();
    const memberTripsSnap = await db
      .collection('trips')
      .where('memberUserIds', 'array-contains', uid)
      .get();

    const watchedChannels = [
      TRIP_NOTIFICATION_CHANNELS.MESSAGES,
      TRIP_NOTIFICATION_CHANNELS.ACTIVITIES,
      TRIP_NOTIFICATION_CHANNELS.ANNOUNCEMENTS,
    ];
    const memberTripIds = new Set(memberTripsSnap.docs.map((doc) => doc.id));

    // Remove stale counters from trips the user no longer belongs to.
    let deleteBatch = db.batch();
    let deleteOps = 0;
    for (const counterDoc of countersSnap.docs) {
      if (memberTripIds.has(counterDoc.id)) {
        continue;
      }
      deleteBatch.delete(counterDoc.ref);
      deleteOps++;
      if (deleteOps >= 400) {
        await deleteBatch.commit();
        deleteBatch = db.batch();
        deleteOps = 0;
      }
    }
    if (deleteOps > 0) {
      await deleteBatch.commit();
    }

    for (const tripDoc of memberTripsSnap.docs) {
      const tripId = tripDoc.id;
      const readSnap = await db
        .collection('trips')
        .doc(tripId)
        .collection('notificationReads')
        .doc(uid)
        .get();
      const readData = readSnap.exists ? readSnap.data() || {} : {};

      for (const channel of watchedChannels) {
        const readAfter =
          channelReadTimestamp(readData, channel) ||
          Timestamp.fromMillis(0);
        const unread = await countUnreadForChannel({
          tripId,
          uid,
          channel,
          readAfter,
        });
        await setTripChannelCounter({
          tripId,
          uid,
          channel,
          value: unread,
        });
      }
    }

    for (const tripDoc of memberTripsSnap.docs) {
      await reconcileCupidonUnreadCounterForTrip(db, uid, tripDoc.id);
    }

    return { ok: true, tripCount: memberTripsSnap.size };
  }
);

/**
 * Realigns `channels.cupidon` + `total` for every trip counter doc from real
 * `users/{uid}/cupidonMatches` counts (fixes ghost counters after partial deletes).
 */
exports.reconcileMyCupidonNotificationCounters = onCall(
  {
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const db = admin.firestore();
    const matchesSnap = await db
      .collection('users')
      .doc(uid)
      .collection('cupidonMatches')
      .get();

    /** @type {Map<string, number>} */
    const byTrip = new Map();
    for (const doc of matchesSnap.docs) {
      const data = doc.data() || {};
      let tid = normalizeString(data.tripId);
      if (!tid) {
        tid = tripIdFromCupidonMatchDocId(doc.id);
      }
      if (!tid) {
        continue;
      }
      byTrip.set(tid, (byTrip.get(tid) || 0) + 1);
    }

    const countersSnap = await db
      .collection('users')
      .doc(uid)
      .collection('tripNotificationCounters')
      .get();

    let batch = db.batch();
    let ops = 0;
    let docsUpdated = 0;

    for (const doc of countersSnap.docs) {
      const tripId = doc.id;
      const actual = byTrip.get(tripId) ?? 0;
      const data = doc.data() || {};
      const channels = channelsMap(data);
      const prevRaw = channels[TRIP_NOTIFICATION_CHANNELS.CUPIDON];
      const prev =
        typeof prevRaw === 'number' ? prevRaw : Number(prevRaw) || 0;

      const totalRaw = data.total;
      const total = typeof totalRaw === 'number' ? totalRaw : Number(totalRaw) || 0;
      const nextTotal = tripNotificationShellTotalFromChannels(channels);

      if (prev === actual && total === nextTotal) {
        continue;
      }

      docsUpdated++;
      batch.set(
        doc.ref,
        {
          channels: {
            ...channels,
            [TRIP_NOTIFICATION_CHANNELS.CUPIDON]: actual,
          },
          total: nextTotal,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }

    if (ops > 0) {
      await batch.commit();
    }

    return {
      ok: true,
      counterDocs: countersSnap.size,
      matchDocs: matchesSnap.size,
      docsUpdated,
    };
  }
);

exports.backfillNewTripMemberInExpenses = onDocumentUpdated(
  {
    document: 'trips/{tripId}',
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (event) => {
    const beforeSnap = event.data.before;
    const afterSnap = event.data.after;
    if (!afterSnap.exists) return;

    const beforeIds = beforeSnap.exists
      ? memberUserIdsAsSet(beforeSnap.data() || {})
      : new Set();
    const afterIds = memberUserIdsAsSet(afterSnap.data() || {});

    const added = [...afterIds].filter((id) => !beforeIds.has(id));
    const removed = [...beforeIds].filter((id) => !afterIds.has(id));
    if (added.length === 0 && removed.length === 0) return;

    const tripRef = afterSnap.ref;

    for (const uid of added) {
      try {
        await addTripMemberToDefaultExpensePost(tripRef, uid);
      } catch (e) {
        console.error(
          'backfillNewTripMemberInExpenses: default post visibility failed',
          tripRef.id,
          uid,
          e
        );
        throw e;
      }
    }

    // Keep meals consistent when members are removed from trip.memberUserIds.
    if (removed.length === 0) return;

    const db = admin.firestore();
    const mealsSnap = await tripRef.collection('meals').get();
    if (mealsSnap.empty) return;
    const removedSet = new Set(removed);
    let batch = db.batch();
    let n = 0;
    for (const doc of mealsSnap.docs) {
      const meal = doc.data() || {};
      const participants = (
        Array.isArray(meal.participantIds) ? meal.participantIds : []
      )
        .map((v) => String(v).trim())
        .filter((id) => id.length > 0);
      const chefParticipantId = normalizeString(meal.chefParticipantId);
      const newParticipants = [
        ...new Set(participants.filter((id) => !removedSet.has(id))),
      ];
      const newChefParticipantId = newParticipants.includes(chefParticipantId)
        ? chefParticipantId
        : null;
      const participantsChanged =
        newParticipants.length !== participants.length ||
        newParticipants.some((id, idx) => id !== participants[idx]);
      const chefChanged = newChefParticipantId !== chefParticipantId;
      if (!participantsChanged && !chefChanged) {
        continue;
      }

      batch.update(doc.ref, {
        participantIds: newParticipants,
        chefParticipantId: newChefParticipantId,
        updatedAt: FieldValue.serverTimestamp(),
      });
      n++;
      if (n >= 450) {
        await batch.commit();
        batch = db.batch();
        n = 0;
      }
    }
    if (n > 0) {
      await batch.commit();
    }
  }
);

/**
 * When trip-level Cupidon mode is disabled by an admin/owner, force-disable
 * per-member Cupidon preferences so participant settings stay consistent.
 */
exports.disableTripCupidonForAllMembers = onDocumentUpdated(
  {
    document: 'trips/{tripId}',
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const wasEnabled = before.cupidonModeEnabled !== false;
    const isEnabled = after.cupidonModeEnabled !== false;
    if (!wasEnabled || isEnabled) {
      return;
    }

    const tripRef = event.data.after.ref;
    const membersSnap = await tripRef
      .collection('participants')
      .where('cupidonEnabled', '==', true)
      .get();
    if (membersSnap.empty) {
      return;
    }

    const db = admin.firestore();
    let batch = db.batch();
    let writeCount = 0;
    for (const memberDoc of membersSnap.docs) {
      batch.update(memberDoc.ref, {
        cupidonEnabled: false,
        cupidonUpdatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      writeCount++;
      if (writeCount >= 450) {
        await batch.commit();
        batch = db.batch();
        writeCount = 0;
      }
    }
    if (writeCount > 0) {
      await batch.commit();
    }
  }
);

/**
 * Shared logic: fetch and store a link preview on any Firestore document.
 * @param {FirebaseFirestore.DocumentReference} docRef
 * @param {string} beforeUrlRaw
 * @param {string} afterUrlRaw
 * @param {string} previewField  Firestore field name to write the preview into.
 */
async function generateLinkPreview(docRef, beforeUrlRaw, afterUrlRaw, previewField) {
  const beforeUrl = normalizeString(beforeUrlRaw);
  const afterUrl = normalizeString(afterUrlRaw);

  if (beforeUrl === afterUrl) return;

  if (!afterUrl) {
    await docRef.set(
      { [previewField]: FieldValue.delete() },
      { merge: true }
    );
    return;
  }

  const parsed = safeUrl(afterUrl);
  if (!parsed) {
    await docRef.set(
      {
        [previewField]: {
          status: 'error',
          url: afterUrl,
          error: 'invalid_url',
          isGoogleMaps: false,
          fetchedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );
    return;
  }

  await docRef.set(
    {
      [previewField]: {
        status: 'loading',
        url: parsed.toString(),
        isGoogleMaps: isGoogleMapsUrl(parsed),
        fetchedAt: FieldValue.serverTimestamp(),
      },
    },
    { merge: true }
  );

  try {
    const { html, finalUrl } = await fetchHtml(parsed);

    // Guard: document may have been deleted while fetching (cancelled creation).
    if (!(await docRef.get()).exists) return;

    const preview = parsePreviewFromHtml(finalUrl, html);

    if (isGoogleMapsUrl(finalUrl)) {
      const maps = extractGoogleMapsPreview(finalUrl);
      const enriched = await enrichWithGooglePlaces(
        maps.title || preview.title,
        maps.lat,
        maps.lng
      );
      if (enriched) {
        if (enriched.title) preview.title = enriched.title;
        if (enriched.description) preview.description = enriched.description;
        if (enriched.imageUrl) preview.imageUrl = enriched.imageUrl;
      }
    }

    const hasSomething =
      preview.title || preview.description || preview.imageUrl || preview.siteName;

    await docRef.set(
      {
        [previewField]: {
          status: hasSomething ? 'ok' : 'empty',
          url: finalUrl.toString(),
          title: preview.title,
          description: preview.description,
          siteName: preview.siteName,
          imageUrl: preview.imageUrl,
          isGoogleMaps: isGoogleMapsUrl(finalUrl),
          fetchedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );
  } catch (e) {
    await docRef.set(
      {
        [previewField]: {
          status: 'error',
          url: parsed.toString(),
          error: String(e),
          isGoogleMaps: isGoogleMapsUrl(parsed),
          fetchedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );
  }
}

exports.generateTripLinkPreview = onDocumentUpdated(
  { document: 'trips/{tripId}', timeoutSeconds: 30, memory: '256MiB', secrets: ['GOOGLE_PLACES_API_KEY'] },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    await generateLinkPreview(
      event.data.after.ref,
      before.linkUrl,
      after.linkUrl,
      'linkPreview'
    );
  }
);

exports.generateTripShoppingMeetupLinkPreview = onDocumentUpdated(
  {
    document: 'trips/{tripId}/sections/carpoolShoppingMeetup',
    timeoutSeconds: 30,
    memory: '256MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    await generateLinkPreview(
      event.data.after.ref,
      before.shoppingMeetupLinkUrl,
      after.shoppingMeetupLinkUrl,
      'shoppingMeetupLinkPreview'
    );
  }
);

exports.generateActivityLinkPreview = onDocumentUpdated(
  {
    document: 'trips/{tripId}/activities/{activityId}',
    timeoutSeconds: 30,
    memory: '256MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    await generateLinkPreview(
      event.data.after.ref,
      before.linkUrl,
      after.linkUrl,
      'linkPreview'
    );
  }
);

exports.generateMealLinkPreview = onDocumentUpdated(
  {
    document: 'trips/{tripId}/meals/{mealId}',
    timeoutSeconds: 30,
    memory: '256MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    await generateLinkPreview(
      event.data.after.ref,
      before.restaurantUrl,
      after.restaurantUrl,
      'restaurantLinkPreview'
    );
  }
);

exports.generateTripLinkPreviewOnCreate = onDocumentCreated(
  { document: 'trips/{tripId}', timeoutSeconds: 30, memory: '256MiB', secrets: ['GOOGLE_PLACES_API_KEY'] },
  async (event) => {
    const data = event.data.data() || {};
    await generateLinkPreview(event.data.ref, undefined, data.linkUrl, 'linkPreview');
  }
);

exports.generateTripShoppingMeetupLinkPreviewOnCreate = onDocumentCreated(
  {
    document: 'trips/{tripId}/sections/carpoolShoppingMeetup',
    timeoutSeconds: 30,
    memory: '256MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    const data = event.data.data() || {};
    await generateLinkPreview(
      event.data.ref,
      undefined,
      data.shoppingMeetupLinkUrl,
      'shoppingMeetupLinkPreview'
    );
  }
);

exports.generateActivityLinkPreviewOnCreate = onDocumentCreated(
  {
    document: 'trips/{tripId}/activities/{activityId}',
    timeoutSeconds: 30,
    memory: '256MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    const data = event.data.data() || {};
    await generateLinkPreview(event.data.ref, undefined, data.linkUrl, 'linkPreview');
  }
);

exports.generateMealLinkPreviewOnCreate = onDocumentCreated(
  {
    document: 'trips/{tripId}/meals/{mealId}',
    timeoutSeconds: 30,
    memory: '256MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    const data = event.data.data() || {};
    await generateLinkPreview(event.data.ref, undefined, data.restaurantUrl, 'restaurantLinkPreview');
  }
);

exports.generateTripBoardGameLinkPreview = onDocumentUpdated(
  {
    document: 'trips/{tripId}/boardGames/{gameId}',
    timeoutSeconds: 30,
    memory: '256MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    await generateLinkPreview(
      event.data.after.ref,
      before.linkUrl,
      after.linkUrl,
      'linkPreview'
    );
  }
);

exports.generateTripBoardGameLinkPreviewOnCreate = onDocumentCreated(
  {
    document: 'trips/{tripId}/boardGames/{gameId}',
    timeoutSeconds: 30,
    memory: '256MiB',
    secrets: ['GOOGLE_PLACES_API_KEY'],
  },
  async (event) => {
    const data = event.data.data() || {};
    await generateLinkPreview(event.data.ref, undefined, data.linkUrl, 'linkPreview');
  }
);

/**
 * Adds [uid] to trip members if [token] matches the trip inviteToken.
 * When the trip still has placeholder members, [placeholderMemberId] must name
 * the placeholder row to claim (replaced by [uid]), unless
 * [bypassPlaceholderChoice] is true.
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} uid
 * @param {string} token
 * @param {string} placeholderMemberId
 * @param {boolean} bypassPlaceholderChoice
 */
async function completeJoinTripWithInvite(
  tripRef,
  uid,
  token,
  participantSlotId,
  bypassParticipantChoice,
  newParticipantName,
  useProfileNameForJoin
) {
  const slotArg = normalizeString(participantSlotId);
  const bypass = bypassParticipantChoice === true;
  const db = admin.firestore();

  // Validate token and check membership outside the transaction first.
  const [tripSnap, participantsSnap] = await Promise.all([
    tripRef.get(),
    tripRef.collection('participants').get(),
  ]);
  if (!tripSnap.exists) {
    throw new HttpsError('not-found', 'Voyage introuvable');
  }
  const data = tripSnap.data() || {};
  assertTripInviteToken(data, token);

  const memberUserIds = Array.isArray(data.memberUserIds)
    ? data.memberUserIds.map((v) => String(v))
    : [];
  if (memberUserIds.includes(uid)) {
    return;
  }

  const unclaimedSlots = participantsSnap.docs.filter((d) => {
    const userId = normalizeString(d.data().userId);
    const isChild = d.data().isChild === true;
    return !userId && !isChild;
  });

  let claimedParticipantRef = null;

  if (unclaimedSlots.length > 0 && !bypass) {
    if (!slotArg) {
      throw new HttpsError(
        'invalid-argument',
        'Choisis un voyageur prévu sur la liste pour rejoindre ce voyage.'
      );
    }
    const slotDoc = participantsSnap.docs.find((d) => d.id === slotArg);
    if (!slotDoc || normalizeString(slotDoc.data().userId)) {
      throw new HttpsError(
        'failed-precondition',
        'Ce voyageur a déjà été choisi ou est introuvable.'
      );
    }
    if (slotDoc.data().isChild === true) {
      throw new HttpsError(
        'failed-precondition',
        'Ce voyageur prévu est un enfant et ne peut pas être associé à un compte.'
      );
    }
    claimedParticipantRef = slotDoc.ref;
  }

  // Claim an existing slot or create a new participant document.
  if (claimedParticipantRef) {
    await claimedParticipantRef.update({ userId: uid });
  } else {
    const participantName = assertParticipantNameForNewJoin(newParticipantName);
    const defaultStay = defaultStayForTrip(data);
    const newParticipantDoc = {
      participantName,
      userId: uid,
      ...defaultStay,
      cupidonEnabled: false,
      phoneVisibility: 'nobody',
      createdAt: FieldValue.serverTimestamp(),
    };
    if (useProfileNameForJoin === true) {
      newParticipantDoc.useProfileName = true;
    }
    await tripRef.collection('participants').add(newParticipantDoc);
  }

  await tripRef.update({
    memberUserIds: FieldValue.arrayUnion(uid),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

exports.getInviteJoinContext = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripIdIn = normalizeString(request.data?.tripId);
    const token = normalizeString(request.data?.token);
    if (!token) {
      throw new HttpsError('invalid-argument', 'Invitation invalide');
    }

    const db = admin.firestore();

    let tripRef;
    if (tripIdIn) {
      tripRef = db.collection('trips').doc(tripIdIn);
    } else {
      const q = await db
        .collection('trips')
        .where('inviteToken', '==', token)
        .limit(2)
        .get();

      if (q.empty) {
        throw new HttpsError('not-found', 'Code d invitation inconnu');
      }
      if (q.size > 1) {
        console.error('getInviteJoinContext duplicate token', token);
        throw new HttpsError('internal', 'Erreur serveur');
      }
      tripRef = q.docs[0].ref;
    }

    const snap = await tripRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const data = snap.data() || {};
    assertTripInviteToken(data, token);

    const memberUserIds = Array.isArray(data.memberUserIds)
      ? data.memberUserIds.map((v) => String(v))
      : [];
    if (memberUserIds.includes(uid)) {
      return { tripId: tripRef.id, alreadyMember: true };
    }

    const participantsSnap = await tripRef.collection('participants').get();
    const unclaimedSlots = participantsSnap.docs
      .filter((d) => {
        const userId = normalizeString(d.data().userId);
        const isChild = d.data().isChild === true;
        return !userId && !isChild;
      })
      .map((d) => ({
        id: d.id,
        displayName: normalizeString(d.data().participantName) || 'Voyageur',
      }));

    const startTs = data.startDate;
    const endTs = data.endDate;
    const tripStartDate =
      startTs && typeof startTs.toDate === 'function'
        ? startTs.toDate().toISOString()
        : null;
    const tripEndDate =
      endTs && typeof endTs.toDate === 'function'
        ? endTs.toDate().toISOString()
        : null;

    return {
      tripId: tripRef.id,
      tripTitle: normalizeString(data.title) || 'Voyage',
      participants: unclaimedSlots,
      requiresParticipantChoice: unclaimedSlots.length > 0,
      cupidonModeEnabled: data.cupidonModeEnabled !== false,
      tripStartDate,
      tripEndDate,
    };
  }
);

exports.addTripParticipant = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const participantName = normalizeString(request.data?.participantName);
    const isChild = request.data?.isChild === true;
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }
    if (!participantName) {
      throw new HttpsError('invalid-argument', 'Nom obligatoire');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const tripData = tripSnap.data() || {};
    await assertTripParticipantPermission({
      tripData,
      uid,
      permissionKey: 'manageParticipants',
      fallbackRole: 'owner',
      deniedMessage: 'Droits insuffisants pour ajouter un voyageur prévu.',
    });

    const defaultStay = defaultStayForTrip(tripData);
    const participantDoc = {
      participantName,
      ...defaultStay,
      cupidonEnabled: false,
      phoneVisibility: 'nobody',
      createdAt: FieldValue.serverTimestamp(),
    };
    if (isChild) {
      participantDoc.isChild = true;
    }
    const participantRef = await tripRef.collection('participants').add(participantDoc);
    const participantId = participantRef.id;
    if (!isChild) {
      await addParticipantIdToDefaultExpensePost(tripRef, participantId);
    }

    return { ok: true, participantId };
  }
);

exports.removeTripParticipant = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const participantId = normalizeString(request.data?.participantId);
    if (!tripId || !participantId) {
      throw new HttpsError('invalid-argument', 'Parametres invalides');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const [tripSnap, participantSnap] = await Promise.all([
      tripRef.get(),
      tripRef.collection('participants').doc(participantId).get(),
    ]);
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    if (!participantSnap.exists) {
      throw new HttpsError('not-found', 'Participant introuvable');
    }

    const data = tripSnap.data() || {};
    await assertTripParticipantPermission({
      tripData: data,
      uid,
      permissionKey: 'manageParticipants',
      fallbackRole: 'owner',
      deniedMessage: 'Droits insuffisants pour retirer ce voyageur prévu.',
    });

    const participantData = participantSnap.data() || {};
    const claimedUserId = normalizeString(participantData.userId);
    const ownerId = normalizeString(data.ownerId);

    if (claimedUserId && claimedUserId === ownerId) {
      throw new HttpsError('permission-denied', 'Le créateur du voyage ne peut pas être retiré.');
    }

    await assertMemberRemovalBlockingDependencies({
      tripRef,
      memberId: participantId,
      tripData: data,
    });
    await cleanupNonBlockingMemberReferences(tripRef, participantId);

    const groupsSnap = await tripRef.collection('expenseGroups').get();

    let batch = db.batch();
    let n = 0;
    for (const doc of groupsSnap.docs) {
      const vis = doc.data().visibleToMemberIds;
      if (!Array.isArray(vis) || !vis.map(String).includes(participantId)) {
        continue;
      }
      batch.update(doc.ref, {
        visibleToMemberIds: FieldValue.arrayRemove(participantId),
      });
      n++;
      if (n >= 450) {
        await batch.commit();
        batch = db.batch();
        n = 0;
      }
    }

    batch.delete(participantSnap.ref);
    n++;

    if (claimedUserId) {
      batch.update(tripRef, {
        memberUserIds: FieldValue.arrayRemove(claimedUserId),
        adminMemberIds: FieldValue.arrayRemove(claimedUserId),
      });
      n++;
    }

    if (n > 0) {
      await batch.commit();
    }

    return { ok: true };
  }
);

exports.joinTripWithInvite = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const token = normalizeString(request.data?.token);
    if (!tripId || !token) {
      throw new HttpsError('invalid-argument', 'Lien d invitation invalide');
    }

    const participantId = normalizeString(request.data?.participantId);
    const bypassParticipantChoice = request.data?.bypassParticipantChoice === true;
    const participantName = normalizeString(request.data?.participantName);
    const useProfileName = request.data?.useProfileName === true;

    const tripRef = admin.firestore().collection('trips').doc(tripId);
    await completeJoinTripWithInvite(
      tripRef,
      uid,
      token,
      participantId,
      bypassParticipantChoice,
      participantName,
      useProfileName
    );

    return { ok: true };
  }
);

exports.leaveTrip = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const data = tripSnap.data() || {};
    const ownerId = normalizeString(data.ownerId);
    if (ownerId === uid) {
      throw new HttpsError(
        'permission-denied',
        'Le créateur du voyage ne peut pas quitter ainsi'
      );
    }

    const memberUserIds = Array.isArray(data.memberUserIds)
      ? data.memberUserIds.map((v) => String(v))
      : [];
    if (!memberUserIds.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Tu ne fais pas partie de ce voyage'
      );
    }

    const participantsSnap = await tripRef.collection('participants')
      .where('userId', '==', uid)
      .limit(1)
      .get();
    const participantDoc = participantsSnap.empty ? null : participantsSnap.docs[0];

    if (participantDoc) {
      await assertMemberRemovalBlockingDependencies({
        tripRef,
        memberId: participantDoc.id,
        tripData: data,
      });
      await cleanupNonBlockingMemberReferences(tripRef, participantDoc.id);
    }

    const batch = db.batch();
    batch.update(tripRef, {
      memberUserIds: FieldValue.arrayRemove(uid),
      adminMemberIds: FieldValue.arrayRemove(uid),
    });
    if (participantDoc) {
      batch.delete(participantDoc.ref);
    }
    await batch.commit();

    return { ok: true };
  }
);

const MAX_TRIP_SECTION_CARPOOL_CARS = 40;

function cloneFirestoreCarsArray(rawCars) {
  if (!Array.isArray(rawCars)) return [];
  return rawCars.map((entry) =>
    entry && typeof entry === 'object' ? { ...entry } : {}
  );
}

function participantIdIsDriverOfAnySerializedCar(cars, participantId) {
  return cars.some(
    (car) => normalizeString(car.driverParticipantId) === participantId
  );
}

function stripParticipantIdFromEveryCarAssignments(cars, participantId) {
  return cars.map((car) => {
    const copy = { ...car };
    const raw = Array.isArray(car.assignedParticipantIds)
      ? car.assignedParticipantIds
      : [];
    copy.assignedParticipantIds = raw
      .map((x) => String(x).trim())
      .filter((id) => id.length > 0 && id !== participantId);
    return copy;
  });
}

function validateSerializedTripCarOrThrow(car) {
  const driverUserId = normalizeString(car.driverParticipantId);
  const seatsRaw = car.availableSeats;
  const seats =
    typeof seatsRaw === 'number'
      ? seatsRaw
      : Number.parseInt(String(seatsRaw ?? ''), 10);
  if (!Number.isFinite(seats)) {
    throw new HttpsError('failed-precondition', 'Carpool misconfigured.');
  }
  const rawAssigned = Array.isArray(car.assignedParticipantIds)
    ? car.assignedParticipantIds.map((x) => String(x).trim()).filter(Boolean)
    : [];
  let assigned = [...new Set(rawAssigned)];
  if (driverUserId && !assigned.includes(driverUserId)) {
    assigned = [...assigned, driverUserId];
  }
  if (seats < 1) {
    throw new HttpsError('failed-precondition', 'Carpool misconfigured.');
  }
  if (assigned.length > seats) {
    throw new HttpsError('failed-precondition', 'Carpool misconfigured.');
  }
}

function validateAllTripSectionCarsOrThrow(cars) {
  if (cars.length > MAX_TRIP_SECTION_CARPOOL_CARS) {
    throw new HttpsError(
      'failed-precondition',
      'Too many carpools.'
    );
  }
  for (const car of cars) {
    validateSerializedTripCarOrThrow(car);
  }
}

function tripCarpoolPermissionMinRole(tripData, key, fallbackRole) {
  const perms =
    tripData && typeof tripData.permissions === 'object' ? tripData.permissions : {};
  const carpoolPerms =
    perms && typeof perms.carpool === 'object' ? perms.carpool : {};
  const configured = normalizeString(carpoolPerms[key]);
  return configured || fallbackRole;
}

function parseRawDateToTimestamp(rawValue) {
  if (rawValue instanceof Timestamp) {
    return rawValue;
  }
  if (rawValue instanceof Date && Number.isFinite(rawValue.getTime())) {
    return Timestamp.fromDate(rawValue);
  }
  if (typeof rawValue === 'number' && Number.isFinite(rawValue)) {
    return Timestamp.fromMillis(rawValue);
  }
  if (typeof rawValue === 'string') {
    const parsedDate = new Date(rawValue);
    if (Number.isFinite(parsedDate.getTime())) {
      return Timestamp.fromDate(parsedDate);
    }
  }
  return null;
}

function parseCallableDateToTimestamp(rawValue) {
  const parsedTimestamp = parseRawDateToTimestamp(rawValue);
  if (parsedTimestamp) {
    return parsedTimestamp;
  }
  throw new HttpsError('invalid-argument', 'Parametres invalides');
}

function parseTimestampOrFallback(rawValue, fallbackTimestamp) {
  return parseRawDateToTimestamp(rawValue) ?? fallbackTimestamp;
}

exports.upsertTripCarpool = onCall({}, async (request) => {
  const uid = normalizeString(request.auth?.uid);
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
  }

  const tripId = normalizeString(request.data?.tripId);
  const requestedCarpoolId = normalizeString(request.data?.carpoolId);
  const driverParticipantId = normalizeString(request.data?.driverParticipantId);
  const meetingPointAddress = normalizeString(request.data?.meetingPointAddress);
  const nearestTransitStop = normalizeString(request.data?.nearestTransitStop);
  const departureAt = parseCallableDateToTimestamp(
    request.data?.departureAtMillis ?? request.data?.departureAt
  );
  const availableSeatsRaw = request.data?.availableSeats;
  const availableSeats =
    typeof availableSeatsRaw === 'number'
      ? availableSeatsRaw
      : Number.parseInt(String(availableSeatsRaw ?? ''), 10);
  const assignedParticipantIdsRaw = Array.isArray(request.data?.assignedParticipantIds)
    ? request.data.assignedParticipantIds
    : [];
  const goesShopping = request.data?.goesShopping === true;

  if (!tripId || !driverParticipantId || !Number.isFinite(availableSeats)) {
    throw new HttpsError('invalid-argument', 'Parametres invalides');
  }
  if (!Number.isInteger(availableSeats) || availableSeats < 1) {
    throw new HttpsError('invalid-argument', 'Parametres invalides');
  }

  const normalizedAssignedParticipantIds = [
    ...new Set(
      assignedParticipantIdsRaw
        .map((entry) => normalizeString(entry))
        .filter(Boolean)
        .concat(driverParticipantId)
    ),
  ];
  if (normalizedAssignedParticipantIds.length > availableSeats) {
    throw new HttpsError('invalid-argument', 'Parametres invalides');
  }

  const db = admin.firestore();
  const tripRef = db.collection('trips').doc(tripId);
  const sectionRef = tripRef.collection('sections').doc('carpool');

  // Validate participant IDs against the participants subcollection before the
  // transaction (Firestore transactions don't support collection queries).
  const participantsSnap = await tripRef.collection('participants').get();
  const validParticipantIds = new Set(participantsSnap.docs.map((d) => d.id));
  if (!validParticipantIds.has(driverParticipantId)) {
    throw new HttpsError('invalid-argument', 'Conducteur introuvable');
  }
  const driverParticipantDoc = participantsSnap.docs.find(
    (doc) => doc.id === driverParticipantId
  );
  if (driverParticipantDoc?.data()?.isChild === true) {
    throw new HttpsError(
      'invalid-argument',
      'Un enfant ne peut pas etre conducteur.'
    );
  }
  for (const pid of normalizedAssignedParticipantIds) {
    if (!validParticipantIds.has(pid)) {
      throw new HttpsError('invalid-argument', 'Participant introuvable');
    }
  }

  await db.runTransaction(async (tx) => {
    const [tripSnap, sectionSnap] = await Promise.all([
      tx.get(tripRef),
      tx.get(sectionRef),
    ]);
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const tripData = tripSnap.data() || {};
    const memberIds = Array.isArray(tripData.memberUserIds)
      ? tripData.memberUserIds.map((value) => normalizeString(value)).filter(Boolean)
      : [];
    if (!memberIds.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Tu ne fais pas partie de ce voyage'
      );
    }

    const sectionData = sectionSnap.exists ? sectionSnap.data() || {} : {};
    const cars = cloneFirestoreCarsArray(sectionData.cars);

    const targetCarpoolId = requestedCarpoolId || db.collection('_').doc().id;
    const targetCarIndex = cars.findIndex(
      (car) => normalizeString(car.id) === targetCarpoolId
    );
    const existingCar = targetCarIndex >= 0 ? cars[targetCarIndex] : null;

    if (existingCar) {
      const carpoolCreatorUserId = normalizeString(existingCar.createdByUserId);
      const minEditRole = tripCarpoolPermissionMinRole(
        tripData,
        'editCarpools',
        'admin'
      );
      const canEditAsTripRole =
        tripCallerRoleRank(tripData, uid) >= roleRank(minEditRole);
      if (uid !== carpoolCreatorUserId && !canEditAsTripRole) {
        throw new HttpsError(
          'permission-denied',
          'Tu n as pas le droit de modifier ce covoiturage'
        );
      }
    } else {
      const minCreateRole = tripCarpoolPermissionMinRole(
        tripData,
        'proposeCarpool',
        'participant'
      );
      const canCreate =
        tripCallerRoleRank(tripData, uid) >= roleRank(minCreateRole);
      if (!canCreate) {
        throw new HttpsError(
          'permission-denied',
          'Tu n as pas le droit de proposer un covoiturage'
        );
      }
    }

    const assignedInOtherCars = new Set();
    for (const car of cars) {
      const currentCarId = normalizeString(car.id);
      if (currentCarId === targetCarpoolId) continue;
      const rawAssigned = Array.isArray(car.assignedParticipantIds)
        ? car.assignedParticipantIds
        : [];
      for (const participantId of rawAssigned) {
        const normalizedId = normalizeString(participantId);
        if (normalizedId) {
          assignedInOtherCars.add(normalizedId);
        }
      }
    }
    for (const participantId of normalizedAssignedParticipantIds) {
      if (assignedInOtherCars.has(participantId)) {
        throw new HttpsError(
          'failed-precondition',
          'Participant already assigned to another carpool.'
        );
      }
    }

    const createdAt = parseTimestampOrFallback(
      existingCar?.createdAt,
      Timestamp.now()
    );
    const createdByUserId = normalizeString(existingCar?.createdByUserId) || uid;
    const updatedCar = {
      id: targetCarpoolId,
      createdByUserId,
      driverParticipantId,
      meetingPointAddress,
      nearestTransitStop,
      departureAt,
      availableSeats,
      assignedParticipantIds: normalizedAssignedParticipantIds,
      goesShopping,
      createdAt,
      updatedAt: Timestamp.now(),
    };

    const nextCars = cars.filter(
      (car) => normalizeString(car.id) !== targetCarpoolId
    );
    nextCars.push(updatedCar);
    validateAllTripSectionCarsOrThrow(nextCars);

    tx.set(
      sectionRef,
      {
        cars: nextCars,
        updatedAt: Timestamp.now(),
      },
      { merge: true }
    );
  });

  return { ok: true };
});

exports.deleteTripCarpool = onCall({}, async (request) => {
  const uid = normalizeString(request.auth?.uid);
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
  }
  const tripId = normalizeString(request.data?.tripId);
  const carpoolId = normalizeString(request.data?.carpoolId);
  if (!tripId || !carpoolId) {
    throw new HttpsError('invalid-argument', 'Parametres invalides');
  }

  const db = admin.firestore();
  const tripRef = db.collection('trips').doc(tripId);
  const sectionRef = tripRef.collection('sections').doc('carpool');

  await db.runTransaction(async (tx) => {
    const [tripSnap, sectionSnap] = await Promise.all([
      tx.get(tripRef),
      tx.get(sectionRef),
    ]);
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const tripData = tripSnap.data() || {};
    const memberIds = Array.isArray(tripData.memberUserIds)
      ? tripData.memberUserIds.map((value) => normalizeString(value)).filter(Boolean)
      : [];
    if (!memberIds.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Tu ne fais pas partie de ce voyage'
      );
    }
    if (!sectionSnap.exists) {
      return;
    }

    const sectionData = sectionSnap.data() || {};
    const cars = cloneFirestoreCarsArray(sectionData.cars);
    const targetCarIndex = cars.findIndex(
      (car) => normalizeString(car.id) === carpoolId
    );
    if (targetCarIndex < 0) {
      return;
    }

    const targetCar = cars[targetCarIndex];
    const carpoolCreatorUserId = normalizeString(targetCar.createdByUserId);
    const minEditRole = tripCarpoolPermissionMinRole(
      tripData,
      'editCarpools',
      'admin'
    );
    const canEditAsTripRole =
      tripCallerRoleRank(tripData, uid) >= roleRank(minEditRole);
    if (uid !== carpoolCreatorUserId && !canEditAsTripRole) {
      throw new HttpsError(
        'permission-denied',
        'Tu n as pas le droit de supprimer ce covoiturage'
      );
    }

    const nextCars = cars.filter((car) => normalizeString(car.id) !== carpoolId);
    validateAllTripSectionCarsOrThrow(nextCars);
    tx.set(
      sectionRef,
      {
        cars: nextCars,
        updatedAt: Timestamp.now(),
      },
      { merge: true }
    );
  });

  return { ok: true };
});

exports.joinTripCarpoolAsPassenger = onCall({}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
  }
  const tripId = normalizeString(request.data?.tripId);
  const targetCarpoolId = normalizeString(request.data?.targetCarpoolId);
  if (!tripId || !targetCarpoolId) {
    throw new HttpsError('invalid-argument', 'Parametres invalides');
  }

  const db = admin.firestore();
  const tripRef = db.collection('trips').doc(tripId);
  const sectionRef = tripRef.collection('sections').doc('carpool');

  // Resolve caller's participant document ID before the transaction.
  const myParticipantSnap = await tripRef
    .collection('participants')
    .where('userId', '==', uid)
    .limit(1)
    .get();
  if (myParticipantSnap.empty) {
    throw new HttpsError('permission-denied', 'Tu ne fais pas partie de ce voyage');
  }
  const myParticipantId = myParticipantSnap.docs[0].id;

  await db.runTransaction(async (tx) => {
    const [tripSnap, sectionSnap] = await Promise.all([
      tx.get(tripRef),
      tx.get(sectionRef),
    ]);
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const sectionData = sectionSnap.exists ? sectionSnap.data() || {} : {};
    let cars = cloneFirestoreCarsArray(sectionData.cars);

    // Block drivers (handles both new driverParticipantId and legacy driverUserId).
    if (participantIdIsDriverOfAnySerializedCar(cars, myParticipantId)) {
      throw new HttpsError(
        'permission-denied',
        'Drivers cannot join another carpool via self-assignment.'
      );
    }

    cars = stripParticipantIdFromEveryCarAssignments(cars, myParticipantId);

    const targetIndex = cars.findIndex(
      (c) => normalizeString(c.id) === targetCarpoolId
    );
    if (targetIndex < 0) {
      throw new HttpsError('not-found', 'Carpool not found.');
    }

    const targetCar = { ...cars[targetIndex] };
    const seatsRaw = targetCar.availableSeats;
    const seats =
      typeof seatsRaw === 'number'
        ? seatsRaw
        : Number.parseInt(String(seatsRaw ?? ''), 10);
    const rawAssigned = Array.isArray(targetCar.assignedParticipantIds)
      ? targetCar.assignedParticipantIds.map((x) => String(x).trim()).filter(Boolean)
      : [];
    const assignedIds = [...new Set(rawAssigned)];
    const driverParticipantId = normalizeString(targetCar.driverParticipantId);
    if (driverParticipantId && !assignedIds.includes(driverParticipantId)) {
      assignedIds.push(driverParticipantId);
    }
    if (!Number.isFinite(seats) || assignedIds.length >= seats) {
      throw new HttpsError('failed-precondition', 'Carpool is full.');
    }
    if (assignedIds.includes(myParticipantId)) {
      throw new HttpsError('failed-precondition', 'Carpool misconfigured.');
    }
    assignedIds.push(myParticipantId);
    targetCar.assignedParticipantIds = assignedIds;
    targetCar.updatedAt = Timestamp.now();
    cars[targetIndex] = targetCar;

    validateAllTripSectionCarsOrThrow(cars);

    tx.set(
      sectionRef,
      {
        cars,
        updatedAt: Timestamp.now(),
      },
      { merge: true }
    );
  });

  return { ok: true };
});

exports.leaveTripCarpoolAsPassenger = onCall({}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
  }
  const tripId = normalizeString(request.data?.tripId);
  const carpoolId = normalizeString(request.data?.carpoolId);
  if (!tripId || !carpoolId) {
    throw new HttpsError('invalid-argument', 'Parametres invalides');
  }

  const db = admin.firestore();
  const tripRef = db.collection('trips').doc(tripId);
  const sectionRef = tripRef.collection('sections').doc('carpool');

  // Resolve caller's participant document ID before the transaction.
  const myParticipantSnap = await tripRef
    .collection('participants')
    .where('userId', '==', uid)
    .limit(1)
    .get();
  if (myParticipantSnap.empty) {
    throw new HttpsError('permission-denied', 'Tu ne fais pas partie de ce voyage');
  }
  const myParticipantId = myParticipantSnap.docs[0].id;

  await db.runTransaction(async (tx) => {
    const [tripSnap, sectionSnap] = await Promise.all([
      tx.get(tripRef),
      tx.get(sectionRef),
    ]);
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const sectionData = sectionSnap.exists ? sectionSnap.data() || {} : {};
    const cars = cloneFirestoreCarsArray(sectionData.cars);

    // Block drivers (handles both new driverParticipantId and legacy driverUserId).
    if (participantIdIsDriverOfAnySerializedCar(cars, myParticipantId)) {
      throw new HttpsError(
        'permission-denied',
        'Drivers cannot leave their carpool via self-assignment.'
      );
    }

    const targetIndex = cars.findIndex(
      (c) => normalizeString(c.id) === carpoolId
    );
    if (targetIndex < 0) {
      throw new HttpsError('not-found', 'Carpool not found.');
    }

    const targetCar = cars[targetIndex];
    const driverParticipantId = normalizeString(targetCar.driverParticipantId);
    if (driverParticipantId === myParticipantId) {
      throw new HttpsError(
        'permission-denied',
        'Drivers cannot leave their carpool via self-assignment.'
      );
    }

    const rawAssigned = Array.isArray(targetCar.assignedParticipantIds)
      ? targetCar.assignedParticipantIds.map((x) => String(x).trim()).filter(Boolean)
      : [];
    const assignedIds = [...new Set(rawAssigned)];
    if (!assignedIds.includes(myParticipantId)) {
      return;
    }

    const nextCars = cars.map((car, idx) => {
      if (idx !== targetIndex) {
        return { ...car };
      }
      const copy = { ...car };
      copy.assignedParticipantIds = assignedIds.filter((id) => id !== myParticipantId);
      copy.updatedAt = Timestamp.now();
      return copy;
    });

    validateAllTripSectionCarsOrThrow(nextCars);

    tx.set(
      sectionRef,
      {
        cars: nextCars,
        updatedAt: Timestamp.now(),
      },
      { merge: true }
    );
  });

  return { ok: true };
});

exports.removeTripRegisteredMember = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const memberId = normalizeString(request.data?.memberId);
    if (!tripId || !memberId) {
      throw new HttpsError('invalid-argument', 'Parametres invalides');
    }
    if (memberId === uid) {
      throw new HttpsError(
        'invalid-argument',
        'Utilise l\'action quitter le voyage pour ton propre compte.'
      );
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const data = tripSnap.data() || {};
    await assertTripParticipantPermission({
      tripData: data,
      uid,
      permissionKey: 'manageParticipants',
      fallbackRole: 'owner',
      deniedMessage: 'Droits insuffisants pour retirer ce participant.',
    });

    const ownerId = normalizeString(data.ownerId);
    if (memberId === ownerId) {
      throw new HttpsError(
        'failed-precondition',
        'Le créateur du voyage ne peut pas être supprimé.'
      );
    }

    const memberUserIds = Array.isArray(data.memberUserIds)
      ? data.memberUserIds.map((v) => String(v))
      : [];
    if (!memberUserIds.includes(memberId)) {
      throw new HttpsError('not-found', 'Participant introuvable');
    }

    const participantsSnap = await tripRef.collection('participants')
      .where('userId', '==', memberId)
      .limit(1)
      .get();
    const participantDoc = participantsSnap.empty ? null : participantsSnap.docs[0];

    if (participantDoc) {
      await assertMemberRemovalBlockingDependencies({
        tripRef,
        memberId: participantDoc.id,
        tripData: data,
      });
      await cleanupNonBlockingMemberReferences(tripRef, participantDoc.id);
    }

    const batch = db.batch();
    batch.update(tripRef, {
      memberUserIds: FieldValue.arrayRemove(memberId),
      adminMemberIds: FieldValue.arrayRemove(memberId),
    });
    if (participantDoc) {
      batch.delete(participantDoc.ref);
    }
    await batch.commit();

    return { ok: true };
  }
);

exports.cycleTripMemberAdminRole = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const memberId = normalizeString(request.data?.memberId);
    if (!tripId || !memberId) {
      throw new HttpsError('invalid-argument', 'Parametres invalides');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = tripSnap.data() || {};
    await assertTripParticipantPermission({
      tripData: data,
      uid,
      permissionKey: 'toggleAdminRole',
      fallbackRole: 'owner',
      deniedMessage: 'Droits insuffisants pour modifier ce rôle',
    });

    const ownerId = normalizeString(data.ownerId);
    if (memberId === ownerId) {
      throw new HttpsError(
        'invalid-argument',
        'Le créateur du voyage reste administrateur'
      );
    }

    const memberUserIds = Array.isArray(data.memberUserIds)
      ? data.memberUserIds.map((v) => String(v))
      : [];
    if (!memberUserIds.includes(memberId)) {
      throw new HttpsError('not-found', 'Participant introuvable');
    }

    const admins = tripAdminMemberIdSet(data);
    if (admins.has(memberId)) {
      await tripRef.update({
        adminMemberIds: FieldValue.arrayRemove(memberId),
      });
    } else {
      await tripRef.update({
        adminMemberIds: FieldValue.arrayUnion(memberId),
      });
    }

    return { ok: true };
  }
);

exports.registerMyTripMemberLabel = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }

    const tripRef = admin.firestore().collection('trips').doc(tripId);
    const snap = await tripRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = snap.data() || {};
    const memberUserIds = Array.isArray(data.memberUserIds)
      ? data.memberUserIds.map((v) => String(v))
      : [];
    if (!memberUserIds.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Tu ne fais pas partie de ce voyage'
      );
    }

    // participantName is now set from the participants sub-collection.
    return { ok: true };
  }
);

exports.deleteTripCascade = onCall(
  {
    timeoutSeconds: 540,
    memory: '1GiB',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      return { ok: true, tripId, deleted: false, reason: 'not-found' };
    }

    const tripData = tripSnap.data() || {};
    const ownerId = normalizeString(tripData.ownerId);
    if (ownerId !== uid) {
      throw new HttpsError(
        'permission-denied',
        'Seul le proprietaire peut supprimer ce voyage'
      );
    }

    // Remove Storage assets first so no orphan blobs remain if recursive
    // deletion succeeds.
    await deleteTripStorageObjects(tripId);

    // Deletes the trip document and all nested subcollections recursively.
    await db.recursiveDelete(tripRef);

    return { ok: true, tripId, deleted: true };
  }
);

exports.backfillLegacyTripPermissions = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(tripRef);
      if (!snap.exists) {
        throw new HttpsError('not-found', 'Voyage introuvable');
      }
      const data = snap.data() || {};
      const memberIds = Array.isArray(data.memberUserIds)
        ? data.memberUserIds.map((v) => normalizeString(v)).filter(Boolean)
        : [];
      if (!memberIds.includes(uid)) {
        throw new HttpsError(
          'permission-denied',
          'Tu ne fais pas partie de ce voyage'
        );
      }

      const currentPermissions =
        data.permissions &&
        typeof data.permissions === 'object' &&
        !Array.isArray(data.permissions)
          ? data.permissions
          : {};
      const mergedPermissions =
        mergedTripPermissionsWithDefaults(currentPermissions);
      if (tripPermissionsEqual(currentPermissions, mergedPermissions)) {
        return { changed: false, reason: 'already-up-to-date' };
      }

      tx.update(tripRef, {
        permissions: mergedPermissions,
        permissionsBackfilledAt: FieldValue.serverTimestamp(),
        permissionsBackfilledBy: uid,
      });
      return { changed: true, reason: 'backfilled' };
    });

    return {
      ok: true,
      tripId,
      changed: result.changed,
      reason: result.reason,
    };
  }
);

exports.setTripCupidonEnabled = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const enabled = request.data?.enabled === true;
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const tripData = tripSnap.data() || {};
    const memberIds = Array.isArray(tripData.memberUserIds)
      ? tripData.memberUserIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Tu ne fais pas partie de ce voyage'
      );
    }

    const participantSnap = await tripRef
      .collection('participants')
      .where('userId', '==', uid)
      .limit(1)
      .get();
    if (participantSnap.empty) {
      throw new HttpsError('not-found', 'Tu n\'es pas inscrit comme participant');
    }
    await participantSnap.docs[0].ref.update({
      cupidonEnabled: enabled,
      cupidonUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { ok: true };
  }
);

exports.updateParticipantProfile = onCall(
  {},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const participantId = normalizeString(request.data?.participantId);
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }

    const stayStartDateKey = normalizeString(request.data?.stayStartDateKey);
    const stayStartDayPart = normalizeString(request.data?.stayStartDayPart);
    const stayEndDateKey = normalizeString(request.data?.stayEndDateKey);
    const stayEndDayPart = normalizeString(request.data?.stayEndDayPart);
    const phoneVisibility = normalizeString(request.data?.phoneVisibility);

    const hasStay = stayStartDateKey && stayStartDayPart && stayEndDateKey && stayEndDayPart;
    const hasPhone = !!phoneVisibility;
    if (!hasStay && !hasPhone) {
      throw new HttpsError('invalid-argument', 'Aucun champ à mettre à jour');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const tripData = tripSnap.data() || {};
    const memberIds = Array.isArray(tripData.memberUserIds)
      ? tripData.memberUserIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid) && !(await userIsApplicationOwner(uid))) {
      throw new HttpsError('permission-denied', 'Tu ne fais pas partie de ce voyage');
    }

    let participantRef;
    if (participantId) {
      participantRef = tripRef.collection('participants').doc(participantId);
      const participantSnap = await participantRef.get();
      if (!participantSnap.exists) {
        throw new HttpsError('not-found', 'Participant introuvable');
      }
      const participantUserId = normalizeString(participantSnap.data()?.userId);
      if (participantUserId !== uid) {
        await assertTripParticipantPermission({
          tripData,
          uid,
          permissionKey: 'manageParticipants',
          fallbackRole: 'owner',
          deniedMessage: 'Droits insuffisants pour modifier ce participant.',
        });
      }
    } else {
      const snap = await tripRef
        .collection('participants')
        .where('userId', '==', uid)
        .limit(1)
        .get();
      if (snap.empty) {
        throw new HttpsError('not-found', 'Tu n\'es pas inscrit comme participant');
      }
      participantRef = snap.docs[0].ref;
    }

    const update = { updatedAt: FieldValue.serverTimestamp() };
    if (hasStay) {
      update.stayStartDateKey = stayStartDateKey;
      update.stayStartDayPart = stayStartDayPart;
      update.stayEndDateKey = stayEndDateKey;
      update.stayEndDayPart = stayEndDayPart;
    }
    if (hasPhone) {
      update.phoneVisibility = phoneVisibility;
    }

    await participantRef.update(update);
    return { ok: true };
  }
);

exports.toggleTripCupidonLike = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const targetMemberId = normalizeString(request.data?.targetMemberId);
    const isLiked = request.data?.isLiked === true;
    if (!tripId || !targetMemberId) {
      throw new HttpsError('invalid-argument', 'Parametres invalides');
    }
    if (targetMemberId === uid) {
      throw new HttpsError('invalid-argument', 'Tu ne peux pas te liker');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const tripData = tripSnap.data() || {};
    const memberIds = Array.isArray(tripData.memberUserIds)
      ? tripData.memberUserIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid) || !memberIds.includes(targetMemberId)) {
      throw new HttpsError('permission-denied', 'Participants invalides');
    }

    const participantsRef = tripRef.collection('participants');
    const [myParticipantSnap, targetParticipantSnap] = await Promise.all([
      participantsRef.where('userId', '==', uid).limit(1).get(),
      participantsRef.where('userId', '==', targetMemberId).limit(1).get(),
    ]);
    if (!hasCupidonEnabled(myParticipantSnap.docs[0]?.data())) {
      throw new HttpsError(
        'failed-precondition',
        'Active le mode Cupidon pour liker des participants'
      );
    }
    const targetCupidonEnabled = hasCupidonEnabled(targetParticipantSnap.docs[0]?.data());

    const likeRef = tripRef
      .collection('cupidonLikes')
      .doc(cupidonLikeDocId(uid, targetMemberId));
    if (isLiked) {
      await likeRef.set(
        {
          likerId: uid,
          targetId: targetMemberId,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      if (!targetCupidonEnabled) {
        return { ok: true, match: false };
      }
      const reciprocalRef = tripRef
        .collection('cupidonLikes')
        .doc(cupidonLikeDocId(targetMemberId, uid));
      const reciprocalSnap = await reciprocalRef.get();
      if (!reciprocalSnap.exists) {
        return { ok: true, match: false };
      }

      const matchId = cupidonMatchDocId(tripId, uid, targetMemberId);
      const tripMatchRef = tripRef.collection('cupidonMatches').doc(matchId);
      const meMatchRef = db
        .collection('users')
        .doc(uid)
        .collection('cupidonMatches')
        .doc(matchId);
      const targetMatchRef = db
        .collection('users')
        .doc(targetMemberId)
        .collection('cupidonMatches')
        .doc(matchId);
      const tripTitle = normalizeString(tripData.title) || 'Voyage';
      const [myProfile, targetProfile] = await Promise.all([
        resolveTripMemberProfile(tripData, uid),
        resolveTripMemberProfile(tripData, targetMemberId),
      ]);
      const matchDataForMe = {
        matchId,
        tripId,
        tripTitle,
        otherMemberId: targetMemberId,
        otherMemberLabel: targetProfile.label,
        otherMemberPhotoUrl: targetProfile.photoUrl,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      const matchDataForTarget = {
        matchId,
        tripId,
        tripTitle,
        otherMemberId: uid,
        otherMemberLabel: myProfile.label,
        otherMemberPhotoUrl: myProfile.photoUrl,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };

      // Deduplicate match creation in concurrent like scenarios.
      const created = await db.runTransaction(async (tx) => {
        const tripMatchSnap = await tx.get(tripMatchRef);
        if (tripMatchSnap.exists) {
          return false;
        }
        const matchCreatedAt = FieldValue.serverTimestamp();
        tx.set(tripMatchRef, {
          matchId,
          tripId,
          memberIds: [uid, targetMemberId],
          createdAt: matchCreatedAt,
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.set(
          meMatchRef,
          {
            ...matchDataForMe,
            createdAt: matchCreatedAt,
          },
          { merge: true }
        );
        tx.set(
          targetMatchRef,
          {
            ...matchDataForTarget,
            createdAt: matchCreatedAt,
          },
          { merge: true }
        );
        return true;
      });

      if (!created) {
        return { ok: true, match: true };
      }

      await Promise.all([
        sendCupidonMatchPush({
          tripId,
          matchId,
          tripTitle,
          notifiedUid: uid,
          otherLabel: targetProfile.label,
          otherPhotoUrl: targetProfile.photoUrl,
        }),
        sendCupidonMatchPush({
          tripId,
          matchId,
          tripTitle,
          notifiedUid: targetMemberId,
          otherLabel: myProfile.label,
          otherPhotoUrl: myProfile.photoUrl,
        }),
      ]);

      return { ok: true, match: true };
    }

    await likeRef.delete();
    const matchId = cupidonMatchDocId(tripId, uid, targetMemberId);
    await removeCupidonMatchEverywhereAndCounters({
      db,
      tripId,
      uidA: uid,
      uidB: targetMemberId,
      matchId,
    });
    return { ok: true, match: false };
  }
);

exports.deleteCupidonMatch = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const matchId = normalizeString(request.data?.matchId);
    if (!matchId) {
      throw new HttpsError('invalid-argument', 'Match invalide');
    }

    const db = admin.firestore();
    const ref = db
      .collection('users')
      .doc(uid)
      .collection('cupidonMatches')
      .doc(matchId);
    const matchSnap = await ref.get();
    const matchData = matchSnap.exists ? matchSnap.data() || {} : {};
    await ref.delete();

    const tripId = normalizeString(matchData.tripId);
    const otherMemberId = normalizeString(matchData.otherMemberId);
    if (tripId && otherMemberId && otherMemberId !== uid) {
      const likeRef = db
        .collection('trips')
        .doc(tripId)
        .collection('cupidonLikes')
        .doc(cupidonLikeDocId(uid, otherMemberId));
      await likeRef.delete();
      await removeCupidonMatchEverywhereAndCounters({
        db,
        tripId,
        uidA: uid,
        uidB: otherMemberId,
        matchId,
      });
    }
    return { ok: true };
  }
);

/**
 * Returns anonymous app-wide usage statistics for the administration panel.
 * Restricted to users with isApplicationOwner === true in Firestore.
 * No PII is returned — no names, emails, or location data.
 */
exports.getAppUsageStats = onCall(
  {
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }

    const db = admin.firestore();
    const userSnap = await db.collection('users').doc(uid).get();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    if (userData.isApplicationOwner !== true) {
      throw new HttpsError('permission-denied', 'Accès réservé aux administrateurs');
    }

    const now = Date.now();

    // --- Trips ---
    const tripsSnap = await db.collection('trips').get();
    let totalTrips = 0;
    let pastTrips = 0;
    let ongoingTrips = 0;
    let upcomingTrips = 0;
    let uncategorizedTrips = 0;
    let maxParticipants = 0;
    let maxDurationDays = 0;
    let latestTripCreatedAtMs = 0;

    for (const doc of tripsSnap.docs) {
      const trip = doc.data() || {};
      totalTrips++;
      const createdAt = trip.createdAt instanceof Timestamp
        ? trip.createdAt.toMillis()
        : doc.createTime instanceof Timestamp
        ? doc.createTime.toMillis()
        : 0;
      if (createdAt > latestTripCreatedAtMs) {
        latestTripCreatedAtMs = createdAt;
      }

      const memberCount = Array.isArray(trip.memberUserIds) ? trip.memberUserIds.length : 0;
      if (memberCount > maxParticipants) maxParticipants = memberCount;

      const startDate = trip.startDate instanceof Timestamp
        ? trip.startDate
        : null;
      const endDate = trip.endDate instanceof Timestamp
        ? trip.endDate
        : null;

      if (startDate && endDate) {
        const durationMs = endDate.toMillis() - startDate.toMillis();
        const durationDays = Math.max(0, Math.round(durationMs / (1000 * 60 * 60 * 24)));
        if (durationDays > maxDurationDays) maxDurationDays = durationDays;

        const startMs = startDate.toMillis();
        const endMs = endDate.toMillis();
        if (endMs < now) {
          pastTrips++;
        } else if (startMs > now) {
          upcomingTrips++;
        } else {
          ongoingTrips++;
        }
      } else if (startDate) {
        if (startDate.toMillis() > now) {
          upcomingTrips++;
        } else {
          ongoingTrips++;
        }
      } else {
        uncategorizedTrips++;
      }
    }

    // --- Users ---
    let totalUsers = 0;
    let latestSignInMs = 0;
    let pageToken;

    do {
      const listResult = await admin.auth().listUsers(1000, pageToken);
      for (const user of listResult.users) {
        totalUsers++;
        const signInTime = user.metadata.lastSignInTime;
        if (signInTime) {
          const ms = new Date(signInTime).getTime();
          if (!isNaN(ms) && ms > latestSignInMs) latestSignInMs = ms;
        }
      }
      pageToken = listResult.pageToken;
    } while (pageToken);

    // --- Activities ---
    const activitiesSnap = await db.collectionGroup('activities').get();
    let totalActivities = 0;
    let plannedActivities = 0;
    /** @type {Record<string, number>} */
    const activitiesByCategory = {};

    for (const doc of activitiesSnap.docs) {
      const act = doc.data() || {};
      totalActivities++;

      const category = normalizeString(act.category) || 'unknown';
      activitiesByCategory[category] = (activitiesByCategory[category] || 0) + 1;

      if (act.plannedAt instanceof Timestamp) {
        plannedActivities++;
      }
    }

    return {
      trips: {
        total: totalTrips,
        past: pastTrips,
        ongoing: ongoingTrips,
        upcoming: upcomingTrips,
        uncategorized: uncategorizedTrips,
        maxParticipants,
        maxDurationDays,
        latestCreatedAtIso: latestTripCreatedAtMs > 0
          ? new Date(latestTripCreatedAtMs).toISOString()
          : null,
      },
      users: {
        total: totalUsers,
        latestSignInMs: latestSignInMs > 0 ? latestSignInMs : null,
      },
      activities: {
        total: totalActivities,
        planned: plannedActivities,
        byCategory: activitiesByCategory,
      },
    };
  }
);

// ============================================================
// AI-driven shopping list consolidation (POC)
// ============================================================
// Source of truth: scripts/ia/antropic_shopping_consolidate.ps1
// - Same system/user prompts.
// - Same JSON tool schema (summary + consolidatedItems[ + sourceItems ]).
// - Same per-provider request shapes (Anthropic v1/messages,
//   Gemini generateContent with thinkingBudget = 0).
// ============================================================

const AI_CONSOLIDATION_TOOL_NAME = 'consolidate_shopping_list';

function buildAiConsolidationToolDescription(lang) {
  return lang === 'en'
    ? 'Returns the consolidated shopping list built from the two input arrays.'
    : 'Retourne la liste de courses consolidee a partir des deux tableaux fournis.';
}

function buildAiConsolidationSystemPrompt(lang) {
  if (lang === 'en') {
    return [
      'You are an assistant specialised in consolidating culinary ingredient lists.',
      'Merging rules:',
      '- Merge only when the base name is identical or nearly identical.',
      '- Do not merge semantically different ingredients.',
      '- Convert compatible units before adding (g/kg, ml/l).',
      '- If units are incompatible, keep separate lines.',
      '- sourceType must be manual, recipe, or mixed according to the consolidated origin.',
      "- For each consolidated ingredient, assign a categoryId from the identifiers provided in the prompt. Choose the most precise category. Use 'divers' if no category fits.",
    ].join('\n');
  }
  return [
    'Tu es un assistant specialise dans la consolidation de listes d ingredients culinaires.',
    'Regles de fusion :',
    '- Fusionner uniquement si le nom de base est identique ou quasi-identique.',
    '- Ne pas fusionner des ingredients semantiquement differents.',
    '- Convertir les unites compatibles avant addition (g/kg, ml/l).',
    '- Si les unites sont incompatibles, garder des lignes separees.',
    '- sourceType doit valoir manual, recipe, ou mixed selon l origine consolidee.',
    "- Pour chaque ingredient consolide, assigne un categoryId parmi les identifiants fournis dans le prompt. Choisis la categorie la plus precise. Utilise 'divers' si aucune categorie ne convient.",
  ].join('\n');
}

function buildAiConsolidationToolSchema(lang) {
  const isFr = lang !== 'en';
  return {
    type: 'object',
    required: ['summary', 'consolidatedItems'],
    properties: {
      summary: {
        type: 'object',
        required: ['manualOriginalLineCount', 'recipeOriginalLineCount'],
        properties: {
          manualOriginalLineCount: {
            type: 'integer',
            description: isFr
              ? 'Nombre total de lignes en entree dans manualShoppingItems'
              : 'Total number of input lines in manualShoppingItems',
          },
          recipeOriginalLineCount: {
            type: 'integer',
            description: isFr
              ? 'Nombre total de lignes en entree dans recipeIngredients'
              : 'Total number of input lines in recipeIngredients',
          },
        },
      },
      consolidatedItems: {
        type: 'array',
        items: {
          type: 'object',
          required: [
            'itemLabel',
            'quantityValue',
            'quantityUnit',
            'sourceType',
            'categoryId',
            'manualOriginalLineCount',
            'recipeOriginalLineCount',
          ],
          properties: {
            itemLabel: {
              type: 'string',
              description: isFr ? 'Nom consolide de l ingredient' : 'Consolidated ingredient name',
            },
            quantityValue: {
              type: 'number',
              description: isFr ? 'Quantite totale consolidee' : 'Total consolidated quantity',
            },
            quantityUnit: {
              type: 'string',
              description: isFr ? 'Unite apres conversion eventuelle' : 'Unit after optional conversion',
            },
            sourceType: { type: 'string', enum: ['manual', 'recipe', 'mixed'] },
            categoryId: {
              type: 'string',
              description: isFr
                ? 'Identifiant de la categorie de course (voir liste fournie). Utiliser "divers" si aucune ne convient.'
                : 'Shopping category identifier (see provided list). Use "divers" if none fits.',
              enum: [
                'animaux',
                'bebe',
                'boissons',
                'boucherie',
                'boulangerie-viennoiserie',
                'conserves',
                'cremerie',
                'divers',
                'entretien',
                'epicerie-salee',
                'epicerie-sucree',
                'fruits-et-legumes',
                'hygiene',
                'maison',
                'petit-dejeuner-et-gouter',
                'poissonnerie',
                'rayon-frais',
                'surgeles',
              ],
            },
            manualOriginalLineCount: {
              type: 'integer',
              description: isFr
                ? 'Nombre de lignes manual fusionnees dans cette entree'
                : 'Number of manual lines merged into this entry',
            },
            recipeOriginalLineCount: {
              type: 'integer',
              description: isFr
                ? 'Nombre de lignes recipe fusionnees dans cette entree'
                : 'Number of recipe lines merged into this entry',
            },
            sourceItems: {
              type: 'array',
              description: isFr
                ? 'Lignes d entree ayant contribue a la consolidation. Renseigne uniquement si sourceType est mixed.'
                : 'Input lines that contributed to this consolidation. Fill only when sourceType is mixed.',
              items: {
                type: 'object',
                required: [
                  'source',
                  'originalLabel',
                  'originalQuantityValue',
                  'originalQuantityUnit',
                ],
                properties: {
                  source: {
                    type: 'string',
                    enum: ['manual', 'recipe'],
                    description: isFr ? 'Tableau d origine de la ligne' : 'Origin array of the line',
                  },
                  originalLabel: {
                    type: 'string',
                    description: isFr
                      ? 'Label original de la ligne d entree'
                      : 'Original label of the input line',
                  },
                  originalQuantityValue: {
                    type: 'number',
                    description: isFr
                      ? 'Quantite originale avant consolidation'
                      : 'Original quantity before consolidation',
                  },
                  originalQuantityUnit: {
                    type: 'string',
                    description: isFr
                      ? 'Unite originale avant conversion'
                      : 'Original unit before conversion',
                  },
                },
              },
            },
          },
        },
      },
    },
  };
}

const AI_CONSOLIDATION_CATEGORIES = [
  { id: 'animaux',                  fr: 'Animaux',                    en: 'Pet Supplies'       },
  { id: 'bebe',                     fr: 'Bébé',                       en: 'Baby'               },
  { id: 'boissons',                 fr: 'Boissons',                   en: 'Beverages'          },
  { id: 'boucherie',                fr: 'Boucherie',                  en: 'Meat & Poultry'     },
  { id: 'boulangerie-viennoiserie', fr: 'Boulangerie & Viennoiserie', en: 'Bakery & Pastries'  },
  { id: 'conserves',                fr: 'Conserves',                  en: 'Canned Goods'       },
  { id: 'cremerie',                 fr: 'Crémerie',                   en: 'Dairy'              },
  { id: 'divers',                   fr: 'Divers',                     en: 'Miscellaneous'      },
  { id: 'entretien',                fr: 'Entretien',                  en: 'Household Cleaning' },
  { id: 'epicerie-salee',           fr: 'Épicerie salée',             en: 'Pantry'             },
  { id: 'epicerie-sucree',          fr: 'Épicerie sucrée',            en: 'Baking & Sweets'    },
  { id: 'fruits-et-legumes',        fr: 'Fruits et légumes',          en: 'Fresh Produce'      },
  { id: 'hygiene',                  fr: 'Hygiène',                    en: 'Personal Care'      },
  { id: 'maison',                   fr: 'Maison',                     en: 'Home & Stationery'  },
  { id: 'petit-dejeuner-et-gouter', fr: 'Petit-déjeuner et goûter',   en: 'Breakfast & Snacks' },
  { id: 'poissonnerie',             fr: 'Poissonnerie',               en: 'Fish & Seafood'     },
  { id: 'rayon-frais',              fr: 'Rayon frais',                en: 'Chilled'            },
  { id: 'surgeles',                 fr: 'Surgelés',                   en: 'Frozen'             },
];

function buildAiConsolidationUserPrompt(manualShoppingItems, recipeIngredients, lang, manualOnly = false) {
  const categoriesLine = AI_CONSOLIDATION_CATEGORIES
    .map((c) => `${c.id} (${lang === 'en' ? c.en : c.fr})`)
    .join(', ');
  if (lang === 'en') {
    return [
      manualOnly
        ? 'Manual-only mode: do not alter the input list. Do not merge, split, rename, remove, add, reorder, or change quantities/units. Only classify each input line into the most appropriate categoryId.'
        : 'Consolidate the two following arrays.',
      'summary.*OriginalLineCount must match the number of input lines used.',
      'For each consolidated line, fill in the manualOriginalLineCount and recipeOriginalLineCount counters used for that line.',
      `For each consolidated ingredient, assign a categoryId from: ${categoriesLine}.`,
      '',
      'manualShoppingItems:',
      JSON.stringify(manualShoppingItems),
      '',
      'recipeIngredients:',
      JSON.stringify(recipeIngredients),
    ].join('\n');
  }
  return [
    manualOnly
      ? 'Mode manuel uniquement : n altere pas la liste d entree. Ne fusionne pas, ne scinde pas, ne renomme pas, ne supprime pas, n ajoute pas, ne reordonne pas, et ne modifie pas les quantites/unites. Classe uniquement chaque ligne d entree dans le categoryId le plus pertinent.'
      : 'Consolide les deux tableaux suivants.',
    'summary.*OriginalLineCount doit correspondre au nombre de lignes d entree utilisees.',
    'Pour chaque ligne consolidee, renseigne les compteurs manualOriginalLineCount et recipeOriginalLineCount utilises pour cette ligne.',
    `Pour chaque ingredient consolide, assigne un categoryId parmi : ${categoriesLine}.`,
    '',
    'manualShoppingItems:',
    JSON.stringify(manualShoppingItems),
    '',
    'recipeIngredients:',
    JSON.stringify(recipeIngredients),
  ].join('\n');
}

function detectAiProvider(model) {
  return normalizeString(model).toLowerCase().startsWith('gemini') ? 'gemini' : 'anthropic';
}

async function callAnthropicConsolidation({ apiKey, model, systemPrompt, userPrompt, toolSchema, toolDescription }) {
  const body = {
    model,
    max_tokens: 5000,
    temperature: 0.1,
    system: systemPrompt,
    tools: [
      {
        name: AI_CONSOLIDATION_TOOL_NAME,
        description: toolDescription,
        input_schema: toolSchema,
      },
    ],
    tool_choice: { type: 'tool', name: AI_CONSOLIDATION_TOOL_NAME },
    messages: [{ role: 'user', content: userPrompt }],
  };

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new HttpsError(
      'unavailable',
      `Service IA indisponible (Anthropic ${response.status})`,
      { upstream: text.slice(0, 500) }
    );
  }

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    throw new HttpsError('internal', 'Réponse IA non JSON', { upstream: text.slice(0, 500) });
  }

  const toolBlock = Array.isArray(parsed.content)
    ? parsed.content.find((block) => block && block.type === 'tool_use')
    : null;
  if (!toolBlock || !toolBlock.input || typeof toolBlock.input !== 'object') {
    throw new HttpsError('internal', 'Réponse IA invalide (tool_use absent)');
  }
  return toolBlock.input;
}

async function callGeminiConsolidation({ apiKey, model, systemPrompt, userPrompt, toolSchema, toolDescription }) {
  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const body = {
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: 'user', parts: [{ text: userPrompt }] }],
    tools: [
      {
        function_declarations: [
          {
            name: AI_CONSOLIDATION_TOOL_NAME,
            description: toolDescription,
            parameters: toolSchema,
          },
        ],
      },
    ],
    tool_config: { function_calling_config: { mode: 'ANY' } },
    generation_config: {
      temperature: 0.1,
      maxOutputTokens: 32000,
      thinkingConfig: { thinkingBudget: 0 },
    },
  };

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new HttpsError(
      'unavailable',
      `Service IA indisponible (Gemini ${response.status})`,
      { upstream: text.slice(0, 500) }
    );
  }

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    throw new HttpsError('internal', 'Réponse IA non JSON', { upstream: text.slice(0, 500) });
  }

  const candidate = parsed?.candidates?.[0];
  const finishReason = candidate?.finishReason;
  if (finishReason === 'MAX_TOKENS') {
    console.error('callGeminiConsolidation: MAX_TOKENS reached', { finishReason });
    throw new HttpsError('internal', 'Réponse IA tronquée (liste trop longue)');
  }

  const parts = candidate?.content?.parts;
  const funcPart = Array.isArray(parts)
    ? parts.find((p) => p && p.functionCall && p.functionCall.args)
    : null;
  if (!funcPart) {
    console.error('callGeminiConsolidation: no functionCall', { finishReason, parts: JSON.stringify(parts)?.slice(0, 500) });
    throw new HttpsError('internal', 'Réponse IA invalide (functionCall absent)');
  }
  return funcPart.functionCall.args;
}

/**
 * Core helper: consolidates a manual shopping list with recipe ingredients
 * using either an Anthropic Claude model or a Google Gemini model.
 *
 * Mirrors `scripts/ia/antropic_shopping_consolidate.ps1` exactly:
 *   - Same system prompt, user prompt and JSON Schema.
 *   - Same per-provider request body (tools / tool_choice / generation_config).
 *
 * @param {Object} params
 * @param {string} params.model - e.g. 'gemini-2.5-flash' or 'claude-haiku-4-5-20251001'.
 * @param {Array<{label:string,quantityValue:number,quantityUnit:string}>} params.manualShoppingItems
 * @param {Array<{label:string,quantityValue:number,quantityUnit:string}>} params.recipeIngredients
 * @param {'fr'|'en'} [params.lang='fr'] - Language for prompts and item labels in the output.
 * @returns {Promise<{summary:object, consolidatedItems:Array<object>}>}
 */
async function consolidateShoppingListWithAi({
  model,
  manualShoppingItems,
  recipeIngredients,
  lang = 'fr',
  manualOnly = false,
}) {
  const cleanModel = normalizeString(model);
  if (!cleanModel) {
    throw new HttpsError('invalid-argument', 'Modèle IA requis');
  }
  const provider = detectAiProvider(cleanModel);
  const apiKey =
    provider === 'anthropic'
      ? normalizeString(process.env.ANTHROPIC_API_KEY)
      : normalizeString(process.env.GOOGLE_AI_API_KEY);
  if (!apiKey) {
    throw new HttpsError(
      'failed-precondition',
      `Clé API ${provider === 'anthropic' ? 'Anthropic' : 'Google AI'} non configurée`
    );
  }

  const validLang = lang === 'en' ? 'en' : 'fr';
  const systemPrompt = buildAiConsolidationSystemPrompt(validLang);
  const toolDescription = buildAiConsolidationToolDescription(validLang);
  const toolSchema = buildAiConsolidationToolSchema(validLang);
  const userPrompt = buildAiConsolidationUserPrompt(
    manualShoppingItems,
    recipeIngredients,
    validLang,
    manualOnly
  );

  const result =
    provider === 'anthropic'
      ? await callAnthropicConsolidation({
          apiKey,
          model: cleanModel,
          systemPrompt,
          userPrompt,
          toolSchema,
          toolDescription,
        })
      : await callGeminiConsolidation({
          apiKey,
          model: cleanModel,
          systemPrompt,
          userPrompt,
          toolSchema,
          toolDescription,
        });

  const summary = result?.summary && typeof result.summary === 'object' ? result.summary : {};
  const consolidatedItems = Array.isArray(result?.consolidatedItems)
    ? result.consolidatedItems
    : [];
  return { summary, consolidatedItems };
}

function toFiniteQuantity(value) {
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? n : 0;
}

function buildAiInputRow(rawLabel, rawQuantityValue, rawQuantityUnit) {
  const label = normalizeString(rawLabel);
  if (!label) return null;
  return {
    label,
    quantityValue: toFiniteQuantity(rawQuantityValue),
    quantityUnit: normalizeString(rawQuantityUnit) || 'unit',
  };
}

/**
 * POC callable: consolidates a trip's shopping list with AI-driven merging.
 *
 * Reads from Firestore (no writes):
 *   - Manual items: `trips/{tripId}/shoppingItems` where `checked == false`.
 *   - Recipe items: `trips/{tripId}/meals` where `mealMode == 'cooked'`,
 *     flattened from each component's `ingredients` array.
 *
 * The chosen model is hard-coded to `gemini-2.5-flash` for this POC.
 */
exports.consolidateTripShoppingWithAi = onCall(
  {
    timeoutSeconds: 120,
    memory: '512MiB',
    secrets: ['ANTHROPIC_API_KEY', 'GOOGLE_AI_API_KEY'],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }

    const tripId = normalizeString(request.data?.tripId);
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'tripId requis');
    }

    const db = admin.firestore();
    const userSnap = await db.collection('users').doc(uid).get();
    const isApplicationOwner = userSnap.exists && userSnap.data()?.isApplicationOwner === true;

    const tripRef = db.collection('trips').doc(tripId);
    const mode = normalizeString(request.data?.mode);
    const manualOnly = mode === 'manual_only';

    const [shoppingSnap, mealsSnap] = await Promise.all([
      tripRef
        .collection('shoppingItems')
        .where('checked', '==', false)
        .select('label', 'quantityValue', 'quantityUnit')
        .get(),
      manualOnly
        ? Promise.resolve({ docs: [] })
        : tripRef
            .collection('meals')
            .where('mealMode', '==', 'cooked')
            .select('components')
            .get(),
    ]);

    const manualShoppingItems = [];
    for (const doc of shoppingSnap.docs) {
      const data = doc.data() || {};
      const row = buildAiInputRow(data.label, data.quantityValue, data.quantityUnit);
      if (row) manualShoppingItems.push(row);
    }

    const recipeIngredients = [];
    for (const doc of mealsSnap.docs) {
      const components = (doc.data() || {}).components;
      if (!Array.isArray(components)) continue;
      for (const component of components) {
        const ingredients = component && Array.isArray(component.ingredients)
          ? component.ingredients
          : null;
        if (!ingredients) continue;
        for (const ingredient of ingredients) {
          if (!ingredient || typeof ingredient !== 'object') continue;
          const row = buildAiInputRow(
            ingredient.label,
            ingredient.quantityValue,
            ingredient.quantityUnit
          );
          if (row) recipeIngredients.push(row);
        }
      }
    }

    if (manualShoppingItems.length === 0 && recipeIngredients.length === 0) {
      return {
        summary: { manualOriginalLineCount: 0, recipeOriginalLineCount: 0 },
        consolidatedItems: [],
      };
    }

    const rawLang = normalizeString(request.data?.lang);
    const lang = rawLang === 'en' ? 'en' : 'fr';

    return withAiQuota(
      { featureKey: 'shoppingConsolidation', tripId, uid, isApplicationOwner },
      async () => {
        const { summary, consolidatedItems } = await consolidateShoppingListWithAi({
          model: 'gemini-2.5-flash',
          manualShoppingItems,
          recipeIngredients,
          lang,
          manualOnly,
        });
        return { summary, consolidatedItems, categories: AI_CONSOLIDATION_CATEGORIES };
      }
    );
  }
);

// ============================================================
// AI quota management callables (used by CF-assisted features)
// ============================================================

/**
 * Atomically checks and increments AI usage quota for the calling user and
 * the given trip. Throws resource-exhausted if any quota is exceeded.
 *
 * Request: { featureKey: string, tripId: string }
 * Response: { ok: true }
 */
exports.reserveAiQuota = onCall(
  { timeoutSeconds: 30, memory: '256MiB' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }

    const featureKey = normalizeString(request.data?.featureKey);
    const tripId = normalizeString(request.data?.tripId);
    if (!featureKey || !tripId) {
      throw new HttpsError('invalid-argument', 'featureKey et tripId requis');
    }

    await reserveQuota({ featureKey, tripId, uid });
    return { ok: true };
  }
);

/**
 * Decrements AI usage quota counters (floor at 0) after a failed AI call.
 * Best-effort: always returns ok regardless of internal errors.
 *
 * Request: { featureKey: string, tripId: string }
 * Response: { ok: true }
 */
exports.refundAiQuota = onCall(
  { timeoutSeconds: 30, memory: '256MiB' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }

    const featureKey = normalizeString(request.data?.featureKey);
    const tripId = normalizeString(request.data?.tripId);
    if (!featureKey || !tripId) {
      throw new HttpsError('invalid-argument', 'featureKey et tripId requis');
    }

    await refundQuota({ featureKey, tripId, uid }).catch(() => {});
    return { ok: true };
  }
);

/**
 * Translates a text from one language to another using Google Cloud Translation.
 * Restricted to users with isApplicationOwner === true in Firestore.
 */
exports.translateTextWithGoogleCloud = onCall(
  {
    timeoutSeconds: 30,
    memory: '256MiB',
    secrets: ['GOOGLE_CLOUD_TRANSLATION_API_KEY'],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }

    const db = admin.firestore();
    const userSnap = await db.collection('users').doc(uid).get();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    if (userData.isApplicationOwner !== true) {
      throw new HttpsError('permission-denied', 'Accès réservé aux administrateurs');
    }

    const input = request.data || {};
    const text = normalizeString(input.text);
    const sourceLanguage = normalizeLanguageCode(input.sourceLanguage);
    const targetLanguage = normalizeLanguageCode(input.targetLanguage);

    if (!text) {
      throw new HttpsError('invalid-argument', 'Le texte à traduire est requis');
    }
    if (!targetLanguage) {
      throw new HttpsError('invalid-argument', 'La langue cible est invalide');
    }
    if (text.length > 8000) {
      throw new HttpsError(
        'invalid-argument',
        'Le texte dépasse la limite autorisée (8000 caractères)'
      );
    }

    const apiKey = process.env.GOOGLE_CLOUD_TRANSLATION_API_KEY;
    if (!apiKey) {
      throw new HttpsError(
        'failed-precondition',
        'Secret GOOGLE_CLOUD_TRANSLATION_API_KEY manquant'
      );
    }

    /** @type {Record<string, unknown>} */
    const payload = {
      q: text,
      target: targetLanguage,
      format: 'text',
    };
    if (sourceLanguage) {
      payload.source = sourceLanguage;
    }

    let response;
    try {
      response = await fetch(
        `https://translation.googleapis.com/language/translate/v2?key=${encodeURIComponent(apiKey)}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        }
      );
    } catch {
      throw new HttpsError('unavailable', 'Service de traduction indisponible');
    }

    let responseBody;
    try {
      responseBody = await response.json();
    } catch {
      responseBody = null;
    }

    if (!response.ok) {
      const apiMessage = normalizeString(
        responseBody &&
          typeof responseBody === 'object' &&
          responseBody.error &&
          typeof responseBody.error === 'object'
          ? responseBody.error.message
          : ''
      );
      throw new HttpsError(
        'internal',
        apiMessage || 'La traduction a échoué'
      );
    }

    const firstTranslation =
      responseBody &&
      typeof responseBody === 'object' &&
      responseBody.data &&
      typeof responseBody.data === 'object' &&
      Array.isArray(responseBody.data.translations) &&
      responseBody.data.translations.length > 0
        ? responseBody.data.translations[0]
        : null;

    const translatedText = normalizeString(
      firstTranslation && typeof firstTranslation === 'object'
        ? firstTranslation.translatedText
        : ''
    );
    const detectedSourceLanguage = normalizeString(
      firstTranslation && typeof firstTranslation === 'object'
        ? firstTranslation.detectedSourceLanguage
        : ''
    );

    if (!translatedText) {
      throw new HttpsError('internal', 'Réponse de traduction invalide');
    }

    return {
      translatedText,
      sourceLanguage: sourceLanguage || detectedSourceLanguage || null,
      targetLanguage,
    };
  }
);

const CLEANUP_ORPHAN_ADMIN_DISMISSES_SOURCE =
  'cleanupOrphanAdminAnnouncementDismisses';

/**
 * Weekly job: removes each user's dismissedAdminAnnouncements sub-docs when the
 * matching adminAnnouncements/{id} document no longer exists.
 *
 * Region override: Cloud Scheduler has no europe-west9; Gen2 binds the scheduler
 * job to the function region, so deploy fails if we inherit europe-west9 here.
 * Cron still runs at 03:00 Europe/Paris via timeZone.
 */
exports.cleanupOrphanAdminAnnouncementDismisses = onSchedule(
  {
    region: 'europe-west1',
    schedule: '0 3 * * 3',
    timeZone: 'Europe/Paris',
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async () => {
    const db = admin.firestore();
    try {
      const adminAnnouncementRefs = await db
        .collection('adminAnnouncements')
        .listDocuments();
      const livingIds = new Set(
        adminAnnouncementRefs.map((documentReference) => documentReference.id)
      );

      const dismissSnap = await db
        .collectionGroup('dismissedAdminAnnouncements')
        .get();
      const dismissDocs = dismissSnap.docs.map((documentSnapshot) => ({
        id: documentSnapshot.id,
        path: documentSnapshot.ref.path,
      }));
      const orphans = collectOrphanDismissDocs(livingIds, dismissDocs);

      let writeBatch = db.batch();
      let batchOperations = 0;
      for (const orphanEntry of orphans) {
        writeBatch.delete(db.doc(orphanEntry.refPath));
        batchOperations++;
        if (batchOperations >= 500) {
          await writeBatch.commit();
          writeBatch = db.batch();
          batchOperations = 0;
        }
      }
      if (batchOperations > 0) {
        await writeBatch.commit();
      }

      const distinctUserIds = new Set(orphans.map((o) => o.userId));
      await insertApplicationLog(db, {
        level: 'info',
        source: CLEANUP_ORPHAN_ADMIN_DISMISSES_SOURCE,
        message: `Nettoyage des dismiss d'annonces admin orphelins terminé : ${orphans.length} document(s) supprimé(s) chez ${distinctUserIds.size} utilisateur(s).`,
        details: {
          orphansDeleted: orphans.length,
          usersAffected: distinctUserIds.size,
          livingAnnouncementCount: livingIds.size,
        },
      });
    } catch (err) {
      const errorMessage =
        err && typeof err.message === 'string' ? err.message : String(err);
      const errorStack =
        err && typeof err.stack === 'string' ? err.stack : '';
      try {
        await insertApplicationLog(db, {
          level: 'error',
          source: CLEANUP_ORPHAN_ADMIN_DISMISSES_SOURCE,
          message: `Échec du nettoyage des dismiss d'annonces admin orphelins : ${errorMessage}`,
          details: {
            errorMessage:
              errorMessage.length > 8000
                ? `${errorMessage.slice(0, 7997)}...`
                : errorMessage,
            errorStack:
              errorStack.length > 8000
                ? `${errorStack.slice(0, 7997)}...`
                : errorStack,
          },
        });
      } catch (logErr) {
        console.error(
          'cleanupOrphanAdminAnnouncementDismisses: failed to write application log',
          logErr
        );
      }
      throw err;
    }
  }
);

/**
 * Callable: persists to applicationLogs (structured audit / diagnostics).
 * Restricted to users with isApplicationOwner === true in Firestore.
 */
exports.insertApplicationLogCallable = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
  }

  const db = admin.firestore();
  const userSnap = await db.collection('users').doc(uid).get();
  const userData = userSnap.exists ? userSnap.data() || {} : {};
  if (userData.isApplicationOwner !== true) {
    throw new HttpsError(
      'permission-denied',
      'Accès réservé aux administrateurs'
    );
  }

  const payload = request.data || {};
  try {
    await insertApplicationLog(db, {
      level: payload.level,
      source: payload.source,
      message: payload.message,
      details: payload.details,
    });
  } catch (e) {
    const msg = e && typeof e.message === 'string' ? e.message : String(e);
    throw new HttpsError('invalid-argument', msg || 'Payload invalide');
  }

  return { ok: true };
});

// ---------------------------------------------------------------------------
// participantCount — maintained automatically via Firestore triggers.
// Counts all participant docs (real users + placeholders) for display in the
// trip list. No existing function needs to be updated.
// ---------------------------------------------------------------------------

exports.onTripParticipantCreated = onDocumentCreated(
  'trips/{tripId}/participants/{participantId}',
  async (event) => {
    const tripId = event.params.tripId;
    await admin.firestore().collection('trips').doc(tripId).update({
      participantCount: FieldValue.increment(1),
    });
  }
);

exports.onTripParticipantDeleted = onDocumentDeleted(
  'trips/{tripId}/participants/{participantId}',
  async (event) => {
    const tripId = event.params.tripId;
    const tripRef = admin.firestore().collection('trips').doc(tripId);
    const snap = await tripRef.get();
    if (!snap.exists) return;
    const current = snap.data().participantCount;
    await tripRef.update({
      participantCount: typeof current === 'number' && current > 1
        ? FieldValue.increment(-1)
        : FieldValue.delete(),
    });
  }
);

const {
  recomputeExpenseGroupSettlement,
  markExpenseReimbursementPaid,
  unmarkExpenseReimbursementPaid,
  deleteExpenseGroup,
  refreshExpenseGroupSettlement,
} = require('./expense_settlement_recalc');

exports.recomputeExpenseGroupSettlement = recomputeExpenseGroupSettlement;
exports.markExpenseReimbursementPaid = markExpenseReimbursementPaid;
exports.unmarkExpenseReimbursementPaid = unmarkExpenseReimbursementPaid;
exports.deleteExpenseGroup = deleteExpenseGroup;
exports.refreshExpenseGroupSettlement = refreshExpenseGroupSettlement;

const {
  computeActivityDrivingRouteFromTrip,
  recomputeActivityDrivingRoutesOnTripAddressChange,
  refreshActivityDrivingRoute,
} = require('./activity_driving_route');

exports.computeActivityDrivingRouteFromTrip = computeActivityDrivingRouteFromTrip;
exports.recomputeActivityDrivingRoutesOnTripAddressChange =
  recomputeActivityDrivingRoutesOnTripAddressChange;
exports.refreshActivityDrivingRoute = refreshActivityDrivingRoute;

