'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  ACTIVITY_CATEGORIES,
  MAX_DURATION_MINUTES,
  isTripAdminOrOwner,
  sanitizeIdList,
  sanitizeLocalDateTime,
  sanitizeDurationMinutes,
  sanitizeProposal,
  sortProposals,
  buildToolSchema,
  buildImportedActivity,
} = require('./ai_document_activity_import');

describe('isTripAdminOrOwner', () => {
  const trip = { ownerId: 'owner', adminMemberIds: ['co-admin'] };

  it('accepts the creator and co-admins', () => {
    assert.equal(isTripAdminOrOwner(trip, 'owner'), true);
    assert.equal(isTripAdminOrOwner(trip, 'co-admin'), true);
  });

  it('rejects other members and anonymous callers', () => {
    assert.equal(isTripAdminOrOwner(trip, 'member'), false);
    assert.equal(isTripAdminOrOwner(trip, ''), false);
    assert.equal(isTripAdminOrOwner({ ownerId: '' }, ''), false);
  });
});

describe('sanitizeIdList', () => {
  it('keeps unique safe ids up to the limit', () => {
    assert.deepEqual(sanitizeIdList(['a', 'a', 'b/../c', ' d ', 'e'], 2), ['a', 'd']);
  });

  it('returns an empty list for non arrays', () => {
    assert.deepEqual(sanitizeIdList('a', 5), []);
  });
});

describe('sanitizeLocalDateTime', () => {
  it('keeps a valid local date time', () => {
    assert.equal(sanitizeLocalDateTime('2026-10-10T20:25'), '2026-10-10T20:25');
  });

  it('rejects offsets, seconds and impossible dates', () => {
    assert.equal(sanitizeLocalDateTime('2026-10-10T20:25Z'), '');
    assert.equal(sanitizeLocalDateTime('2026-10-10T20:25:00'), '');
    assert.equal(sanitizeLocalDateTime('2026-02-30T10:00'), '');
    assert.equal(sanitizeLocalDateTime('2026-10-10T24:00'), '');
    assert.equal(sanitizeLocalDateTime(''), '');
  });
});

describe('sanitizeDurationMinutes', () => {
  it('returns null for unknown or non positive durations', () => {
    assert.equal(sanitizeDurationMinutes(0), null);
    assert.equal(sanitizeDurationMinutes(-5), null);
    assert.equal(sanitizeDurationMinutes('abc'), null);
  });

  it('rounds and caps at seven days', () => {
    assert.equal(sanitizeDurationMinutes(125.4), 125);
    assert.equal(sanitizeDurationMinutes(99999), MAX_DURATION_MINUTES);
  });
});

describe('sanitizeProposal', () => {
  it('cleans a model proposal', () => {
    const result = sanitizeProposal(
      {
        label: '  Vol Paris → Rome  ',
        category: 'transport',
        plannedAtLocal: '2026-10-10T18:20',
        durationMinutes: 125,
        address: 'Aéroport',
        freeComments: 'Vol AF1234',
        sourceDocumentIds: ['doc1', 'unknown'],
      },
      ['doc1']
    );
    assert.deepEqual(result, {
      label: 'Vol Paris → Rome',
      category: 'transport',
      plannedAtLocal: '2026-10-10T18:20',
      durationMinutes: 125,
      address: 'Aéroport',
      freeComments: 'Vol AF1234',
      sourceDocumentIds: ['doc1'],
    });
  });

  it('falls back to visit for an unknown category and drops unlabeled items', () => {
    assert.equal(sanitizeProposal({ label: 'X', category: 'flight' }, []).category, 'visit');
    assert.equal(sanitizeProposal({ label: '   ' }, []), null);
    assert.equal(sanitizeProposal(null, []), null);
  });
});

describe('sortProposals', () => {
  it('orders chronologically and keeps unscheduled items last', () => {
    const sorted = sortProposals([
      { label: 'none', plannedAtLocal: '' },
      { label: 'late', plannedAtLocal: '2026-10-24T21:10' },
      { label: 'early', plannedAtLocal: '2026-10-10T18:20' },
    ]);
    assert.deepEqual(sorted.map((p) => p.label), ['early', 'late', 'none']);
  });
});

describe('buildToolSchema', () => {
  it('exposes every activity category', () => {
    const item = buildToolSchema().properties.activities.items;
    assert.deepEqual(item.properties.category.enum, ACTIVITY_CATEGORIES);
    assert.ok(item.required.includes('plannedAtLocal'));
  });
});

describe('buildImportedActivity', () => {
  it('builds the activity record', () => {
    const result = buildImportedActivity(
      {
        label: 'Vol',
        category: 'transport',
        plannedAtMillis: Date.UTC(2026, 9, 10, 16, 20),
        durationMinutes: 125,
        address: '',
        freeComments: 'AF1234',
        sourceDocumentIds: ['doc1'],
      },
      'uid1'
    );
    assert.equal(result.doc.label, 'Vol');
    assert.equal(result.doc.category, 'transport');
    assert.equal(result.doc.plannedAt.toMillis(), Date.UTC(2026, 9, 10, 16, 20));
    assert.equal(result.doc.durationMinutes, 125);
    assert.equal(result.doc.createdBy, 'uid1');
    assert.equal(result.doc.done, false);
    assert.deepEqual(result.sourceDocumentIds, ['doc1']);
  });

  it('leaves schedule fields out when absent', () => {
    const result = buildImportedActivity({ label: 'Visite' }, 'uid1');
    assert.equal('plannedAt' in result.doc, false);
    assert.equal('durationMinutes' in result.doc, false);
  });

  it('rejects an activity without label', () => {
    assert.equal(buildImportedActivity({ label: '' }, 'uid1'), null);
  });
});
