/**
 * Trip lifecycle after the trip ends, applied to every traveler of the trip:
 * - day end + 30: the trip is archived for each member who has not archived
 *   it yet (once: a member who unarchives it afterwards is left alone);
 * - day end + 60: every traveler's personal documents ("Mes documents") of
 *   the trip are deleted, whether the trip was archived or not.
 *
 * Days are calendar days in Europe/Paris, counted from the trip's last day
 * (end date, or start date for trips without one), as shown in the app.
 * Progress is recorded in tripLifecycle/{tripId} (server-only) so each step
 * runs once.
 */

const AUTO_ARCHIVE_AFTER_DAYS = 30;
const WALLET_RETENTION_DAYS = 60;
/** Trips ended longer ago are assumed processed (covers ~3 months of missed runs). */
const LOOKBACK_DAYS = 150;
const DAY_MS = 24 * 60 * 60 * 1000;
const TIME_ZONE = 'Europe/Paris';

const parisDateFormat = new Intl.DateTimeFormat('en-CA', {
  timeZone: TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/**
 * Calendar day of [date] in Europe/Paris, as a day count since epoch.
 * @param {Date} date
 * @returns {number}
 */
function parisDayNumber(date) {
  const [y, m, d] = parisDateFormat.format(date).split('-').map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / DAY_MS);
}

/**
 * @param {object} tripData
 * @returns {Date|null} the trip's last day (end date, else start date)
 */
function tripLastDay(tripData) {
  const raw = tripData?.endDate ?? tripData?.startDate ?? null;
  if (!raw) return null;
  if (typeof raw.toDate === 'function') return raw.toDate();
  if (raw instanceof Date) return raw;
  if (typeof raw === 'string') {
    const parsed = new Date(raw);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

/**
 * Which lifecycle steps are due for a trip today.
 * @param {{ tripData: object, lifecycle: object, now: Date }} args
 * @returns {{ archive: boolean, purgeWallet: boolean }}
 */
function dueLifecycleSteps({ tripData, lifecycle, now }) {
  const lastDay = tripLastDay(tripData);
  if (!lastDay) return { archive: false, purgeWallet: false };
  const daysSinceEnd = parisDayNumber(now) - parisDayNumber(lastDay);
  return {
    archive: daysSinceEnd >= AUTO_ARCHIVE_AFTER_DAYS && !lifecycle?.autoArchivedAt,
    purgeWallet: daysSinceEnd >= WALLET_RETENTION_DAYS && !lifecycle?.walletPurgedAt,
  };
}

const ALREADY_EXISTS = 6;

/**
 * Archives the trip for every member who has not archived it yet; an
 * existing (manual) archive keeps its own date.
 */
async function autoArchiveTripForMembers({ db, FieldValue, tripId, memberUserIds }) {
  const uids = Array.isArray(memberUserIds)
    ? [...new Set(memberUserIds.map((v) => String(v)).filter(Boolean))]
    : [];
  for (const uid of uids) {
    try {
      await db
        .collection('users')
        .doc(uid)
        .collection('archivedTrips')
        .doc(tripId)
        .create({ archivedAt: FieldValue.serverTimestamp(), auto: true });
    } catch (e) {
      if (e?.code !== ALREADY_EXISTS && e?.code !== 'already-exists') throw e;
    }
  }
}

/**
 * Runs the due steps for every trip ended within the lookback window.
 * @param {{ db: object, bucket: object, FieldValue: object, Timestamp: object,
 *   deleteMemberWalletData: Function, now?: Date, logger?: object }} args
 */
async function runTripLifecycle({
  db,
  bucket,
  FieldValue,
  Timestamp,
  deleteMemberWalletData,
  now = new Date(),
  logger = console,
}) {
  // One extra day on each side absorbs the Paris/UTC offset of stored dates.
  const from = Timestamp.fromDate(new Date(now.getTime() - (LOOKBACK_DAYS + 1) * DAY_MS));
  const to = Timestamp.fromDate(new Date(now.getTime() - (AUTO_ARCHIVE_AFTER_DAYS - 1) * DAY_MS));
  const tripsSnap = await db
    .collection('trips')
    .where('endDate', '>=', from)
    .where('endDate', '<=', to)
    .get();

  const summary = { trips: tripsSnap.size, archived: 0, purged: 0, failed: 0 };
  for (const tripDoc of tripsSnap.docs) {
    const tripId = tripDoc.id;
    const tripData = tripDoc.data() || {};
    const lifecycleRef = db.collection('tripLifecycle').doc(tripId);
    try {
      const lifecycle = (await lifecycleRef.get()).data() || {};
      const due = dueLifecycleSteps({ tripData, lifecycle, now });

      if (due.archive) {
        await autoArchiveTripForMembers({
          db,
          FieldValue,
          tripId,
          memberUserIds: tripData.memberUserIds,
        });
        await lifecycleRef.set(
          { autoArchivedAt: FieldValue.serverTimestamp() },
          { merge: true }
        );
        summary.archived++;
      }

      if (due.purgeWallet) {
        // Members, plus anyone who still has personal module data here.
        const moduleRefs = await tripDoc.ref.collection('travelerModules').listDocuments();
        const uids = new Set([
          ...(Array.isArray(tripData.memberUserIds) ? tripData.memberUserIds.map(String) : []),
          ...moduleRefs.map((ref) => ref.id),
        ]);
        let allDeleted = true;
        for (const uid of uids) {
          const ok = await deleteMemberWalletData({ db, bucket, tripId, uid, logger });
          if (ok === false) allDeleted = false;
        }
        // Not marked done on failure: retried on the next run.
        if (allDeleted) {
          await lifecycleRef.set(
            { walletPurgedAt: FieldValue.serverTimestamp() },
            { merge: true }
          );
          summary.purged++;
        } else {
          summary.failed++;
        }
      }
    } catch (e) {
      summary.failed++;
      logger.error('trip lifecycle failed', { tripId, error: String(e) });
    }
  }
  return summary;
}

module.exports = {
  AUTO_ARCHIVE_AFTER_DAYS,
  WALLET_RETENTION_DAYS,
  parisDayNumber,
  tripLastDay,
  dueLifecycleSteps,
  autoArchiveTripForMembers,
  runTripLifecycle,
};
