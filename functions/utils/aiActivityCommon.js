'use strict';

/**
 * Shared base of the AI features that propose planning activities (from
 * travel documents, from a free-text description): activity field
 * sanitizers and the Gemini forced function call.
 *
 * Times: the trip has no time zone. Models return local wall-clock times
 * without offset (`YYYY-MM-DDTHH:mm`); the app reads them in the device time
 * zone, exactly like a manual entry.
 */

const { HttpsError } = require('firebase-functions/v2/https');

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

// Must match `tripActivityMaxDurationMinutes` and `firestore.rules`.
const MAX_DURATION_MINUTES = 7 * 24 * 60;
const MAX_LABEL_LENGTH = 200;
const MAX_ADDRESS_LENGTH = 500;
const MAX_COMMENTS_LENGTH = 2000;

const LOCAL_DATE_TIME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/;

function normalizeString(v) {
  return (typeof v === 'string' ? v : '').trim();
}

function truncate(value, maxLength) {
  const s = normalizeString(value);
  return s.length > maxLength ? s.slice(0, maxLength).trim() : s;
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

/**
 * Calls Gemini with a single function the model must call, and returns the
 * arguments of that call.
 *
 * @param {object} options
 * @param {string} options.apiKey
 * @param {string} options.model
 * @param {string} options.logTag prefix of the error logs (feature key)
 * @param {string} options.systemPrompt
 * @param {object[]} options.parts user message parts
 * @param {{ name: string, description: string, parameters: object }} options.tool
 * @param {object} options.generationConfig
 * @param {string} options.truncatedMessage error shown when the answer is cut
 */
async function callGeminiTool({
  apiKey,
  model,
  logTag,
  systemPrompt,
  parts,
  tool,
  generationConfig,
  truncatedMessage,
}) {
  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const body = {
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: 'user', parts }],
    tools: [{ function_declarations: [tool] }],
    tool_config: {
      function_calling_config: { mode: 'ANY', allowed_function_names: [tool.name] },
    },
    generation_config: generationConfig,
  };

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    console.error(`${logTag}: Gemini error`, {
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
    throw new HttpsError('internal', truncatedMessage);
  }
  const candidateParts = candidate?.content?.parts;
  const funcPart = Array.isArray(candidateParts)
    ? candidateParts.find((p) => p && p.functionCall && p.functionCall.args)
    : null;
  if (!funcPart) {
    console.error(`${logTag}: no functionCall`, {
      finishReason: candidate?.finishReason,
    });
    throw new HttpsError('internal', 'Réponse IA invalide (functionCall absent)');
  }
  return funcPart.functionCall.args;
}

module.exports = {
  ACTIVITY_CATEGORIES,
  MAX_DURATION_MINUTES,
  MAX_LABEL_LENGTH,
  MAX_ADDRESS_LENGTH,
  MAX_COMMENTS_LENGTH,
  normalizeString,
  truncate,
  sanitizeLocalDateTime,
  sanitizeDurationMinutes,
  tripDateOnly,
  callGeminiTool,
};
