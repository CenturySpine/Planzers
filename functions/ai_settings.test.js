'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  DEFAULT_AI_SETTINGS,
  normalizeAiSettings,
  selectedModel,
  providerThinkingLevel,
  closeJsonSchemaObjects,
} = require('./ai_settings');

describe('normalizeAiSettings', () => {
  it('uses the defaults when the document does not exist', () => {
    assert.deepEqual(normalizeAiSettings(null), { ...DEFAULT_AI_SETTINGS });
  });

  it('keeps valid values', () => {
    const settings = normalizeAiSettings({
      provider: 'anthropic',
      googleModel: 'gemini-3.6-flash',
      anthropicModel: 'claude-sonnet-5-5',
      thinkingLevel: 'high',
    });
    assert.deepEqual(settings, {
      provider: 'anthropic',
      googleModel: 'gemini-3.6-flash',
      anthropicModel: 'claude-sonnet-5-5',
      thinkingLevel: 'high',
    });
  });

  it('replaces unknown or empty values by the defaults', () => {
    const settings = normalizeAiSettings({
      provider: 'openai',
      googleModel: '  ',
      anthropicModel: 42,
      thinkingLevel: 'max',
    });
    assert.deepEqual(settings, { ...DEFAULT_AI_SETTINGS });
  });
});

describe('selectedModel', () => {
  it('returns the model of the selected provider', () => {
    const base = normalizeAiSettings({ googleModel: 'g', anthropicModel: 'a' });
    assert.equal(selectedModel({ ...base, provider: 'google' }), 'g');
    assert.equal(selectedModel({ ...base, provider: 'anthropic' }), 'a');
  });
});

describe('providerThinkingLevel', () => {
  it('maps the generic levels to Gemini thinking levels', () => {
    assert.equal(providerThinkingLevel('google', 'minimal'), 'MINIMAL');
    assert.equal(providerThinkingLevel('google', 'low'), 'LOW');
    assert.equal(providerThinkingLevel('google', 'medium'), 'MEDIUM');
    assert.equal(providerThinkingLevel('google', 'high'), 'HIGH');
  });

  it('maps the generic levels to Claude effort levels', () => {
    assert.equal(providerThinkingLevel('anthropic', 'minimal'), 'low');
    assert.equal(providerThinkingLevel('anthropic', 'low'), 'low');
    assert.equal(providerThinkingLevel('anthropic', 'medium'), 'medium');
    assert.equal(providerThinkingLevel('anthropic', 'high'), 'high');
  });

  it('rejects an unknown provider', () => {
    assert.throws(() => providerThinkingLevel('openai', 'low'));
  });
});

describe('closeJsonSchemaObjects', () => {
  it('forbids extra properties on every nested object without changing the source', () => {
    const schema = {
      type: 'object',
      properties: {
        items: {
          type: 'array',
          items: { type: 'object', properties: { name: { type: 'string' } } },
        },
        sourceType: { type: 'string', enum: ['manual', 'recipe'] },
      },
    };
    const closed = closeJsonSchemaObjects(schema);
    assert.equal(closed.additionalProperties, false);
    assert.equal(closed.properties.items.items.additionalProperties, false);
    assert.equal('additionalProperties' in closed.properties.sourceType, false);
    assert.deepEqual(closed.properties.sourceType.enum, ['manual', 'recipe']);
    assert.equal('additionalProperties' in schema, false);
  });
});
