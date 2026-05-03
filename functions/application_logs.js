const { FieldValue } = require('firebase-admin/firestore');

const APPLICATION_LOG_LEVELS = new Set(['debug', 'info', 'warn', 'error']);

function normalizeApplicationLogLevel(level) {
  const s = typeof level === 'string' ? level.trim().toLowerCase() : '';
  return APPLICATION_LOG_LEVELS.has(s) ? s : null;
}

function sanitizeDetails(details) {
  if (
    details == null ||
    typeof details !== 'object' ||
    Array.isArray(details)
  ) {
    return null;
  }
  /** @type {Record<string, unknown>} */
  const out = {};
  for (const [key, value] of Object.entries(details)) {
    if (typeof key !== 'string' || key.length > 200) continue;
    if (
      typeof value === 'string' ||
      typeof value === 'number' ||
      typeof value === 'boolean' ||
      value === null
    ) {
      let stored = value;
      if (typeof stored === 'string' && stored.length > 8000) {
        stored = `${stored.slice(0, 7997)}...`;
      }
      out[key] = stored;
    }
  }
  return Object.keys(out).length ? out : null;
}

/**
 * Persists a structured application log (Admin SDK only in production; rules deny client writes).
 * @param {FirebaseFirestore.Firestore} db
 * @param {{ level: string, source: string, message: string, details?: Record<string, unknown> }} payload
 */
async function insertApplicationLog(db, payload) {
  const level = normalizeApplicationLogLevel(payload.level);
  if (!level) {
    throw new Error('Invalid application log level');
  }
  const source =
    typeof payload.source === 'string' ? payload.source.trim() : '';
  if (!source || source.length > 200) {
    throw new Error('Invalid application log source');
  }
  const message =
    typeof payload.message === 'string' ? payload.message.trim() : '';
  if (!message || message.length > 20000) {
    throw new Error('Invalid application log message');
  }
  const details = sanitizeDetails(payload.details);

  /** @type {Record<string, unknown>} */
  const doc = {
    timestampUtc: FieldValue.serverTimestamp(),
    level,
    source,
    message,
  };
  if (details) doc.details = details;

  await db.collection('applicationLogs').add(doc);
}

module.exports = {
  APPLICATION_LOG_LEVELS,
  insertApplicationLog,
  normalizeApplicationLogLevel,
  sanitizeDetails,
};
