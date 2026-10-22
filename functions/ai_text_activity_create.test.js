'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  PROPOSAL_CATEGORIES,
  canSuggestActivity,
  tripCalendar,
  sanitizeTextProposal,
  buildTextToolSchema,
  buildTextSystemPrompt,
  buildTextContextPrompt,
} = require('./ai_text_activity_create');

describe('canSuggestActivity', () => {
  const trip = {
    ownerId: 'owner',
    adminMemberIds: ['co-admin'],
    memberUserIds: ['owner', 'co-admin', 'member'],
  };

  it('accepts every member by default', () => {
    assert.equal(canSuggestActivity(trip, 'owner'), true);
    assert.equal(canSuggestActivity(trip, 'co-admin'), true);
    assert.equal(canSuggestActivity(trip, 'member'), true);
  });

  it('rejects non members and anonymous callers', () => {
    assert.equal(canSuggestActivity(trip, 'stranger'), false);
    assert.equal(canSuggestActivity(trip, ''), false);
  });

  it('follows the trip suggestActivity setting', () => {
    const adminOnly = { ...trip, permissions: { activities: { suggestActivity: 'admin' } } };
    assert.equal(canSuggestActivity(adminOnly, 'co-admin'), true);
    assert.equal(canSuggestActivity(adminOnly, 'member'), false);
    const ownerOnly = { ...trip, permissions: { activities: { suggestActivity: 'owner' } } };
    assert.equal(canSuggestActivity(ownerOnly, 'owner'), true);
    assert.equal(canSuggestActivity(ownerOnly, 'co-admin'), false);
  });
});

describe('tripCalendar', () => {
  it('lists each trip day with its weekday', () => {
    assert.deepEqual(tripCalendar('2026-07-10', '2026-07-12'), [
      '2026-07-10 (Friday)',
      '2026-07-11 (Saturday)',
      '2026-07-12 (Sunday)',
    ]);
  });

  it('stays empty for unknown, inverted or long trips', () => {
    assert.deepEqual(tripCalendar('', '2026-07-12'), []);
    assert.deepEqual(tripCalendar('2026-07-12', '2026-07-10'), []);
    assert.deepEqual(tripCalendar('2026-07-01', '2026-08-15'), []);
    assert.equal(tripCalendar('2026-07-01', '2026-07-31').length, 31);
  });
});

describe('sanitizeTextProposal', () => {
  it('cleans a model proposal', () => {
    assert.deepEqual(
      sanitizeTextProposal({
        label: '  Randonnée dans les gorges ',
        category: 'hiking',
        plannedAtLocal: '2026-07-11T09:00',
        durationMinutes: 240,
        address: ' Gorropu ',
        freeComments: 'Déjeuner au port',
      }),
      {
        label: 'Randonnée dans les gorges',
        category: 'hiking',
        plannedAtLocal: '2026-07-11T09:00',
        durationMinutes: 240,
        address: 'Gorropu',
        freeComments: 'Déjeuner au port',
      }
    );
  });

  it('falls back to visit and drops invalid values', () => {
    const result = sanitizeTextProposal({
      label: 'Balade',
      category: 'unknown',
      plannedAtLocal: 'samedi',
      durationMinutes: 0,
    });
    assert.equal(result.category, 'visit');
    assert.equal(result.plannedAtLocal, '');
    assert.equal(result.durationMinutes, null);
  });

  it('drops meals, items longer than a day and unlabelled ones', () => {
    assert.equal(sanitizeTextProposal({ label: 'Dîner', category: 'restaurant' }), null);
    assert.equal(sanitizeTextProposal({ label: 'Circuit', durationMinutes: 3000 }), null);
    assert.equal(sanitizeTextProposal({ label: '  ' }), null);
    assert.equal(sanitizeTextProposal(null), null);
  });
});

describe('buildTextToolSchema', () => {
  it('never offers restaurant', () => {
    const schema = buildTextToolSchema();
    const category = schema.properties.activities.items.properties.category;
    assert.deepEqual(category.enum, PROPOSAL_CATEGORIES);
    assert.equal(category.enum.includes('restaurant'), false);
  });
});

describe('buildTextSystemPrompt', () => {
  it('follows the output language', () => {
    assert.match(buildTextSystemPrompt('fr'), /French/);
    assert.match(buildTextSystemPrompt('en'), /English/);
  });
});

describe('buildTextContextPrompt', () => {
  it('gives the current date, the trip calendar and the text', () => {
    const prompt = buildTextContextPrompt({
      trip: { title: 'Sardaigne', startDate: '2026-07-10', endDate: '2026-07-12' },
      text: 'Ce matin rando, puis plage',
      nowLocal: '2026-07-11T21:30',
    });
    assert.match(prompt, /Current local date and time: 2026-07-11T21:30 \(Saturday\)/);
    assert.match(prompt, /Trip calendar: 2026-07-10 \(Friday\), 2026-07-11 \(Saturday\)/);
    assert.match(prompt, /<<<\nCe matin rando, puis plage\n>>>/);
  });

  it('omits the current date when unknown', () => {
    const prompt = buildTextContextPrompt({ trip: {}, text: 'Rando', nowLocal: '' });
    assert.doesNotMatch(prompt, /Current local date/);
  });
});
