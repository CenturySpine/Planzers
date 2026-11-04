'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  parseRecipeRequest,
  buildGroundedRecipePrompt,
  buildStructuredConversionPrompt,
  buildRecipeResponseSchema,
  geminiAnswerText,
} = require('./recipe_ai');

describe('parseRecipeRequest', () => {
  const valid = {
    tripId: ' trip1 ',
    recipeName: ' Ratatouille ',
    servings: 6,
    mode: 'ingredientsOnly',
    lang: 'en',
  };

  it('normalizes a valid request', () => {
    assert.deepEqual(parseRecipeRequest(valid), {
      tripId: 'trip1',
      recipeName: 'Ratatouille',
      servings: 6,
      mode: 'ingredientsOnly',
      lang: 'en',
    });
  });

  it('defaults to French', () => {
    assert.equal(parseRecipeRequest({ ...valid, lang: undefined }).lang, 'fr');
  });

  it('rejects unusable values', () => {
    for (const data of [
      { ...valid, tripId: '' },
      { ...valid, recipeName: '  ' },
      { ...valid, recipeName: 'x'.repeat(201) },
      { ...valid, servings: 0 },
      { ...valid, servings: 2.5 },
      { ...valid, servings: '4' },
      { ...valid, mode: 'everything' },
      null,
    ]) {
      assert.throws(() => parseRecipeRequest(data), { code: 'invalid-argument' });
    }
  });
});

describe('recipe prompts', () => {
  it('asks for the steps only when requested', () => {
    const base = { recipeName: 'Ratatouille', servings: 6, lang: 'fr' };
    const withSteps = buildGroundedRecipePrompt({ ...base, mode: 'ingredientsAndInstructions' });
    const withoutSteps = buildGroundedRecipePrompt({ ...base, mode: 'ingredientsOnly' });

    assert.match(withSteps, /instructions de préparation pour réaliser "Ratatouille" pour 6 personnes/);
    assert.match(withSteps, /Pour les instructions :/);
    assert.doesNotMatch(withoutSteps, /Pour les instructions :/);
  });

  it('wraps the source text of the conversion', () => {
    const prompt = buildStructuredConversionPrompt({
      sourceText: '200 g de farine',
      mode: 'ingredientsOnly',
      lang: 'en',
    });
    assert.ok(prompt.endsWith('Source text:\n"""\n200 g de farine\n"""'));
  });
});

describe('buildRecipeResponseSchema', () => {
  it('requires every field and restricts the units to the language', () => {
    const schema = buildRecipeResponseSchema({ mode: 'ingredientsAndInstructions', lang: 'fr' });
    assert.deepEqual(schema.required, ['recipeName', 'servings', 'ingredients', 'instructions']);
    assert.ok(schema.properties.ingredients.items.properties.unit.enum.includes('c. à soupe'));
  });

  it('leaves the steps out when they are not requested', () => {
    const schema = buildRecipeResponseSchema({ mode: 'ingredientsOnly', lang: 'en' });
    assert.equal('instructions' in schema.properties, false);
    assert.ok(schema.properties.ingredients.items.properties.unit.enum.includes('tablespoon'));
  });
});

describe('geminiAnswerText', () => {
  it('joins the text parts and skips thoughts', () => {
    const response = {
      candidates: [
        {
          content: {
            parts: [
              { text: 'thinking', thought: true },
              { text: 'Hello ' },
              { functionCall: {} },
              { text: 'world', thoughtSignature: 'abc' },
            ],
          },
        },
      ],
    };
    assert.equal(geminiAnswerText(response), 'Hello world');
  });

  it('returns an empty text without candidate', () => {
    assert.equal(geminiAnswerText({}), '');
  });
});
