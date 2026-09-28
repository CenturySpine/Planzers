'use strict';

/**
 * AI-driven import of planning activities from the caller's travel documents
 * ("Mes documents" wallet).
 *
 * Two steps, so nothing reaches the shared planning without a human check:
 *   1. `extractTripActivitiesFromDocuments` reads the selected wallet files,
 *      sends them to Gemini with a forced function call whose schema mirrors
 *      the activity fields, and returns proposals (no write).
 *   2. `importTripActivitiesFromDocuments` writes the proposals the user kept
 *      to `trips/{tripId}/activities` and links them to their source
 *      documents.
 *
 * Restricted to the trip creator and co-admins.
 *
 * Times: documents give local wall-clock times at the destination and the
 * trip has no time zone. The model returns them without offset
 * (`YYYY-MM-DDTHH:mm`); the app reads them in the device time zone, exactly
 * like a manual entry, and sends back an instant on import.
 */

const admin = require('firebase-admin');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { withAiQuota } = require('./utils/aiQuotaGate');

const AI_FEATURE_KEY = 'documentActivityImport';
const AI_MODEL = 'gemini-2.5-flash';
const AI_TOOL_NAME = 'propose_trip_activities';

const MAX_DOCUMENTS_PER_EXTRACTION = 5;
// Gemini rejects inline requests above 20 MB (base64 grows the payload ~4/3).
const MAX_TOTAL_FILE_BYTES = 14 * 1024 * 1024;
const MAX_ACTIVITIES_PER_IMPORT = 50;
// Must match `tripActivityMaxDurationMinutes` and `firestore.rules`.
const MAX_DURATION_MINUTES = 7 * 24 * 60;
// Extracted items are journeys, nights or activities of a day: anything longer
// is a whole-tour or multi-night item the prompt forbids.
const MAX_PROPOSAL_DURATION_MINUTES = 24 * 60;
// Must match `walletMaxActivityLinks` and `firestore.rules`.
const MAX_WALLET_ACTIVITY_LINKS = 50;
const MAX_LABEL_LENGTH = 200;
const MAX_ADDRESS_LENGTH = 500;
const MAX_COMMENTS_LENGTH = 2000;
// Must match `walletActivityImportMaxInstructionsLength`.
const MAX_INSTRUCTIONS_LENGTH = 1000;

// Must match `TripActivityCategory.firestoreValue`.
const ACTIVITY_CATEGORIES = [
  'sport',
  'hiking',
  'shopping',
  'visit',
  'restaurant',
  'cafe',
  'museum',
  'show',
  'nightlife',
  'karaoke',
  'games',
  'beach',
  'park',
  'transport',
  'accommodation',
  'wellness',
  'cooking',
  'workshop',
  'market',
  'meeting',
];

// Restaurant activities are meal suggestions, hidden from the planning:
// meals of a programme go in the comments instead.
const PROPOSAL_CATEGORIES = ACTIVITY_CATEGORIES.filter((c) => c !== 'restaurant');

const SAFE_SEGMENT =/^[A-Za-z0-9_-]+$/;
const LOCAL_DATE_TIME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/;

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function truncate(value, maxLength) {
  const s = normalizeString(value);
  return s.length > maxLength ? s.slice(0, maxLength).trim() : s;
}

/** Creator (`ownerId`) or listed co-admin (`adminMemberIds`). */
function isTripAdminOrOwner(tripData, uid) {
  const u = normalizeString(uid);
  if (!u || !tripData) return false;
  if (normalizeString(tripData.ownerId) === u) return true;
  const admins = Array.isArray(tripData.adminMemberIds) ? tripData.adminMemberIds : [];
  return admins.map((v) => String(v).trim()).includes(u);
}

/** @returns {string[]} unique, safe ids, in the given order. */
function sanitizeIdList(raw, maxCount) {
  if (!Array.isArray(raw)) return [];
  const ids = [];
  for (const value of raw) {
    const id = normalizeString(value);
    if (id && SAFE_SEGMENT.test(id) && !ids.includes(id)) ids.push(id);
    if (ids.length >= maxCount) break;
  }
  return ids;
}

/** `YYYY-MM-DDTHH:mm` for a real calendar date/time, otherwise ''. */
function sanitizeLocalDateTime(raw) {
  const s = normalizeString(raw);
  const match = s.match(LOCAL_DATE_TIME);
  if (!match) return '';
  const [year, month, day, hour, minute] = match.slice(1).map(Number);
  const probe = new Date(Date.UTC(year, month - 1, day, hour, minute));
  const valid =
    probe.getUTCFullYear() === year &&
    probe.getUTCMonth() === month - 1 &&
    probe.getUTCDate() === day &&
    probe.getUTCHours() === hour &&
    probe.getUTCMinutes() === minute;
  return valid ? s : '';
}

/** Whole minutes in (0, 7 days], otherwise null (category default applies). */
function sanitizeDurationMinutes(raw) {
  const n = typeof raw === 'number' ? raw : Number(raw);
  if (!Number.isFinite(n)) return null;
  const minutes = Math.round(n);
  if (minutes <= 0) return null;
  return Math.min(minutes, MAX_DURATION_MINUTES);
}

function sanitizeCategory(raw) {
  const s = normalizeString(raw);
  return ACTIVITY_CATEGORIES.includes(s) ? s : 'visit';
}

/**
 * Cleans one model proposal. Returns null when unusable (no label), longer
 * than a day or a meal.
 * @param {object} raw
 * @param {string[]} allowedDocumentIds
 */
function sanitizeProposal(raw, allowedDocumentIds) {
  if (!raw || typeof raw !== 'object') return null;
  const label = truncate(raw.label, MAX_LABEL_LENGTH);
  if (!label) return null;
  if (Number(raw.durationMinutes) > MAX_PROPOSAL_DURATION_MINUTES) return null;
  if (normalizeString(raw.category) === 'restaurant') return null;
  const sourceDocumentIds = sanitizeIdList(raw.sourceDocumentIds, MAX_DOCUMENTS_PER_EXTRACTION)
    .filter((id) => allowedDocumentIds.includes(id));
  return {
    label,
    category: sanitizeCategory(raw.category),
    plannedAtLocal: sanitizeLocalDateTime(raw.plannedAtLocal),
    durationMinutes: sanitizeDurationMinutes(raw.durationMinutes),
    address: truncate(raw.address, MAX_ADDRESS_LENGTH),
    freeComments: truncate(raw.freeComments, MAX_COMMENTS_LENGTH),
    sourceDocumentIds,
  };
}

/** Chronological (unscheduled last), stable otherwise. */
function sortProposals(proposals) {
  return proposals
    .map((p, index) => ({ p, index }))
    .sort((a, b) => {
      const aAt = a.p.plannedAtLocal;
      const bAt = b.p.plannedAtLocal;
      if (aAt && bAt && aAt !== bAt) return aAt < bAt ? -1 : 1;
      if (aAt && !bAt) return -1;
      if (!aAt && bAt) return 1;
      return a.index - b.index;
    })
    .map(({ p }) => p);
}

function buildToolSchema() {
  return {
    type: 'object',
    required: ['activities'],
    properties: {
      activities: {
        type: 'array',
        description:
          'Scheduled items found in the documents, deduplicated across documents: one per journey leg, one per night, one per activity of each programme day.',
        items: {
          type: 'object',
          required: [
            'label',
            'category',
            'plannedAtLocal',
            'durationMinutes',
            'address',
            'freeComments',
            'sourceDocumentIds',
          ],
          properties: {
            label: {
              type: 'string',
              description:
                'Short title in the output language, e.g. "Vol Paris → Rome (AF1234)", "Nuit à l\'hôtel du Port" or "Visite libre de Noto". Never the name of a whole tour.',
            },
            category: {
              type: 'string',
              enum: PROPOSAL_CATEGORIES,
              description:
                'transport for any journey (flight, train, bus, boat, transfer, car rental pick-up); accommodation for a night; meeting for a meeting point or briefing; otherwise the closest leisure category. Meals are never items.',
            },
            plannedAtLocal: {
              type: 'string',
              description:
                'Start as local wall-clock time at the place of the event, format YYYY-MM-DDTHH:mm, no time zone. Night: 20:00 on that evening unless a check-in time is stated. Programme activity without a time: right after the end of the previous item of that day, in the order of the text. Empty string when the day itself is unknown.',
            },
            durationMinutes: {
              type: 'integer',
              description:
                'Duration in minutes (flight: departure to arrival; night: 720, i.e. until 08:00 the next morning, unless check-in/check-out times are stated). 0 when unknown. At most 1440.',
            },
            address: {
              type: 'string',
              description:
                'Postal address of the place (accommodation, meeting point, departure station/airport). Empty string when none.',
            },
            freeComments: {
              type: 'string',
              description:
                'Practical details only: flight/train number, booking reference, contact phone, baggage allowance, meeting instructions. One detail per line. Empty string when none.',
            },
            sourceDocumentIds: {
              type: 'array',
              items: { type: 'string' },
              description: 'Ids of the documents this item was read from.',
            },
          },
        },
      },
    },
  };
}

function buildSystemPrompt(lang) {
  const outputLanguage = lang === 'en' ? 'English' : 'French (with proper accents)';
  return [
    'You extract the schedule of a trip from travel documents (tickets, booking confirmations, vouchers, invoices, tour programmes, letters from a travel agency).',
    'Return every dated or datable item a traveller would put in a trip calendar: journeys, nights, meeting points, and every activity of each day.',
    '',
    'Allowed item types:',
    '1. Journey: one item per leg (outbound and return flights are two items; an airport transfer or a minibus transfer between two places is its own item). Category transport. Duration from departure to arrival.',
    '2. Night: ONE item per night, whether the accommodation is the same as the previous night or not ("3 nuits à l\'hôtel X" gives three items, one per night). Category accommodation. Start: 20:00 on the evening of that night. Duration: until 08:00 the next morning, i.e. 720 minutes. Use the check-in / check-out times instead only when the documents state them for that accommodation. Never 24 hours.',
    '3. Meeting: a meeting point, welcome meeting or briefing with a guide or representative. Category meeting.',
    '4. Programme activity: in a tour or circuit programme described day by day (JOUR 1, JOUR 2..., Day 1, Day 2... or dated days), each distinct activity of a day is its own item. "Visite de X le matin, déjeuner pique-nique, visite de Y l\'après-midi" gives two items: the visit of X and the visit of Y, with "Déjeuner pique-nique" in the comments of the visit of X. Label: the activity itself (e.g. "Randonnée dans la réserve de Vendicari", "Visite libre de Noto"). Duration: as stated (e.g. "Randonnée - Entre 4h et 4h30" gives 240), otherwise a realistic estimate (a visit about 120). Comments: the practical details of that activity (distance, elevation, sites seen, what is included), one per line. Category: the closest one (hiking for a hike, visit for sightseeing, museum, beach...). Optional suggestions ("possibilité de...", "en supplément", "selon l\'envie du groupe") are not items; mention them in the comments of the closest activity.',
    '   Moves within a programme day: every move the text describes is its own transport item, placed right before the activity at the destination: the departure from the accommodation ("Départ pour la réserve de Vendicari", "Départ matinal en direction de Syracuse"), each move between two places ("court transfert vers Marzamemi", "route vers Noto", "continuation vers Taormine") and the return or the move to the evening accommodation ("Sur le chemin du retour", "pour rejoindre un agritourisme"). Label "Transfert A → B", with A the previous place (the accommodation of the previous night for the first move of the day) and B the destination. The day\'s "Transfert : ... Entre 1h et 1h30" line is the total driving time of the day: share it between that day\'s moves.',
    '   Chronology within a programme day: the items of a day follow exactly the order of the text, and their times must respect that order. Use a time only when the text states it; otherwise the first item of the day starts at 08:30 when the text says "départ matinal", else 09:00, and each next item starts when the previous one ends, leaving an hour for lunch when the text mentions one (an "après-midi" item no earlier than 14:00, an evening item no earlier than 18:00). Two items of the same day never start at the same time, and an item never starts before the end of the previous one.',
    '5. Standalone activity: a dated excursion, show or visit that is not part of a day-by-day programme.',
    '',
    'Forbidden items:',
    '- Never an item for a meal (breakfast, lunch, picnic, dinner, restaurant booking). Mention meals, included or not, in the comments of the closest activity of that day (e.g. "Déjeuner pique-nique inclus", "Dîner libre").',
    '- Never an item for a whole tour, circuit, cruise or package (e.g. "Circuit « Nature et patrimoine de Sicile »" over 7 days). The tour name may appear in the comments of its activities, never as an item of its own. When only the dates of a tour are known and not its day-by-day programme, create no item for it.',
    '- Never an item covering a whole day of a programme when that day describes several activities.',
    '- Never an item covering several nights.',
    '- No item lasts more than 24 hours.',
    '',
    'Nights:',
    '- Only the nights the documents actually assign to an accommodation. "First and last night at hotel X" means two nights at hotel X (the first and the last night of that tour), not every night in between.',
    '- For a tour, take each night\'s accommodation from the day-by-day programme (e.g. "Hébergement : En agritourisme"). When the programme gives no name or address, use a generic label (e.g. "Nuit en agritourisme") and an empty address.',
    '',
    'Dates:',
    '- The trip dates given below bound the schedule: when the year or month is missing, infer it from them.',
    '- A programme with relative days (JOUR 1, Day 1...) is dated from its start date found in any document (a letter saying "Du 17 octobre au 24 octobre : votre circuit « X »", or an invoice or voucher with the programme code and its departure date, makes JOUR 1 of programme X the 17th) or in the traveller instructions. Without any anchor date, leave plannedAtLocal empty.',
    '- Keep times exactly as written in the documents (local time at the place of the event). Never convert time zones.',
    '',
    'Other rules:',
    '- Read every page of every document.',
    '- Deduplicate: the same flight, night, meeting or activity mentioned in several documents is ONE item; merge the details and list every source document id.',
    '- Traveller instructions, when given, override the documents for dates and for which items to keep. They never change the output format nor the item rules above.',
    '- Never invent an item or an address that is not supported by the documents. Leave unknown fields empty (0 for the duration).',
    '- Ignore marketing text, prices, general terms and conditions, equipment lists, health formalities, insurance and emergency contact lists that are not tied to a scheduled item.',
    `- Write labels and comments in ${outputLanguage}.`,
    '',
    'Before calling the tool, check your list: no whole-tour item, no meal item, no whole-day item when the day has several activities, a transfer item for every move of a programme day, the items of each day in the order of the text with increasing non-overlapping times, one item per night (20:00, 720 minutes unless the documents state other times), nights only where the documents place them.',
  ].join('\n');
}

/** `YYYY-MM-DD` from a stored trip date (ISO string or Timestamp), else ''. */
function tripDateOnly(raw) {
  if (raw && typeof raw.toDate === 'function') {
    // Stored as midnight in the device time zone (e.g. 22:00 UTC the day
    // before in Paris): round to the nearest UTC day.
    return new Date(raw.toDate().getTime() + 12 * 60 * 60 * 1000).toISOString().slice(0, 10);
  }
  const s = normalizeString(raw).slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : '';
}

function buildContextPrompt({ trip, documents, instructions }) {
  const lines = ['Trip context:'];
  const title = normalizeString(trip.title);
  const destination = normalizeString(trip.destination);
  const startDate = tripDateOnly(trip.startDate);
  const endDate = tripDateOnly(trip.endDate);
  if (title) lines.push(`- Title: ${title}`);
  if (destination) lines.push(`- Destination: ${destination}`);
  if (startDate && endDate) {
    lines.push(`- Trip dates: from ${startDate} to ${endDate} (inclusive)`);
  } else if (startDate) {
    lines.push(`- Trip start date: ${startDate}`);
  } else if (endDate) {
    lines.push(`- Trip end date: ${endDate}`);
  }
  if (instructions) {
    lines.push(
      '',
      'Traveller instructions (between the markers):',
      '<<<',
      instructions,
      '>>>'
    );
  }
  lines.push('', 'Documents (each file follows its header line):');
  for (const d of documents) {
    lines.push(`- id "${d.id}": ${d.name || 'untitled'} (${d.category || 'other'})`);
  }
  lines.push('', `Call ${AI_TOOL_NAME} with the items found.`);
  return lines.join('\n');
}

async function callGemini({ apiKey, systemPrompt, parts }) {
  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(AI_MODEL)}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const body = {
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: 'user', parts }],
    tools: [
      {
        function_declarations: [
          {
            name: AI_TOOL_NAME,
            description: 'Records the trip calendar items extracted from the documents.',
            parameters: buildToolSchema(),
          },
        ],
      },
    ],
    tool_config: {
      function_calling_config: { mode: 'ANY', allowed_function_names: [AI_TOOL_NAME] },
    },
    generation_config: {
      temperature: 0.1,
      maxOutputTokens: 32000,
      // Some reasoning is needed to cross-reference documents (programme
      // days dated from a letter, nights per hotel...).
      thinkingConfig: { thinkingBudget: 4096 },
    },
  };

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    console.error('documentActivityImport: Gemini error', {
      status: response.status,
      body: text.slice(0, 500),
    });
    throw new HttpsError('unavailable', `Service IA indisponible (Gemini ${response.status})`);
  }

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (_) {
    throw new HttpsError('internal', 'Réponse IA non JSON');
  }
  const candidate = parsed?.candidates?.[0];
  if (candidate?.finishReason === 'MAX_TOKENS') {
    throw new HttpsError('internal', 'Réponse IA tronquée (documents trop longs)');
  }
  const candidateParts = candidate?.content?.parts;
  const funcPart = Array.isArray(candidateParts)
    ? candidateParts.find((p) => p && p.functionCall && p.functionCall.args)
    : null;
  if (!funcPart) {
    console.error('documentActivityImport: no functionCall', {
      finishReason: candidate?.finishReason,
    });
    throw new HttpsError('internal', 'Réponse IA invalide (functionCall absent)');
  }
  return funcPart.functionCall.args;
}

async function loadTripForAdmin(db, tripId, uid) {
  const tripSnap = await db.collection('trips').doc(tripId).get();
  if (!tripSnap.exists) {
    throw new HttpsError('not-found', 'Voyage introuvable');
  }
  const trip = tripSnap.data() || {};
  if (!isTripAdminOrOwner(trip, uid)) {
    throw new HttpsError(
      'permission-denied',
      'Réservé au créateur et aux administrateurs du voyage'
    );
  }
  return trip;
}

function walletDocumentsRef(db, tripId, uid) {
  return db
    .collection('trips')
    .doc(tripId)
    .collection('travelerModules')
    .doc(uid)
    .collection('walletDocuments');
}

/**
 * Step 1 — proposals only, no write.
 *
 * Request: { tripId: string, documentIds: string[] (1..5), lang?: 'fr'|'en',
 *   instructions?: string (free text from the traveller, max 1000 chars) }
 * Response: { activities: Array<{ label, category, plannedAtLocal,
 *   durationMinutes, address, freeComments, sourceDocumentIds }> }
 */
const extractTripActivitiesFromDocuments = onCall(
  {
    timeoutSeconds: 300,
    memory: '1GiB',
    secrets: ['GOOGLE_AI_API_KEY'],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }
    const tripId = normalizeString(request.data?.tripId);
    if (!SAFE_SEGMENT.test(tripId)) {
      throw new HttpsError('invalid-argument', 'tripId requis');
    }
    const documentIds = sanitizeIdList(request.data?.documentIds, MAX_DOCUMENTS_PER_EXTRACTION + 1);
    if (documentIds.length === 0) {
      throw new HttpsError('invalid-argument', 'Au moins un document requis');
    }
    if (documentIds.length > MAX_DOCUMENTS_PER_EXTRACTION) {
      throw new HttpsError(
        'invalid-argument',
        `${MAX_DOCUMENTS_PER_EXTRACTION} documents maximum par analyse`
      );
    }
    const lang = normalizeString(request.data?.lang) === 'en' ? 'en' : 'fr';
    // The markers stay ours: a pasted '>>>' cannot close the block early.
    const instructions = truncate(request.data?.instructions, MAX_INSTRUCTIONS_LENGTH)
      .replace(/<<<|>>>/g, '');

    const db = admin.firestore();
    const trip = await loadTripForAdmin(db, tripId, uid);

    const docSnaps = await Promise.all(
      documentIds.map((id) => walletDocumentsRef(db, tripId, uid).doc(id).get())
    );
    const documents = [];
    let totalBytes = 0;
    for (const snap of docSnaps) {
      if (!snap.exists) {
        throw new HttpsError('not-found', 'Document introuvable');
      }
      const data = snap.data() || {};
      const file = data.file && typeof data.file === 'object' ? data.file : null;
      const barcodePayload = normalizeString(data.barcode?.payload);
      const storagePath = normalizeString(file?.storagePath);
      // Only files of this traveler for this trip (same check as the rules).
      if (storagePath && !storagePath.startsWith(`users/${uid}/wallet/${tripId}/`)) {
        throw new HttpsError('permission-denied', 'Document invalide');
      }
      if (!storagePath && !barcodePayload) continue;
      totalBytes += Number(file?.sizeBytes) || 0;
      documents.push({
        id: snap.id,
        name: normalizeString(data.name),
        category: normalizeString(data.category),
        storagePath,
        contentType: normalizeString(file?.contentType),
        barcodePayload,
      });
    }
    if (documents.length === 0) {
      throw new HttpsError('failed-precondition', 'Aucun document exploitable');
    }
    if (totalBytes > MAX_TOTAL_FILE_BYTES) {
      throw new HttpsError('invalid-argument', 'Documents trop volumineux pour une seule analyse');
    }

    const apiKey = normalizeString(process.env.GOOGLE_AI_API_KEY);
    if (!apiKey) {
      throw new HttpsError('failed-precondition', 'Clé API Google AI non configurée');
    }

    const bucket = admin.storage().bucket();
    const parts = [{ text: buildContextPrompt({ trip, documents, instructions }) }];
    for (const d of documents) {
      parts.push({ text: `Document id "${d.id}":` });
      if (d.storagePath) {
        const [buffer] = await bucket.file(d.storagePath).download();
        parts.push({
          inline_data: { mime_type: d.contentType, data: buffer.toString('base64') },
        });
      } else {
        parts.push({ text: `Scanned ticket code content: ${d.barcodePayload}` });
      }
    }

    const userSnap = await db.collection('users').doc(uid).get();
    const isApplicationOwner = userSnap.exists && userSnap.data()?.isApplicationOwner === true;

    return withAiQuota(
      { featureKey: AI_FEATURE_KEY, tripId, uid, isApplicationOwner },
      async () => {
        const result = await callGemini({
          apiKey,
          systemPrompt: buildSystemPrompt(lang),
          parts,
        });
        const rawActivities = Array.isArray(result?.activities) ? result.activities : [];
        const allowedIds = documents.map((d) => d.id);
        const activities = sortProposals(
          rawActivities
            .map((raw) => sanitizeProposal(raw, allowedIds))
            .filter(Boolean)
            .slice(0, MAX_ACTIVITIES_PER_IMPORT)
        );
        return { activities };
      }
    );
  }
);

/**
 * Validates one activity sent back by the app for import.
 * @returns {{ doc: object, sourceDocumentIds: string[] } | null}
 */
function buildImportedActivity(raw, uid) {
  if (!raw || typeof raw !== 'object') return null;
  const label = truncate(raw.label, MAX_LABEL_LENGTH);
  if (!label) return null;
  const plannedAtMillis = Number(raw.plannedAtMillis);
  const hasPlannedAt = raw.plannedAtMillis != null && Number.isFinite(plannedAtMillis);
  const durationMinutes = sanitizeDurationMinutes(raw.durationMinutes);
  return {
    doc: {
      label,
      category: sanitizeCategory(raw.category),
      linkUrl: '',
      address: truncate(raw.address, MAX_ADDRESS_LENGTH),
      freeComments: truncate(raw.freeComments, MAX_COMMENTS_LENGTH),
      ...(hasPlannedAt ? { plannedAt: Timestamp.fromMillis(Math.round(plannedAtMillis)) } : {}),
      ...(durationMinutes != null ? { durationMinutes } : {}),
      done: false,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
    },
    sourceDocumentIds: sanitizeIdList(raw.sourceDocumentIds, MAX_DOCUMENTS_PER_EXTRACTION),
  };
}

/**
 * Step 2 — writes the proposals the user kept.
 *
 * Request: { tripId: string, activities: Array<{ label, category,
 *   plannedAtMillis?: number, durationMinutes?: number, address,
 *   freeComments, sourceDocumentIds }> (1..50) }
 * Response: { activityIds: string[] }
 */
const importTripActivitiesFromDocuments = onCall(
  { timeoutSeconds: 60, memory: '256MiB' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }
    const tripId = normalizeString(request.data?.tripId);
    if (!SAFE_SEGMENT.test(tripId)) {
      throw new HttpsError('invalid-argument', 'tripId requis');
    }
    const rawActivities = Array.isArray(request.data?.activities) ? request.data.activities : [];
    if (rawActivities.length === 0 || rawActivities.length > MAX_ACTIVITIES_PER_IMPORT) {
      throw new HttpsError(
        'invalid-argument',
        `Entre 1 et ${MAX_ACTIVITIES_PER_IMPORT} activités par import`
      );
    }

    const db = admin.firestore();
    await loadTripForAdmin(db, tripId, uid);

    const imported = rawActivities.map((raw) => buildImportedActivity(raw, uid));
    if (imported.some((item) => item == null)) {
      throw new HttpsError('invalid-argument', 'Activité invalide (libellé obligatoire)');
    }

    const activitiesCol = db.collection('trips').doc(tripId).collection('activities');
    const walletCol = walletDocumentsRef(db, tripId, uid);
    // Shared by the activities of this import so members get one grouped
    // notification instead of one per activity.
    const importId = activitiesCol.doc().id;
    const newIdsByDocument = new Map();
    const activityIds = [];
    const batch = db.batch();
    for (const item of imported) {
      const ref = activitiesCol.doc();
      batch.set(ref, { ...item.doc, importId });
      activityIds.push(ref.id);
      for (const documentId of item.sourceDocumentIds) {
        const ids = newIdsByDocument.get(documentId) || [];
        ids.push(ref.id);
        newIdsByDocument.set(documentId, ids);
      }
    }

    // Links go on the caller's own documents only; a missing document or a
    // full link list simply leaves that link out.
    const walletSnaps = await Promise.all(
      [...newIdsByDocument.keys()].map((id) => walletCol.doc(id).get())
    );
    for (const snap of walletSnaps) {
      if (!snap.exists) continue;
      const data = snap.data() || {};
      const linked = new Set(
        (Array.isArray(data.activityIds) ? data.activityIds : [])
          .map((v) => normalizeString(v))
          .filter(Boolean)
      );
      const legacy = normalizeString(data.activityId);
      if (legacy) linked.add(legacy);
      for (const id of newIdsByDocument.get(snap.id)) {
        if (linked.size >= MAX_WALLET_ACTIVITY_LINKS) break;
        linked.add(id);
      }
      batch.update(snap.ref, {
        activityIds: [...linked],
        activityId: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return { activityIds };
  }
);

module.exports = {
  extractTripActivitiesFromDocuments,
  importTripActivitiesFromDocuments,
  // Exposed for tests.
  ACTIVITY_CATEGORIES,
  MAX_DURATION_MINUTES,
  MAX_PROPOSAL_DURATION_MINUTES,
  isTripAdminOrOwner,
  sanitizeIdList,
  sanitizeLocalDateTime,
  sanitizeDurationMinutes,
  sanitizeProposal,
  sortProposals,
  buildToolSchema,
  buildSystemPrompt,
  buildContextPrompt,
  buildImportedActivity,
};
