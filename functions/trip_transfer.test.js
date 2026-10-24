'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { GeoPoint, Timestamp } = require('firebase-admin/firestore');
const {
  EXPORTER_PLACEHOLDER,
  TRANSFERRED_COLLECTIONS,
  normalizeAppVersion,
  toTransferValue,
  fromTransferValue,
  remapAccountIds,
  participantForImport,
  tripDataForTransfer,
  photoSubjectForTransfer,
  isValidDocId,
  isOwnTransferPath,
  generateInviteToken,
  importedTripTitle,
  parseTransferFile,
  collectionWrites,
} = require('./trip_transfer');

if (admin.apps.length === 0) admin.initializeApp({ projectId: 'trip-transfer-test' });

describe('normalizeAppVersion', () => {
  it('keeps the semver version only', () => {
    assert.equal(normalizeAppVersion('0.5.2'), '0.5.2');
    assert.equal(normalizeAppVersion(' v0.5.2 '), '0.5.2');
    assert.equal(normalizeAppVersion('0.5.2+29'), '0.5.2');
    assert.equal(normalizeAppVersion('0.6.0-beta1'), '0.6.0-beta1');
  });

  it('rejects anything else', () => {
    assert.equal(normalizeAppVersion(''), '');
    assert.equal(normalizeAppVersion('0.5'), '');
    assert.equal(normalizeAppVersion(52), '');
  });
});

describe('transfer values', () => {
  it('round-trips timestamps and GPS points', () => {
    const value = {
      plannedAt: new Timestamp(1700000000, 123),
      location: new GeoPoint(48.85, 2.35),
      nested: [{ at: new Timestamp(1, 2) }],
      amount: 12.5,
      label: 'Musée',
    };
    const json = JSON.parse(JSON.stringify(toTransferValue(value)));
    const back = fromTransferValue(json);
    assert.ok(back.plannedAt.isEqual(value.plannedAt));
    assert.ok(back.location.isEqual(value.location));
    assert.ok(back.nested[0].at.isEqual(value.nested[0].at));
    assert.equal(back.amount, 12.5);
    assert.equal(back.label, 'Musée');
  });

  it('rejects unknown or malformed tagged values', () => {
    assert.throws(() => fromTransferValue({ __type: 'reference', path: 'users/x' }));
    assert.throws(() => fromTransferValue({ __type: 'timestamp', seconds: 'x', nanoseconds: 0 }));
  });
});

describe('remapAccountIds', () => {
  const toFile = { from: 'exporterUid', to: EXPORTER_PLACEHOLDER };
  const toImporter = { from: EXPORTER_PLACEHOLDER, to: 'importerUid' };

  it('keeps the exporter as a placeholder and drops other travelers', () => {
    const out = remapAccountIds(
      {
        createdBy: 'aliceUid',
        claimedBy: 'aliceUid',
        votes: ['aliceUid', 'exporterUid'],
        potluckItems: [
          { label: 'Vin', addedBy: 'exporterUid' },
          { label: 'Pain', addedBy: 'aliceUid' },
        ],
        cars: [{ createdByUserId: 'aliceUid', driverParticipantId: 'p1' }],
        paidBy: 'p1',
      },
      toFile
    );
    assert.deepEqual(out, {
      createdBy: EXPORTER_PLACEHOLDER,
      votes: [EXPORTER_PLACEHOLDER],
      potluckItems: [
        { label: 'Vin', addedBy: EXPORTER_PLACEHOLDER },
        { label: 'Pain' },
      ],
      cars: [{ createdByUserId: EXPORTER_PLACEHOLDER, driverParticipantId: 'p1' }],
      paidBy: 'p1',
    });
  });

  it('gives the exporter slot to the importer and leaves the others to claim', () => {
    assert.deepEqual(
      remapAccountIds({ participantName: 'Bruno', userId: EXPORTER_PLACEHOLDER }, toImporter),
      { participantName: 'Bruno', userId: 'importerUid' }
    );
    assert.deepEqual(
      remapAccountIds({ participantName: 'Alice', userId: 'aliceUid' }, toImporter),
      { participantName: 'Alice' }
    );
  });

  it('attributes every author to the importer, even from a crafted file', () => {
    assert.deepEqual(
      remapAccountIds({ authorId: 'someoneElse', votes: ['someoneElse'] }, toImporter),
      { authorId: 'importerUid', votes: [] }
    );
  });
});

describe('participantForImport', () => {
  it('starts Cupidon over', () => {
    const out = participantForImport({
      participantName: 'Alice',
      cupidonEnabled: true,
      cupidonUpdatedAt: 'x',
      isChild: true,
    });
    assert.deepEqual(out, { participantName: 'Alice', cupidonEnabled: false, isChild: true });
  });
});

describe('tripDataForTransfer', () => {
  it('leaves out the fields recreated for the new trip', () => {
    const out = tripDataForTransfer({
      title: 'Ski',
      ownerId: 'u1',
      memberUserIds: ['u1'],
      adminMemberIds: ['u2'],
      inviteToken: 'ABC-123',
      participantCount: 4,
      bannerImageUrl: 'https://x',
      bannerImagePath: 'trips/t/banner_1.jpg',
      permissions: { tripGeneral: {} },
    });
    assert.deepEqual(out, { title: 'Ski', permissions: { tripGeneral: {} } });
  });
});

describe('photoSubjectForTransfer', () => {
  const subjects = { activityIds: new Set(['a1']), mealIds: new Set(['m1']) };

  it('keeps the activity or the meal a photo belongs to', () => {
    assert.deepEqual(photoSubjectForTransfer({ activityId: 'a1' }, subjects), { activityId: 'a1' });
    assert.deepEqual(photoSubjectForTransfer({ mealId: 'm1' }, subjects), { mealId: 'm1' });
  });

  it('drops a photo whose activity or meal is not transferred', () => {
    assert.equal(photoSubjectForTransfer({ activityId: 'a2' }, subjects), null);
    assert.equal(photoSubjectForTransfer({ mealId: 'm2' }, subjects), null);
    assert.equal(photoSubjectForTransfer({ mealId: 'a1' }, subjects), null);
    assert.equal(photoSubjectForTransfer({}, subjects), null);
  });
});

describe('isValidDocId', () => {
  it('accepts stored ids and rejects paths', () => {
    assert.equal(isValidDocId('aB3_x-9'), true);
    assert.equal(isValidDocId('default'), true);
    assert.equal(isValidDocId(''), false);
    assert.equal(isValidDocId('a/b'), false);
    assert.equal(isValidDocId('..'), false);
    assert.equal(isValidDocId('__name__'), false);
  });
});

describe('isOwnTransferPath', () => {
  it('only accepts files in the caller transfer folder', () => {
    assert.equal(isOwnTransferPath('users/u1/tripTransfers/import-1.json', 'u1'), true);
    assert.equal(isOwnTransferPath('users/u2/tripTransfers/import-1.json', 'u1'), false);
    assert.equal(isOwnTransferPath('users/u1/tripTransfers/../wallet/x.pdf', 'u1'), false);
    assert.equal(isOwnTransferPath('users/u1/tripTransfers/', 'u1'), false);
  });
});

describe('generateInviteToken', () => {
  it('has the app format', () => {
    assert.match(generateInviteToken(), /^[A-Z0-9]{3}-[A-Z0-9]{3}$/);
  });
});

describe('importedTripTitle', () => {
  it('marks the copy once', () => {
    assert.equal(importedTripTitle('Ski 2026'), 'Ski 2026 (export)');
    assert.equal(importedTripTitle('Ski 2026 (export)'), 'Ski 2026 (export)');
    assert.equal(importedTripTitle('  '), '(export)');
  });
});

describe('parseTransferFile', () => {
  const file = (overrides) =>
    JSON.stringify({
      format: 'planerz-trip',
      formatVersion: 1,
      appVersion: '0.5.2',
      trip: { data: { title: 'Ski' }, collections: {} },
      ...overrides,
    });

  it('accepts a file of the same app version', () => {
    assert.equal(parseTransferFile(file({}), '0.5.2').trip.data.title, 'Ski');
  });

  it('refuses another app version', () => {
    assert.throws(
      () => parseTransferFile(file({ appVersion: '0.5.1' }), '0.5.2'),
      (e) => e.code === 'failed-precondition' && e.details.reason === 'version-mismatch'
    );
  });

  it('refuses other files', () => {
    assert.throws(
      () => parseTransferFile('{not json', '0.5.2'),
      (e) => e.details.reason === 'invalid-file'
    );
    assert.throws(
      () => parseTransferFile(file({ format: 'other' }), '0.5.2'),
      (e) => e.details.reason === 'invalid-file'
    );
  });
});

describe('collectionWrites', () => {
  const tripRef = admin.firestore().collection('trips').doc('newTrip');
  const accounts = { from: EXPORTER_PLACEHOLDER, to: 'importerUid' };

  it('recreates the carried-over documents under the new trip, ids kept', () => {
    const writes = collectionWrites(
      tripRef,
      {
        participants: {
          p1: { data: { participantName: 'Bruno', userId: EXPORTER_PLACEHOLDER } },
          p2: { data: { participantName: 'Alice', cupidonEnabled: true } },
        },
        expenseGroups: {
          g1: {
            data: { title: 'Commun', visibleToMemberIds: ['p1', 'p2'] },
            collections: { balances: { EUR: { data: { nets: { p1: 10, p2: -10 } } } } },
          },
        },
        messages: { m1: { data: { text: 'hello' } } },
      },
      TRANSFERRED_COLLECTIONS,
      accounts
    );
    assert.deepEqual(
      writes.map(({ ref }) => ref.path),
      [
        'trips/newTrip/participants/p1',
        'trips/newTrip/participants/p2',
        'trips/newTrip/expenseGroups/g1',
        'trips/newTrip/expenseGroups/g1/balances/EUR',
      ]
    );
    assert.equal(writes[0].data.userId, 'importerUid');
    assert.equal(writes[1].data.cupidonEnabled, false);
  });

  it('refuses ids that would escape the trip', () => {
    assert.throws(() =>
      collectionWrites(
        tripRef,
        { rooms: { 'a/b': { data: {} } } },
        TRANSFERRED_COLLECTIONS,
        accounts
      )
    );
  });
});
