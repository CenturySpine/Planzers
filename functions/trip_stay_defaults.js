function normalizeString(value) {
  return (typeof value === 'string' ? value : '').trim();
}

function dateKey(date) {
  const year = date.getFullYear().toString().padStart(4, '0');
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

/**
 * Builds default stay fields for a new participant slot using trip calendar bounds.
 * Preparation trips intentionally have no stay fields until dates are configured.
 * @param {object} tripData - Firestore trip document data
 * @returns {object} Firestore-ready stay fields
 */
function defaultStayForTrip(tripData) {
  if (normalizeString(tripData?.lifecycleStatus) === 'preparation') {
    return {};
  }

  const parseDate = (raw) => {
    if (!raw) return null;
    const date = typeof raw.toDate === 'function' ? raw.toDate() : new Date(raw);
    if (isNaN(date.getTime())) return null;
    // Trip dates are stored as midnight local time (e.g. UTC+2), which arrives
    // as 22:00 UTC the day before on the server. Adding 12h normalises any
    // UTC offset up to +/-12h before the day is extracted.
    return new Date(date.getTime() + 12 * 60 * 60 * 1000);
  };
  const tripStartDate = parseDate(tripData?.startDate);
  const tripEndDate = parseDate(tripData?.endDate);

  if (!tripStartDate && !tripEndDate) {
    const now = new Date();
    const start = startOfDay(now);
    const end = new Date(start);
    end.setDate(end.getDate() + 1);
    return {
      stayStartDateKey: dateKey(start),
      stayStartDayPart: 'evening',
      stayEndDateKey: dateKey(end),
      stayEndDayPart: 'morning',
    };
  }

  const start = tripStartDate ? startOfDay(tripStartDate) : startOfDay(new Date());
  const end = tripEndDate ? startOfDay(tripEndDate) : start;
  const later = end < start ? start : end;
  const isSingleDay = start.getTime() === later.getTime();
  return {
    stayStartDateKey: dateKey(start),
    stayStartDayPart: isSingleDay ? 'morning' : 'evening',
    stayEndDateKey: dateKey(later),
    stayEndDayPart: isSingleDay ? 'evening' : 'morning',
  };
}

module.exports = {
  defaultStayForTrip,
};
