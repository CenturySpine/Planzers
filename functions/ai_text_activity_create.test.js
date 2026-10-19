'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  PROPOSAL_CATEGORIES,
  canSuggestActivity,
  sanitizeAllowedCategories,
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

describe('sanitizeAllowedCategories', () => {
  it('keeps the known categories offered by the form', () => {
    assert.deepEqual(sanitizeAllowedCategories(['transport', 'unknown']), ['transport']);
  });

  it('never offers restaurant', () => {
    assert.deepEqual(sanitizeAllowedCategories(['restaurant', 'beach']), ['beach']);
    assert.equal(PROPOSAL_CATEGORIES.includes('restaurant'), false);
  });

  it('falls back to every category', () => {
    assert.deepEqual(sanitizeAllowedCategories(undefined), PROPOSAL_CATEGORIES);
    assert.deepEqual(sanitizeAllowedCategories(['restaurant']), PROPOSAL_CATEGORIES);
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
  const allowed = ['beach', 'sport'];

  it('cleans the model proposal', () => {
    assert.deepEqual(
      sanitizeTextProposal(
        {
          label: '  Kayak à Cala Gonone ',
          category: 'sport',
          plannedAtLocal: '2026-07-11T14:00',
          durationMinutes: 180,
          address: ' Plage de Cala Gonone ',
          freeComments: '',
        },
        allowed
      ),
      {
        label: 'Kayak à Cala Gonone',
        category: 'sport',
        plannedAtLocal: '2026-07-11T14:00',
        durationMinutes: 180,
        address: 'Plage de Cala Gonone',
        freeComments: '',
      }
    );
  });

  it('falls back to the first allowed category and drops invalid values', () => {
    const result = sanitizeTextProposal(
      { label: 'Kayak', category: 'museum', plannedAtLocal: 'samedi', durationMinutes: 0 },
      allowed
    );
    assert.equal(result.category, 'beach');
    assert.equal(result.plannedAtLocal, '');
    assert.equal(result.durationMinutes, null);
  });

  it('returns null when no activity was recognised', () => {
    assert.equal(sanitizeTextProposal({ label: '  ' }, allowed), null);
    assert.equal(sanitizeTextProposal(null, allowed), null);
  });
});

describe('buildTextToolSchema', () => {
  it('restricts the category to the allowed ones', () => {
    const schema = buildTextToolSchema(['transport']);
    assert.deepEqual(schema.properties.activity.properties.category.enum, ['transport']);
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
      text: 'Kayak samedi de 14h à 17h',
      nowLocal: '2026-06-01T09:30',
    });
    assert.match(prompt, /Current local date and time: 2026-06-01T09:30 \(Monday\)/);
    assert.match(prompt, /Trip calendar: 2026-07-10 \(Friday\), 2026-07-11 \(Saturday\)/);
    assert.match(prompt, /<<<\nKayak samedi de 14h à 17h\n>>>/);
  });

  it('omits the current date when unknown', () => {
    const prompt = buildTextContextPrompt({ trip: {}, text: 'Kayak', nowLocal: '' });
    assert.doesNotMatch(prompt, /Current local date/);
  });
});
