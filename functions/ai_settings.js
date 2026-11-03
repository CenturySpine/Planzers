'use strict';

/**
 * AI provider settings chosen by application owners in the administration
 * (Firestore `system/aiSettings`), and their translation into the values each
 * provider API expects.
 *
 * Document shape (every field optional, defaults below):
 *   - provider:       'google' | 'anthropic' — used by server-side AI calls
 *   - googleModel:    Gemini model id (also used by client-side Firebase AI calls)
 *   - anthropicModel: Claude model id
 *   - thinkingLevel:  'minimal' | 'low' | 'medium' | 'high' (provider-agnostic)
 *
 * Mirrors lib/features/ai_settings/data/ai_settings.dart — keep in sync.
 */

const AI_SETTINGS_COLLECTION = 'system';
const AI_SETTINGS_DOC_ID = 'aiSettings';

const AI_PROVIDERS = Object.freeze(['google', 'anthropic']);
const AI_THINKING_LEVELS = Object.freeze(['minimal', 'low', 'medium', 'high']);

const DEFAULT_AI_SETTINGS = Object.freeze({
  provider: 'google',
  googleModel: 'gemini-3.5-flash-lite',
  anthropicModel: 'claude-haiku-5-5',
  thinkingLevel: 'minimal',
});

// Generic thinking level -> provider value.
// - Google (Gemini 3.x): `generationConfig.thinkingConfig.thinkingLevel`.
// - Anthropic (Claude 5.5 models): `output_config.effort`. Not all of these
//   models can fully disable thinking, so `minimal` maps to the lowest effort.
const PROVIDER_THINKING_LEVELS = Object.freeze({
  google: Object.freeze({ minimal: 'MINIMAL', low: 'LOW', medium: 'MEDIUM', high: 'HIGH' }),
  anthropic: Object.freeze({ minimal: 'low', low: 'low', medium: 'medium', high: 'high' }),
});

function trimmedString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

/**
 * Returns complete, valid settings from a raw Firestore document (or null):
 * unknown or missing values fall back to [DEFAULT_AI_SETTINGS].
 */
function normalizeAiSettings(raw) {
  const data = raw && typeof raw === 'object' ? raw : {};
  const provider = trimmedString(data.provider);
  const thinkingLevel = trimmedString(data.thinkingLevel);
  return {
    provider: AI_PROVIDERS.includes(provider) ? provider : DEFAULT_AI_SETTINGS.provider,
    googleModel: trimmedString(data.googleModel) || DEFAULT_AI_SETTINGS.googleModel,
    anthropicModel: trimmedString(data.anthropicModel) || DEFAULT_AI_SETTINGS.anthropicModel,
    thinkingLevel: AI_THINKING_LEVELS.includes(thinkingLevel)
      ? thinkingLevel
      : DEFAULT_AI_SETTINGS.thinkingLevel,
  };
}

/** Model id to call for the selected provider. */
function selectedModel(settings) {
  return settings.provider === 'anthropic' ? settings.anthropicModel : settings.googleModel;
}

/** Provider-specific value of a generic thinking level. */
function providerThinkingLevel(provider, thinkingLevel) {
  const levels = PROVIDER_THINKING_LEVELS[provider];
  if (!levels) {
    throw new Error(`Unknown AI provider: ${provider}`);
  }
  return levels[thinkingLevel] || levels[DEFAULT_AI_SETTINGS.thinkingLevel];
}

/**
 * Deep copy of a JSON Schema where every object forbids extra properties, as
 * required by Anthropic structured outputs (`output_config.format`).
 */
function closeJsonSchemaObjects(schema) {
  if (Array.isArray(schema)) {
    return schema.map(closeJsonSchemaObjects);
  }
  if (!schema || typeof schema !== 'object') {
    return schema;
  }
  const copy = {};
  for (const [key, value] of Object.entries(schema)) {
    copy[key] = closeJsonSchemaObjects(value);
  }
  if (copy.type === 'object') {
    copy.additionalProperties = false;
  }
  return copy;
}

/** Reads the current settings (defaults when the document does not exist). */
async function readAiSettings(db) {
  const snap = await db.collection(AI_SETTINGS_COLLECTION).doc(AI_SETTINGS_DOC_ID).get();
  return normalizeAiSettings(snap.exists ? snap.data() : null);
}

module.exports = {
  AI_PROVIDERS,
  AI_THINKING_LEVELS,
  DEFAULT_AI_SETTINGS,
  normalizeAiSettings,
  selectedModel,
  providerThinkingLevel,
  closeJsonSchemaObjects,
  readAiSettings,
};
