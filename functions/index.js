const admin = require('firebase-admin');
const {
  onDocumentCreated,
  onDocumentWritten,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const cheerio = require('cheerio');

const { setGlobalOptions } = require('firebase-functions/v2');

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

/** Text before @ for public trip member chips (empty if unusable). */
function emailLocalPart(email) {
  const e = normalizeString(email);
  if (!e) return '';
  const at = e.indexOf('@');
  return at > 0 ? e.slice(0, at).trim() : e;
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
  return (
    h === 'maps.google.com' ||
    (h === 'www.google.com' && url.pathname.startsWith('/maps'))
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
      const photoRes = await fetch(
        `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=800&key=${apiKey}`,
        { redirect: 'follow' }
      );
      if (photoRes.ok) {
        imageUrl = photoRes.url;
      }
    }

    return { title, description, imageUrl };
  } catch {
    return null;
  }
}

/** @param {FirebaseFirestore.DocumentData} data */
function memberIdsAsSet(data) {
  const raw = data.memberIds;
  if (!Array.isArray(raw)) return new Set();
  return new Set(raw.map((v) => String(v)));
}

/** Trip planner placeholders: ids in trip.memberIds until a guest claims one. */
function isPlaceholderMemberId(id) {
  const s = normalizeString(id);
  return s.startsWith('ph_') && s.length > 8;
}

function newTripPlaceholderMemberId() {
  return `ph_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
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
  if (normalizeString(data.ownerId) === cleanUid) return 2;
  return tripAdminMemberIdSet(data).has(cleanUid) ? 1 : 0;
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

function assertTripParticipantPermission({
  tripData,
  uid,
  permissionKey,
  fallbackRole,
  deniedMessage,
}) {
  const memberIds = Array.isArray(tripData.memberIds)
    ? tripData.memberIds.map((v) => String(v))
    : [];
  if (!memberIds.includes(uid)) {
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

/**
 * When a placeholder row becomes a real uid in memberIds, carry co-admin from
 * ph_* to uid in adminMemberIds. Returns null if the field needs no update.
 * @param {unknown} adminIdsRaw
 * @param {string} phId
 * @param {string} uid
 * @returns {string[] | null}
 */
function adminMemberIdsAfterPlaceholderClaim(adminIdsRaw, phId, uid) {
  const raw = Array.isArray(adminIdsRaw)
    ? adminIdsRaw.map((v) => String(v))
    : [];
  if (!raw.includes(phId)) return null;
  return [...new Set(raw.map((id) => (id === phId ? uid : id)))];
}

/**
 * Undo {@link adminMemberIdsAfterPlaceholderClaim} when claim migration fails.
 * @param {unknown} adminIdsRaw
 * @param {string} uid
 * @param {string} phId
 * @returns {string[] | null}
 */
function adminMemberIdsAfterRevertClaim(adminIdsRaw, uid, phId) {
  const raw = Array.isArray(adminIdsRaw)
    ? adminIdsRaw.map((v) => String(v))
    : [];
  if (!raw.includes(uid)) return null;
  return [...new Set(raw.map((id) => (id === uid ? phId : id)))];
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
 * Rewires [fromId] to [toId] in expense groups, expenses, rooms, and meals.
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} fromId
 * @param {string} toId
 */
async function migrateTripMemberIdReferences(tripRef, fromId, toId) {
  const db = admin.firestore();
  const [groupsSnap, expensesSnap, roomsSnap, mealsSnap] = await Promise.all([
    tripRef.collection('expenseGroups').get(),
    tripRef.collection('expenses').get(),
    tripRef.collection('rooms').get(),
    tripRef.collection('meals').get(),
  ]);

  /** @type {{ ref: FirebaseFirestore.DocumentReference, data: Record<string, unknown> }[]} */
  const updates = [];

  for (const doc of groupsSnap.docs) {
    const vis = doc.data().visibleToMemberIds;
    if (!Array.isArray(vis) || !vis.map(String).includes(fromId)) continue;
    const next = [
      ...new Set(vis.map((id) => (String(id) === fromId ? toId : String(id)))),
    ];
    updates.push({ ref: doc.ref, data: { visibleToMemberIds: next } });
  }

  for (const doc of expensesSnap.docs) {
    const exp = doc.data() || {};
    const participants = (
      Array.isArray(exp.participantIds) ? exp.participantIds : []
    ).map(String);
    const paidBy = normalizeString(exp.paidBy);
    let dirty = false;
    let newParticipants = participants;
    if (participants.includes(fromId)) {
      newParticipants = [
        ...new Set(participants.map((id) => (id === fromId ? toId : id))),
      ];
      dirty = true;
    }
    let newPaidBy = paidBy;
    if (paidBy === fromId) {
      newPaidBy = toId;
      dirty = true;
    }

    /** @type {Record<string, unknown>} */
    const expUpdate = {};
    if (dirty) {
      expUpdate.participantIds = newParticipants;
      expUpdate.paidBy = newPaidBy;
    }

    const sharesRaw = exp.participantShares;
    if (
      sharesRaw &&
      typeof sharesRaw === 'object' &&
      !Array.isArray(sharesRaw) &&
      Object.prototype.hasOwnProperty.call(sharesRaw, fromId)
    ) {
      const nextShares = { ...sharesRaw };
      const v = nextShares[fromId];
      delete nextShares[fromId];
      nextShares[toId] = v;
      expUpdate.participantShares = nextShares;
      dirty = true;
    }

    if (dirty) {
      updates.push({ ref: doc.ref, data: expUpdate });
    }
  }

  for (const doc of roomsSnap.docs) {
    const data = doc.data() || {};
    const bedsRaw = Array.isArray(data.beds) ? data.beds : [];
    let roomDirty = false;
    const newBeds = bedsRaw.map((bed) => {
      if (!bed || typeof bed !== 'object') return bed;
      const ids = Array.isArray(bed.assignedMemberIds)
        ? bed.assignedMemberIds.map(String)
        : [];
      if (!ids.includes(fromId)) return bed;
      roomDirty = true;
      const rep = [...new Set(ids.map((id) => (id === fromId ? toId : id)))];
      return { ...bed, assignedMemberIds: rep };
    });
    /** @type {Record<string, unknown>} */
    const newData = {};
    if (roomDirty) {
      newData.beds = newBeds;
    }
    const legacy = Array.isArray(data.assignedMemberIds)
      ? data.assignedMemberIds.map(String)
      : [];
    if (legacy.includes(fromId)) {
      roomDirty = true;
      newData.assignedMemberIds = [
        ...new Set(legacy.map((id) => (id === fromId ? toId : id))),
      ];
    }
    if (roomDirty && Object.keys(newData).length > 0) {
      updates.push({ ref: doc.ref, data: newData });
    }
  }

  for (const doc of mealsSnap.docs) {
    const meal = doc.data() || {};
    const participants = (
      Array.isArray(meal.participantIds) ? meal.participantIds : []
    )
      .map((v) => String(v).trim())
      .filter((id) => id.length > 0);
    const chefParticipantId = normalizeString(meal.chefParticipantId);
    let dirty = false;

    let newParticipants = participants;
    if (participants.includes(fromId)) {
      newParticipants = [
        ...new Set(participants.map((id) => (id === fromId ? toId : id))),
      ];
      dirty = true;
    } else {
      newParticipants = [...new Set(participants)];
    }

    let newChefParticipantId = chefParticipantId;
    if (chefParticipantId === fromId) {
      newChefParticipantId = toId;
      dirty = true;
    }
    if (
      newChefParticipantId &&
      !newParticipants.includes(newChefParticipantId)
    ) {
      newChefParticipantId = null;
      dirty = true;
    }

    if (!dirty) continue;
    updates.push({
      ref: doc.ref,
      data: {
        participantIds: newParticipants,
        chefParticipantId: newChefParticipantId || null,
      },
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
 * @param {string} uid
 * @param {string} phId
 */
async function revertTripMemberClaim(tripRef, uid, phId) {
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(tripRef);
    if (!snap.exists) return;
    const data = snap.data() || {};
    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid)) return;
    const newMemberIds = memberIds.map((id) => (id === uid ? phId : id));
    const FieldValue = admin.firestore.FieldValue;
    /** @type {Record<string, unknown>} */
    const upd = {
      memberIds: newMemberIds,
      updatedAt: FieldValue.serverTimestamp(),
    };
    const nextAdmins = adminMemberIdsAfterRevertClaim(
      data.adminMemberIds,
      uid,
      phId
    );
    if (nextAdmins) {
      upd.adminMemberIds = nextAdmins;
    }
    tx.update(tripRef, upd);
  });
}

/**
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} phId
 */
async function assertPlaceholderUnusedInExpensesAndRooms(tripRef, phId) {
  const [expensesSnap, roomsSnap] = await Promise.all([
    tripRef.collection('expenses').get(),
    tripRef.collection('rooms').get(),
  ]);

  for (const doc of expensesSnap.docs) {
    const exp = doc.data() || {};
    const participants = (
      Array.isArray(exp.participantIds) ? exp.participantIds : []
    ).map(String);
    const paidBy = normalizeString(exp.paidBy);
    const shares = exp.participantShares;
    const inShares =
      shares &&
      typeof shares === 'object' &&
      !Array.isArray(shares) &&
      Object.prototype.hasOwnProperty.call(shares, phId);
    if (participants.includes(phId) || paidBy === phId || inShares) {
      throw new HttpsError(
        'failed-precondition',
        'Ce voyageur prévu est encore utilisé dans des dépenses. Retire-le des participants avant de le supprimer.'
      );
    }
  }

  for (const doc of roomsSnap.docs) {
    const data = doc.data() || {};
    const bedsRaw = Array.isArray(data.beds) ? data.beds : [];
    for (const bed of bedsRaw) {
      if (!bed || typeof bed !== 'object') continue;
      const ids = Array.isArray(bed.assignedMemberIds)
        ? bed.assignedMemberIds.map(String)
        : [];
      if (ids.includes(phId)) {
        throw new HttpsError(
          'failed-precondition',
          'Ce voyageur prévu est encore assigné à une chambre. Retire l\'assignation avant de le supprimer.'
        );
      }
    }
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
        'Ce membre est créateur d’un poste de dépense. Transfère ou supprime ce poste avant de le supprimer.'
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
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} memberId
 * @param {FirebaseFirestore.DocumentData} tripData
 */
async function assertMemberRemovalBlockingDependencies({
  tripRef,
  memberId,
  tripData,
}) {
  const [expensesSnap, roomsSnap, mealsSnap, groupsSnap] = await Promise.all([
    tripRef.collection('expenses').get(),
    tripRef.collection('rooms').get(),
    tripRef.collection('meals').get(),
    tripRef.collection('expenseGroups').get(),
  ]);
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
  const FieldValue = admin.firestore.FieldValue;
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
 * When someone is added to trip.memberIds, add them to every expense post
 * (visibleToMemberIds) and every expense (participantIds). arrayUnion is
 * idempotent. Batched in chunks of 500 writes.
 * @param {FirebaseFirestore.DocumentReference} tripRef
 * @param {string} uid
 */
async function backfillTripMemberInExpenseSubcollections(tripRef, uid) {
  const FieldValue = admin.firestore.FieldValue;
  const db = admin.firestore();

  const [groupsSnap, expensesSnap] = await Promise.all([
    tripRef.collection('expenseGroups').get(),
    tripRef.collection('expenses').get(),
  ]);

  const updates = [];
  for (const doc of groupsSnap.docs) {
    updates.push({
      ref: doc.ref,
      data: { visibleToMemberIds: FieldValue.arrayUnion(uid) },
    });
  }
  for (const doc of expensesSnap.docs) {
    updates.push({
      ref: doc.ref,
      data: { participantIds: FieldValue.arrayUnion(uid) },
    });
  }

  let batch = db.batch();
  let n = 0;
  for (const { ref, data } of updates) {
    batch.update(ref, data);
    n++;
    if (n >= 500) {
      await batch.commit();
      batch = db.batch();
      n = 0;
    }
  }
  if (n > 0) {
    await batch.commit();
  }
}

const FCM_INVALID_TOKEN_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

const TRIP_NOTIFICATION_CHANNELS = Object.freeze({
  MESSAGES: 'messages',
  ACTIVITIES: 'activities',
  ANNOUNCEMENTS: 'announcements',
  CUPIDON: 'cupidon',
});

const ANDROID_CHANNEL_IDS = Object.freeze({
  messages: 'planerz_messages',
  activities: 'planerz_activities',
  announcements: 'planerz_announcements',
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
        updatedAt instanceof admin.firestore.Timestamp
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
  const FieldValue = admin.firestore.FieldValue;
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
  /** @type {{ token: string, ref: FirebaseFirestore.DocumentReference }[]} */
  const tokenEntries = [];
  /** @type {Map<string, FirebaseFirestore.DocumentReference>} */
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
          const t = normalizeString((doc.data() || {}).token);
          if (t && !byToken.has(t)) {
            byToken.set(t, doc.ref);
          }
        }
      } catch (e) {
        console.warn('collectRecipientTokenEntries', uid, e);
      }
    })
  );
  for (const [token, ref] of byToken.entries()) {
    tokenEntries.push({ token, ref });
  }
  return tokenEntries;
}

async function markFunctionEventProcessedOnce(functionName, eventId) {
  const cleanFunction = normalizeString(functionName);
  const cleanEventId = normalizeString(eventId);
  if (!cleanFunction || !cleanEventId) {
    return true;
  }
  const db = admin.firestore();
  const lockRef = db
    .collection('functionEventLocks')
    .doc(`${cleanFunction}__${cleanEventId}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(lockRef);
    if (snap.exists) {
      return false;
    }
    tx.set(lockRef, {
      functionName: cleanFunction,
      eventId: cleanEventId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
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
 * Trip list / shell badge total: messages + activities only (Cupidon is profile-only).
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
  const msgs =
    typeof msgsRaw === 'number' ? msgsRaw : Number(msgsRaw) || 0;
  const acts =
    typeof actsRaw === 'number' ? actsRaw : Number(actsRaw) || 0;
  const announcements =
    typeof announcementsRaw === 'number'
      ? announcementsRaw
      : Number(announcementsRaw) || 0;
  return msgs + acts + announcements;
}

function channelReadTimestamp(data, channel) {
  const channels = channelsMap(data);
  const raw = channels[channel];
  if (raw instanceof admin.firestore.Timestamp) {
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
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
      event.createdAt instanceof admin.firestore.Timestamp
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
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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

async function resolveTripMemberLabel(tripData, uid) {
  const labels =
    tripData.memberPublicLabels && typeof tripData.memberPublicLabels === 'object'
      ? tripData.memberPublicLabels
      : {};
  const fromTrip = normalizeString(labels[uid]);
  if (fromTrip) return fromTrip;
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
  tripTitle,
  notifiedUid,
  otherLabel,
  otherPhotoUrl,
}) {
  const cleanTripTitle = normalizeString(tripTitle);
  const cleanOtherLabel = normalizeString(otherLabel);
  const cleanOtherPhotoUrl = normalizeString(otherPhotoUrl);
  await admin.firestore().collection('notificationQueue').add({
    channel: TRIP_NOTIFICATION_CHANNELS.CUPIDON,
    type: CUPIDON_MATCH_TYPE,
    tripId: normalizeString(tripId),
    actorId: normalizeString(notifiedUid),
    targetPath: '/account/cupidon',
    title: `Mode Cupidon · ${cleanTripTitle || 'Voyage'}`,
    body: `Match mutuel avec ${cleanOtherLabel || "quelqu'un"}`,
    candidateRecipients: [normalizeString(notifiedUid)],
    skipPresenceCheck: true,
    androidChannelId: ANDROID_CHANNEL_IDS.cupidon,
    payload: {
      tripTitle: cleanTripTitle,
      otherLabel: cleanOtherLabel,
      ...(cleanOtherPhotoUrl ? { otherPhotoUrl: cleanOtherPhotoUrl } : {}),
    },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Generic notification dispatcher. Reads a notificationQueue document,
 * applies presence filtering (when applicable), increments per-trip unread
 * counters, and delivers FCM messages to all eligible recipient tokens.
 * Deletes the queue document after processing.
 */
exports.dispatchNotificationQueue = onDocumentCreated(
  {
    document: 'notificationQueue/{notifId}',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (event) => {
    const proceed = await markFunctionEventProcessedOnce(
      'dispatchNotificationQueue',
      event.id
    );
    if (!proceed) return;

    const snap = event.data;
    if (!snap) return;

    const data = snap.data() || {};
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
      await snap.ref.delete();
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

    const db = admin.firestore();
    const tokenEntries = await collectRecipientTokenEntries(db, recipients);
    if (tokenEntries.length > 0) {
      const createdAt =
        data.createdAt instanceof admin.firestore.Timestamp
          ? data.createdAt
          : undefined;

      const messages = tokenEntries.map(({ token }) => {
        /** @type {admin.messaging.Message} */
        const msg = {
          token,
          notification: { title, body },
          data: buildTripNotificationEventData({
            channel,
            tripId,
            actorId,
            type,
            targetPath,
            createdAt,
            payload,
          }),
        };
        if (androidChannelId) {
          msg.android = { notification: { channelId: androidChannelId } };
        }
        return msg;
      });

      const result = await admin.messaging().sendEach(messages);
      await cleanupInvalidFcmTokens(db, result, tokenEntries);
    }

    await snap.ref.delete();
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
    const proceed = await markFunctionEventProcessedOnce(
      'notifyTripMessageRecipients',
      event.id
    );
    if (!proceed) return;

    const snap = event.data;
    if (!snap) return;

    const tripId = event.params.tripId;
    const msg = snap.data() || {};
    const authorId = normalizeString(msg.authorId);
    const text = normalizeString(msg.text).slice(0, 180);

    if (!authorId || !text) return;

    const db = admin.firestore();
    const tripSnap = await db.collection('trips').doc(tripId).get();
    if (!tripSnap.exists) return;

    const trip = tripSnap.data() || {};
    const memberIds = Array.isArray(trip.memberIds)
      ? trip.memberIds.map((v) => String(v))
      : [];
    const candidateRecipients = memberIds.filter((id) => id && id !== authorId);
    if (candidateRecipients.length === 0) return;

    const tripTitle = normalizeString(trip.title) || 'Voyage';
    let authorLabel = await resolveTripMemberLabel(trip, authorId);
    if (!authorLabel) authorLabel = "Quelqu'un";

    await db.collection('notificationQueue').add({
      channel: TRIP_NOTIFICATION_CHANNELS.MESSAGES,
      type: 'trip_message',
      tripId,
      actorId: authorId,
      targetPath: `/trips/${tripId}/messages`,
      title: `Messagerie · ${tripTitle}`,
      body: `${authorLabel} : ${text}`,
      candidateRecipients,
      skipPresenceCheck: false,
      androidChannelId: ANDROID_CHANNEL_IDS.messages,
      payload: {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
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
    const proceed = await markFunctionEventProcessedOnce(
      'notifyTripActivityRecipients',
      event.id
    );
    if (!proceed) return;

    const snap = event.data;
    if (!snap) return;

    const tripId = event.params.tripId;
    const activity = snap.data() || {};
    const actorId = normalizeString(activity.createdBy);
    const label = normalizeString(activity.label).slice(0, 180);
    if (!actorId || !label) return;

    const db = admin.firestore();
    const tripSnap = await db.collection('trips').doc(tripId).get();
    if (!tripSnap.exists) return;

    const trip = tripSnap.data() || {};
    const memberIds = Array.isArray(trip.memberIds)
      ? trip.memberIds.map((v) => String(v))
      : [];
    const candidateRecipients = memberIds.filter((id) => id && id !== actorId);
    if (candidateRecipients.length === 0) return;

    const tripTitle = normalizeString(trip.title) || 'Voyage';
    let actorLabel = await resolveTripMemberLabel(trip, actorId);
    if (!actorLabel) actorLabel = "Quelqu'un";

    await db.collection('notificationQueue').add({
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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
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
    const proceed = await markFunctionEventProcessedOnce(
      'notifyTripAnnouncementRecipients',
      event.id
    );
    if (!proceed) return;

    const snap = event.data;
    if (!snap) return;

    const tripId = event.params.tripId;
    const announcement = snap.data() || {};
    const actorId = normalizeString(announcement.authorId);
    const text = normalizeString(announcement.text).slice(0, 180);
    if (!actorId || !text) return;

    const db = admin.firestore();
    const tripSnap = await db.collection('trips').doc(tripId).get();
    if (!tripSnap.exists) return;

    const trip = tripSnap.data() || {};
    const memberIds = Array.isArray(trip.memberIds)
      ? trip.memberIds.map((v) => String(v))
      : [];
    const candidateRecipients = memberIds.filter((id) => id && id !== actorId);
    if (candidateRecipients.length === 0) return;

    const tripTitle = normalizeString(trip.title) || 'Voyage';
    let actorLabel = await resolveTripMemberLabel(trip, actorId);
    if (!actorLabel) actorLabel = "Quelqu'un";

    await db.collection('notificationQueue').add({
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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
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
      const readAfter =
        afterTs || admin.firestore.Timestamp.fromMillis(0);
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
      .where('memberIds', 'array-contains', uid)
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
          admin.firestore.Timestamp.fromMillis(0);
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
    const FieldValue = admin.firestore.FieldValue;

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

      const msgsRaw = channels[TRIP_NOTIFICATION_CHANNELS.MESSAGES];
      const actsRaw = channels[TRIP_NOTIFICATION_CHANNELS.ACTIVITIES];
      const msgs =
        typeof msgsRaw === 'number' ? msgsRaw : Number(msgsRaw) || 0;
      const acts =
        typeof actsRaw === 'number' ? actsRaw : Number(actsRaw) || 0;

      const totalRaw = data.total;
      const total = typeof totalRaw === 'number' ? totalRaw : Number(totalRaw) || 0;
      const nextTotal = msgs + acts;

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
      ? memberIdsAsSet(beforeSnap.data() || {})
      : new Set();
    const afterIds = memberIdsAsSet(afterSnap.data() || {});

    const added = [...afterIds].filter((id) => !beforeIds.has(id));
    const removed = [...beforeIds].filter((id) => !afterIds.has(id));
    if (added.length === 0 && removed.length === 0) return;
    const isPlaceholderClaimSwap =
      added.length === 1 &&
      removed.length === 1 &&
      isPlaceholderMemberId(removed[0]) &&
      !isPlaceholderMemberId(added[0]);

    const tripRef = afterSnap.ref;
    for (const uid of added) {
      // Placeholder claimed by a real account: join callable migrates data;
      // do not union the new uid into every expense like a brand-new member.
      if (isPlaceholderClaimSwap) {
        continue;
      }
      try {
        await backfillTripMemberInExpenseSubcollections(tripRef, uid);
      } catch (e) {
        console.error(
          'backfillNewTripMemberInExpenses failed',
          tripRef.id,
          uid,
          e
        );
        throw e;
      }
    }

    // Keep meals consistent when members are removed from trip.memberIds
    // (manual participant removal or leave-trip flow).
    // Skip placeholder claim swap: joinTripWithInvite migrates meal IDs itself.
    if (isPlaceholderClaimSwap || removed.length === 0) {
      return;
    }

    const db = admin.firestore();
    const mealsSnap = await tripRef.collection('meals').get();
    if (mealsSnap.empty) return;
    const FieldValue = admin.firestore.FieldValue;
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
      .collection('members')
      .where('cupidonEnabled', '==', true)
      .get();
    if (membersSnap.empty) {
      return;
    }

    const db = admin.firestore();
    const FieldValue = admin.firestore.FieldValue;
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
      { [previewField]: admin.firestore.FieldValue.delete() },
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
          fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
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
        fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
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
          fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
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
          fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
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
  placeholderMemberId,
  bypassPlaceholderChoice
) {
  const FieldValue = admin.firestore.FieldValue;
  const placeholderArg = normalizeString(placeholderMemberId);
  const bypassPlaceholder = bypassPlaceholderChoice === true;
  let claimedPh = null;

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(tripRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = snap.data() || {};
    assertTripInviteToken(data, token);

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (memberIds.includes(uid)) {
      return;
    }

    const phMembers = memberIds.filter(isPlaceholderMemberId);

    if (phMembers.length > 0) {
      if (bypassPlaceholder) {
        memberIds.push(uid);
        tx.update(tripRef, {
          memberIds,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return;
      }
      if (!placeholderArg || !isPlaceholderMemberId(placeholderArg)) {
        throw new HttpsError(
          'invalid-argument',
          'Choisis un voyageur prévu sur la liste pour rejoindre ce voyage.'
        );
      }
      if (!memberIds.includes(placeholderArg)) {
        throw new HttpsError(
          'failed-precondition',
          'Ce voyageur a déjà été choisi ou est introuvable.'
        );
      }
      const newMemberIds = memberIds.map((id) =>
        id === placeholderArg ? uid : id
      );
      claimedPh = placeholderArg;
      /** @type {Record<string, unknown>} */
      const tripUpdate = {
        memberIds: newMemberIds,
        updatedAt: FieldValue.serverTimestamp(),
      };
      const nextAdmins = adminMemberIdsAfterPlaceholderClaim(
        data.adminMemberIds,
        placeholderArg,
        uid
      );
      if (nextAdmins) {
        tripUpdate.adminMemberIds = nextAdmins;
      }
      tx.update(tripRef, tripUpdate);
    } else {
      memberIds.push(uid);
      tx.update(tripRef, {
        memberIds,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });

  const tripSnap = await tripRef.get();
  const tripData = tripSnap.data() || {};
  const finalMemberIds = Array.isArray(tripData.memberIds)
    ? tripData.memberIds.map((v) => String(v))
    : [];
  if (!finalMemberIds.includes(uid)) {
    return;
  }

  if (claimedPh) {
    try {
      await migrateTripMemberIdReferences(tripRef, claimedPh, uid);
    } catch (e) {
      console.error('migrateTripMemberIdReferences failed', tripRef.id, e);
      try {
        await revertTripMemberClaim(tripRef, uid, claimedPh);
      } catch (revertErr) {
        console.error('revertTripMemberClaim failed', tripRef.id, revertErr);
      }
      throw new HttpsError(
        'internal',
        'Impossible de finaliser ton arrivée dans le voyage. Réessaie dans un instant.'
      );
    }
  }

  let emailLocal = '';
  try {
    const userRecord = await admin.auth().getUser(uid);
    emailLocal = emailLocalPart(userRecord.email || '');
  } catch (e) {
    console.warn('joinTripWithInvite getUser', e);
  }

  const labelUpdate = {};
  if (claimedPh) {
    labelUpdate[`memberPublicLabels.${claimedPh}`] = FieldValue.delete();
  }
  if (emailLocal) {
    labelUpdate[`memberPublicLabels.${uid}`] = emailLocal;
  }
  if (Object.keys(labelUpdate).length > 0) {
    await tripRef.update(labelUpdate);
  }
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

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    const labels =
      data.memberPublicLabels && typeof data.memberPublicLabels === 'object'
        ? data.memberPublicLabels
        : {};

    const placeholders = memberIds
      .filter(isPlaceholderMemberId)
      .map((id) => ({
        id,
        displayName: normalizeString(labels[id]) || 'Voyageur',
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
      placeholders,
      requiresPlaceholderChoice: placeholders.length > 0,
      cupidonModeEnabled: data.cupidonModeEnabled !== false,
      tripStartDate,
      tripEndDate,
    };
  }
);

exports.addTripPlaceholderMember = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const displayName = normalizeString(request.data?.displayName);
    if (!tripId) {
      throw new HttpsError('invalid-argument', 'Voyage invalide');
    }
    if (!displayName) {
      throw new HttpsError('invalid-argument', 'Nom obligatoire');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const tripData = tripSnap.data() || {};
    assertTripParticipantPermission({
      tripData,
      uid,
      permissionKey: 'createParticipant',
      fallbackRole: 'owner',
      deniedMessage: 'Droits insuffisants pour ajouter un voyageur prévu.',
    });

    const memberIds = Array.isArray(tripData.memberIds)
      ? tripData.memberIds.map((v) => String(v))
      : [];
    const memberIdSet = new Set(memberIds);
    let placeholderId = newTripPlaceholderMemberId();
    while (memberIdSet.has(placeholderId)) {
      placeholderId = newTripPlaceholderMemberId();
    }

    const groupsSnap = await tripRef.collection('expenseGroups').get();
    const FieldValue = admin.firestore.FieldValue;
    let batch = db.batch();
    let n = 0;

    batch.update(tripRef, {
      memberIds: FieldValue.arrayUnion(placeholderId),
      [`memberPublicLabels.${placeholderId}`]: displayName,
    });
    n++;

    for (const doc of groupsSnap.docs) {
      batch.update(doc.ref, {
        visibleToMemberIds: FieldValue.arrayUnion(placeholderId),
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

    return { ok: true, placeholderId };
  }
);

exports.removeTripPlaceholderMember = onCall(
  {
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecte');
    }

    const tripId = normalizeString(request.data?.tripId);
    const placeholderId = normalizeString(request.data?.placeholderId);
    if (!tripId || !placeholderId || !isPlaceholderMemberId(placeholderId)) {
      throw new HttpsError('invalid-argument', 'Parametres invalides');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }

    const data = tripSnap.data() || {};
    assertTripParticipantPermission({
      tripData: data,
      uid,
      permissionKey: 'deletePlaceholderParticipant',
      fallbackRole: 'owner',
      deniedMessage: 'Droits insuffisants pour retirer ce voyageur prévu.',
    });

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(placeholderId)) {
      throw new HttpsError('not-found', 'Voyageur prévu introuvable');
    }

    await assertPlaceholderUnusedInExpensesAndRooms(tripRef, placeholderId);
    await assertMemberRemovalBlockingDependencies({
      tripRef,
      memberId: placeholderId,
      tripData: data,
    });
    await cleanupNonBlockingMemberReferences(tripRef, placeholderId);

    const FieldValue = admin.firestore.FieldValue;
    const groupsSnap = await tripRef.collection('expenseGroups').get();

    let batch = db.batch();
    let n = 0;
    for (const doc of groupsSnap.docs) {
      const vis = doc.data().visibleToMemberIds;
      if (!Array.isArray(vis) || !vis.map(String).includes(placeholderId)) {
        continue;
      }
      batch.update(doc.ref, {
        visibleToMemberIds: FieldValue.arrayRemove(placeholderId),
      });
      n++;
      if (n >= 450) {
        await batch.commit();
        batch = db.batch();
        n = 0;
      }
    }

    batch.update(tripRef, {
      memberIds: FieldValue.arrayRemove(placeholderId),
      [`memberPublicLabels.${placeholderId}`]: FieldValue.delete(),
      adminMemberIds: FieldValue.arrayRemove(placeholderId),
    });
    n++;
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

    const placeholderMemberId = normalizeString(
      request.data?.placeholderMemberId
    );
    const bypassPlaceholderChoice = request.data?.bypassPlaceholderChoice === true;

    const tripRef = admin.firestore().collection('trips').doc(tripId);
    await completeJoinTripWithInvite(
      tripRef,
      uid,
      token,
      placeholderMemberId,
      bypassPlaceholderChoice
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

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Tu ne fais pas partie de ce voyage'
      );
    }

    await assertMemberRemovalBlockingDependencies({
      tripRef,
      memberId: uid,
      tripData: data,
    });
    await cleanupNonBlockingMemberReferences(tripRef, uid);

    await tripRef.update({
      memberIds: admin.firestore.FieldValue.arrayRemove(uid),
      [`memberPublicLabels.${uid}`]: admin.firestore.FieldValue.delete(),
      adminMemberIds: admin.firestore.FieldValue.arrayRemove(uid),
    });

    return { ok: true };
  }
);

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
    if (!tripId || !memberId || isPlaceholderMemberId(memberId)) {
      throw new HttpsError('invalid-argument', 'Parametres invalides');
    }
    if (memberId === uid) {
      throw new HttpsError(
        'invalid-argument',
        'Utilise l’action quitter le voyage pour ton propre compte.'
      );
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const data = tripSnap.data() || {};
    assertTripParticipantPermission({
      tripData: data,
      uid,
      permissionKey: 'deleteRegisteredParticipant',
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

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(memberId)) {
      throw new HttpsError('not-found', 'Participant introuvable');
    }

    await assertMemberRemovalBlockingDependencies({
      tripRef,
      memberId,
      tripData: data,
    });
    await cleanupNonBlockingMemberReferences(tripRef, memberId);

    await tripRef.update({
      memberIds: admin.firestore.FieldValue.arrayRemove(memberId),
      [`memberPublicLabels.${memberId}`]: admin.firestore.FieldValue.delete(),
      adminMemberIds: admin.firestore.FieldValue.arrayRemove(memberId),
    });

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
    assertTripParticipantPermission({
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

    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(memberId)) {
      throw new HttpsError('not-found', 'Participant introuvable');
    }

    const admins = tripAdminMemberIdSet(data);
    const FieldValue = admin.firestore.FieldValue;
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
    const memberIds = Array.isArray(data.memberIds)
      ? data.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Tu ne fais pas partie de ce voyage'
      );
    }

    let emailLocal = '';
    try {
      const userRecord = await admin.auth().getUser(uid);
      emailLocal = emailLocalPart(userRecord.email || '');
    } catch (e) {
      console.warn('registerMyTripMemberLabel getUser', e);
    }
    if (!emailLocal) {
      return { ok: false, reason: 'no-email' };
    }

    await tripRef.update({
      [`memberPublicLabels.${uid}`]: emailLocal,
    });
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
      const memberIds = Array.isArray(data.memberIds)
        ? data.memberIds.map((v) => normalizeString(v)).filter(Boolean)
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
        permissionsBackfilledAt: admin.firestore.FieldValue.serverTimestamp(),
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
    const memberIds = Array.isArray(tripData.memberIds)
      ? tripData.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Tu ne fais pas partie de ce voyage'
      );
    }

    await tripRef
      .collection('members')
      .doc(uid)
      .set(
        {
          cupidonEnabled: enabled,
          cupidonUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

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
    if (isPlaceholderMemberId(targetMemberId)) {
      throw new HttpsError('invalid-argument', 'Participant invalide');
    }

    const db = admin.firestore();
    const tripRef = db.collection('trips').doc(tripId);
    const tripSnap = await tripRef.get();
    if (!tripSnap.exists) {
      throw new HttpsError('not-found', 'Voyage introuvable');
    }
    const tripData = tripSnap.data() || {};
    const memberIds = Array.isArray(tripData.memberIds)
      ? tripData.memberIds.map((v) => String(v))
      : [];
    if (!memberIds.includes(uid) || !memberIds.includes(targetMemberId)) {
      throw new HttpsError('permission-denied', 'Participants invalides');
    }

    const [myMemberSnap, targetMemberSnap] = await Promise.all([
      tripRef.collection('members').doc(uid).get(),
      tripRef.collection('members').doc(targetMemberId).get(),
    ]);
    if (!hasCupidonEnabled(myMemberSnap.data())) {
      throw new HttpsError(
        'failed-precondition',
        'Active le mode Cupidon pour liker des participants'
      );
    }
    const targetCupidonEnabled = hasCupidonEnabled(targetMemberSnap.data());

    const likeRef = tripRef
      .collection('cupidonLikes')
      .doc(cupidonLikeDocId(uid, targetMemberId));
    if (isLiked) {
      await likeRef.set(
        {
          likerId: uid,
          targetId: targetMemberId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      const matchDataForTarget = {
        matchId,
        tripId,
        tripTitle,
        otherMemberId: uid,
        otherMemberLabel: myProfile.label,
        otherMemberPhotoUrl: myProfile.photoUrl,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Deduplicate match creation in concurrent like scenarios.
      const created = await db.runTransaction(async (tx) => {
        const tripMatchSnap = await tx.get(tripMatchRef);
        if (tripMatchSnap.exists) {
          return false;
        }
        const matchCreatedAt = admin.firestore.FieldValue.serverTimestamp();
        tx.set(tripMatchRef, {
          matchId,
          tripId,
          memberIds: [uid, targetMemberId],
          createdAt: matchCreatedAt,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
          tripTitle,
          notifiedUid: uid,
          otherLabel: targetProfile.label,
          otherPhotoUrl: targetProfile.photoUrl,
          createdAt: admin.firestore.Timestamp.now(),
        }),
        sendCupidonMatchPush({
          tripId,
          tripTitle,
          notifiedUid: targetMemberId,
          otherLabel: myProfile.label,
          otherPhotoUrl: myProfile.photoUrl,
          createdAt: admin.firestore.Timestamp.now(),
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
      const createdAt = trip.createdAt instanceof admin.firestore.Timestamp
        ? trip.createdAt.toMillis()
        : doc.createTime instanceof admin.firestore.Timestamp
        ? doc.createTime.toMillis()
        : 0;
      if (createdAt > latestTripCreatedAtMs) {
        latestTripCreatedAtMs = createdAt;
      }

      const memberCount = Array.isArray(trip.memberIds) ? trip.memberIds.length : 0;
      if (memberCount > maxParticipants) maxParticipants = memberCount;

      const startDate = trip.startDate instanceof admin.firestore.Timestamp
        ? trip.startDate
        : null;
      const endDate = trip.endDate instanceof admin.firestore.Timestamp
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

      if (act.plannedAt instanceof admin.firestore.Timestamp) {
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

