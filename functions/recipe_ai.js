'use strict';

/**
 * AI recipe generation (ingredient list and optional cooking steps) for the
 * meal editor. Runs server-side so that the app never calls the AI provider
 * directly: no App Check needed, quotas enforced here.
 *
 * Two Gemini calls, as in the former client-side version:
 *   1. a free-form answer grounded with Google Search;
 *   2. a strict JSON conversion of that answer (`responseSchema`).
 * Recipes always use Google, with the Google model and thinking level chosen
 * in the administration (see ai_settings.js). The app maps the returned
 * ingredients onto its units and ingredient catalog.
 */

const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { withAiQuota } = require('./utils/aiQuotaGate');
const { readAiSettings, providerThinkingLevel } = require('./ai_settings');

// Mirrors RecipeAiMode in lib/features/meals/data/recipe_ingredients_ai_service.dart.
const RECIPE_AI_MODES = Object.freeze(['ingredientsOnly', 'ingredientsAndInstructions']);
const MAX_RECIPE_NAME_LENGTH = 200;
const MAX_SERVINGS = 1000;

const RECIPE_UNITS = Object.freeze({
  fr: Object.freeze(['g', 'kg', 'ml', 'l', 'pièce(s)', 'boîte(s)', 'c. à soupe', 'c. à café']),
  en: Object.freeze(['g', 'kg', 'ml', 'l', 'piece(s)', 'can(s)', 'tablespoon', 'teaspoon']),
});

function normalizeString(value) {
  return (typeof value === 'string' ? value : '').trim();
}

/** Validates the callable payload; throws `invalid-argument` when unusable. */
function parseRecipeRequest(data) {
  const tripId = normalizeString(data?.tripId);
  const recipeName = normalizeString(data?.recipeName);
  const servings = data?.servings;
  const mode = normalizeString(data?.mode);
  const lang = normalizeString(data?.lang) === 'en' ? 'en' : 'fr';

  if (!tripId) {
    throw new HttpsError('invalid-argument', 'tripId requis');
  }
  if (!recipeName || recipeName.length > MAX_RECIPE_NAME_LENGTH) {
    throw new HttpsError('invalid-argument', 'Nom de recette invalide');
  }
  if (!Number.isInteger(servings) || servings < 1 || servings > MAX_SERVINGS) {
    throw new HttpsError('invalid-argument', 'Nombre de personnes invalide');
  }
  if (!RECIPE_AI_MODES.includes(mode)) {
    throw new HttpsError('invalid-argument', 'Mode de génération invalide');
  }
  return { tripId, recipeName, servings, mode, lang };
}

/** First call: free-form recipe, the model may rely on web recipes. */
function buildGroundedRecipePrompt({ recipeName, servings, mode, lang }) {
  const asksForInstructions = mode === 'ingredientsAndInstructions';
  if (lang === 'fr') {
    return [
      asksForInstructions
        ? `Donne-moi la liste complète des ingrédients ainsi que les instructions de préparation pour réaliser "${recipeName}" pour ${servings} personnes.`
        : `Donne-moi la liste complète des ingrédients pour réaliser "${recipeName}" pour ${servings} personnes.`,
      '',
      'Pour les ingrédients :',
      '- Les quantités doivent respecter les proportions culinaires réalistes, pas une simple multiplication par le nombre de personnes.',
      '- Par exemple, les aromates et épices ne se multiplient pas linéairement.',
      '- Utilise des unités usuelles parmi : "g", "kg", "ml", "l", "pièce(s)", "boîte(s)", "c. à soupe", "c. à café".',
      '- Choisis l\'unité la plus naturelle pour chaque ingrédient (par exemple "c. à café" pour les épices en petite quantité, "boîte(s)" pour les conserves).',
      ...(asksForInstructions
        ? [
            '',
            'Pour les instructions :',
            '- Présente les étapes de préparation numérotées (1., 2., 3., ...), une étape par ligne.',
            '- Sois clair et concis, en français.',
          ]
        : []),
      '',
      `Tu peux t'appuyer sur des recettes du web pour t'assurer des bonnes proportions${asksForInstructions ? ' et des bonnes étapes' : ''}.`,
    ].join('\n');
  }
  return [
    asksForInstructions
      ? `Give me the complete ingredient list and the preparation instructions to make "${recipeName}" for ${servings} servings.`
      : `Give me the complete ingredient list to make "${recipeName}" for ${servings} servings.`,
    '',
    'For the ingredients:',
    '- Quantities must follow realistic culinary proportions, not a simple multiplication by the number of servings.',
    '- For example, aromatics and spices do not scale linearly.',
    '- Use common units among: "g", "kg", "ml", "l", "piece(s)", "can(s)", "tablespoon", "teaspoon".',
    '- Choose the most natural unit for each ingredient (e.g. "teaspoon" for small amounts of spices, "can(s)" for canned goods).',
    ...(asksForInstructions
      ? [
          '',
          'For the instructions:',
          '- Present the preparation steps numbered (1., 2., 3., ...), one step per line.',
          '- Be clear and concise, in English.',
        ]
      : []),
    '',
    `You may use web recipes to ensure accurate proportions${asksForInstructions ? ' and steps' : ''}.`,
  ].join('\n');
}

/** Second call: faithful conversion of the first answer into JSON. */
function buildStructuredConversionPrompt({ sourceText, mode, lang }) {
  const asksForInstructions = mode === 'ingredientsAndInstructions';
  const lines =
    lang === 'fr'
      ? [
          'Voici une recette rédigée en texte libre. Convertis-la fidèlement en JSON structuré selon le schéma fourni.',
          '',
          'Contraintes :',
          '- N\'invente pas et ne modifie pas les quantités : transcris fidèlement le texte source.',
          '- Pour chaque ingrédient, l\'unité doit être STRICTEMENT une de : "g", "kg", "ml", "l", "pièce(s)", "boîte(s)", "c. à soupe", "c. à café".',
          ...(asksForInstructions
            ? ['- Pour les instructions, conserve les étapes numérotées telles quelles, une étape par ligne.']
            : []),
        ]
      : [
          'Here is a recipe written as free text. Convert it faithfully into structured JSON according to the provided schema.',
          '',
          'Constraints:',
          '- Do not invent or modify quantities: transcribe the source text faithfully.',
          '- For each ingredient, the unit must be STRICTLY one of: "g", "kg", "ml", "l", "piece(s)", "can(s)", "tablespoon", "teaspoon".',
          ...(asksForInstructions
            ? ['- For the instructions, keep the numbered steps as-is, one step per line.']
            : []),
        ];
  return [
    ...lines,
    '',
    lang === 'fr' ? 'Texte source :' : 'Source text:',
    '"""',
    sourceText,
    '"""',
  ].join('\n');
}

/** Gemini `responseSchema` of the second call (every field required). */
function buildRecipeResponseSchema({ mode, lang }) {
  const properties = {
    recipeName: { type: 'STRING' },
    servings: { type: 'INTEGER' },
    ingredients: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          name: { type: 'STRING' },
          quantity: { type: 'NUMBER' },
          unit: { type: 'STRING', format: 'enum', enum: [...RECIPE_UNITS[lang]] },
        },
        required: ['name', 'quantity', 'unit'],
      },
    },
  };
  if (mode === 'ingredientsAndInstructions') {
    properties.instructions = { type: 'STRING' };
  }
  return { type: 'OBJECT', properties, required: Object.keys(properties) };
}

/** Text of the first candidate of a Gemini response, without thought parts. */
function geminiAnswerText(response) {
  const parts = response?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) {
    return '';
  }
  return parts
    .filter((part) => part && typeof part.text === 'string' && part.thought !== true)
    .map((part) => part.text)
    .join('');
}

async function callGemini({ apiKey, model, body }) {
  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
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
  if (parsed?.candidates?.[0]?.finishReason === 'MAX_TOKENS') {
    console.error('generateRecipeWithAi: MAX_TOKENS reached', { model });
    throw new HttpsError('internal', 'Réponse IA tronquée');
  }
  return geminiAnswerText(parsed);
}

const generateRecipeWithAi = onCall(
  {
    timeoutSeconds: 120,
    memory: '256MiB',
    secrets: ['GOOGLE_AI_API_KEY'],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Utilisateur non connecté');
    }
    const { tripId, recipeName, servings, mode, lang } = parseRecipeRequest(request.data);

    const apiKey = normalizeString(process.env.GOOGLE_AI_API_KEY);
    if (!apiKey) {
      throw new HttpsError('failed-precondition', 'Clé API Google AI non configurée');
    }

    const db = admin.firestore();
    const userSnap = await db.collection('users').doc(uid).get();
    const isApplicationOwner = userSnap.exists && userSnap.data()?.isApplicationOwner === true;

    return withAiQuota(
      { featureKey: 'recipeIngredients', tripId, uid, isApplicationOwner },
      async () => {
        const settings = await readAiSettings(db);
        const model = settings.googleModel;
        const thinkingConfig = {
          thinkingLevel: providerThinkingLevel('google', settings.thinkingLevel),
        };

        const sourceText = await callGemini({
          apiKey,
          model,
          body: {
            contents: [
              {
                role: 'user',
                parts: [{ text: buildGroundedRecipePrompt({ recipeName, servings, mode, lang }) }],
              },
            ],
            tools: [{ google_search: {} }],
            generationConfig: { thinkingConfig },
          },
        });
        if (!sourceText.trim()) {
          throw new HttpsError('internal', 'Réponse IA vide.');
        }

        const jsonText = await callGemini({
          apiKey,
          model,
          body: {
            contents: [
              {
                role: 'user',
                parts: [{ text: buildStructuredConversionPrompt({ sourceText, mode, lang }) }],
              },
            ],
            generationConfig: {
              responseMimeType: 'application/json',
              responseSchema: buildRecipeResponseSchema({ mode, lang }),
              thinkingConfig,
            },
          },
        });

        let structured;
        try {
          structured = JSON.parse(jsonText);
        } catch (err) {
          throw new HttpsError('internal', 'Réponse IA invalide (conversion JSON).');
        }
        if (!structured || typeof structured !== 'object' || Array.isArray(structured)) {
          throw new HttpsError('internal', 'Réponse IA invalide (format inattendu).');
        }
        return {
          ingredients: Array.isArray(structured.ingredients) ? structured.ingredients : [],
          instructions: typeof structured.instructions === 'string' ? structured.instructions : '',
        };
      }
    );
  }
);

module.exports = {
  generateRecipeWithAi,
  parseRecipeRequest,
  buildGroundedRecipePrompt,
  buildStructuredConversionPrompt,
  buildRecipeResponseSchema,
  geminiAnswerText,
};
