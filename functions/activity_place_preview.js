'use strict';

/**
 * What to look up on Google Places for an activity's place: the place picked
 * on OpenStreetMap, i.e. its address (which starts with the place's name when
 * OpenStreetMap knows one), or its label when it only has a point, near that
 * point. Null for a transport (its place is a station or an airport) or an
 * activity without a place.
 * @param {FirebaseFirestore.DocumentData} data
 * @returns {{ query: string, lat: number | null, lng: number | null } | null}
 */
function activityPlaceQuery(data) {
  if (!data || data.category === 'transport') return null;
  const address = typeof data.address === 'string' ? data.address.trim() : '';
  const lat = Number(data.location?.latitude);
  const lng = Number(data.location?.longitude);
  const hasPoint = Number.isFinite(lat) && Number.isFinite(lng);
  const label = typeof data.label === 'string' ? data.label.trim() : '';
  const query = address || (hasPoint ? label : '');
  if (!query) return null;
  return { query, lat: hasPoint ? lat : null, lng: hasPoint ? lng : null };
}

/**
 * Identifies the place looked up, to look it up again only when it changes.
 * @param {FirebaseFirestore.DocumentData} data
 */
function activityPlaceQueryKey(data) {
  const place = activityPlaceQuery(data);
  return place ? `${place.query}|${place.lat ?? ''},${place.lng ?? ''}` : '';
}

module.exports = {
  activityPlaceQuery,
  activityPlaceQueryKey,
};
