import 'package:flutter/material.dart';

import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';

/// Phone number visibility for a trip member.
enum TripMemberPhoneVisibility {
  nobody('nobody'),
  owner('owner'),
  admin('admin'),
  participant('participant');

  const TripMemberPhoneVisibility(this.value);

  final String value;

  static TripMemberPhoneVisibility? fromString(String? s) {
    if (s == null) return null;
    for (final v in values) {
      if (v.value == s) return v;
    }
    return null;
  }

  String toFirestore() => value;
}

/// Inclusive stay bounds for a traveler on a trip (calendar days + day part).
class TripMemberStay {
  const TripMemberStay({
    required this.startDateKey,
    required this.startDayPart,
    required this.endDateKey,
    required this.endDayPart,
  });

  final String startDateKey;
  final TripDayPart startDayPart;
  final String endDateKey;
  final TripDayPart endDayPart;

  static TripMemberStay? tryFromFirestore(Map<String, dynamic> data) {
    final sk = (data['stayStartDateKey'] as String?)?.trim() ?? '';
    final ek = (data['stayEndDateKey'] as String?)?.trim() ?? '';
    final sp = tripDayPartFromFirestore(data['stayStartDayPart'] as String?);
    final ep = tripDayPartFromFirestore(data['stayEndDayPart'] as String?);
    if (sk.isEmpty || ek.isEmpty || sp == null || ep == null) {
      return null;
    }
    return TripMemberStay(
      startDateKey: sk,
      startDayPart: sp,
      endDateKey: ek,
      endDayPart: ep,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'stayStartDateKey': startDateKey,
      'stayStartDayPart': tripDayPartToFirestore(startDayPart),
      'stayEndDateKey': endDateKey,
      'stayEndDayPart': tripDayPartToFirestore(endDayPart),
    };
  }

  TripMemberStay copyWith({
    String? startDateKey,
    TripDayPart? startDayPart,
    String? endDateKey,
    TripDayPart? endDayPart,
  }) {
    return TripMemberStay(
      startDateKey: startDateKey ?? this.startDateKey,
      startDayPart: startDayPart ?? this.startDayPart,
      endDateKey: endDateKey ?? this.endDateKey,
      endDayPart: endDayPart ?? this.endDayPart,
    );
  }

  /// Full span: morning of first day through evening of last day.
  static TripMemberStay defaultForTrip(Trip trip) {
    final start = trip.startDate != null
        ? DateUtils.dateOnly(trip.startDate!)
        : DateUtils.dateOnly(DateTime.now());
    final end = trip.endDate != null
        ? DateUtils.dateOnly(trip.endDate!)
        : start;
    final later = end.isBefore(start) ? start : end;
    return TripMemberStay(
      startDateKey: dateKeyFromDateTime(start),
      startDayPart: TripDayPart.morning,
      endDateKey: dateKeyFromDateTime(later),
      endDayPart: TripDayPart.evening,
    );
  }

  static TripMemberStay defaultForInviteContext({
    required DateTime? tripStartDate,
    required DateTime? tripEndDate,
  }) {
    final start = tripStartDate != null
        ? DateUtils.dateOnly(tripStartDate)
        : DateUtils.dateOnly(DateTime.now());
    final end = tripEndDate != null
        ? DateUtils.dateOnly(tripEndDate)
        : start;
    final later = end.isBefore(start) ? start : end;
    final isSingleDay = start.isAtSameMomentAs(later);
    return TripMemberStay(
      startDateKey: dateKeyFromDateTime(start),
      startDayPart: isSingleDay ? TripDayPart.morning : TripDayPart.evening,
      endDateKey: dateKeyFromDateTime(later),
      endDayPart: isSingleDay ? TripDayPart.evening : TripDayPart.morning,
    );
  }

  static String dateKeyFromDateTime(DateTime d) {
    final local = DateUtils.dateOnly(d);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static DateTime? parseDateKey(String key) {
    final p = key.trim().split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// Total order for (date key string, day part).
  static int _ordinal(String dateKey, TripDayPart part) {
    final base = parseDateKey(dateKey);
    if (base == null) return -1;
    return base.millisecondsSinceEpoch * 3 + tripDayPartSortIndex(part);
  }

  static bool isChronological(TripMemberStay s) {
    return _ordinal(s.startDateKey, s.startDayPart) <=
        _ordinal(s.endDateKey, s.endDayPart);
  }

  static bool withinTripCalendarBounds({
    required TripMemberStay stay,
    required Trip trip,
  }) {
    final ts = trip.startDate != null ? DateUtils.dateOnly(trip.startDate!) : null;
    final te = trip.endDate != null ? DateUtils.dateOnly(trip.endDate!) : null;
    if (ts == null && te == null) {
      return true;
    }
    final s0 = parseDateKey(stay.startDateKey);
    final s1 = parseDateKey(stay.endDateKey);
    if (s0 == null || s1 == null) return false;
    if (ts != null && s0.isBefore(ts)) return false;
    if (te != null && s1.isAfter(te)) return false;
    return true;
  }

  static bool withinInviteDateBounds({
    required TripMemberStay stay,
    required DateTime? tripStartDate,
    required DateTime? tripEndDate,
  }) {
    final ts =
        tripStartDate != null ? DateUtils.dateOnly(tripStartDate) : null;
    final te = tripEndDate != null ? DateUtils.dateOnly(tripEndDate) : null;
    if (ts == null && te == null) {
      return true;
    }
    final s0 = parseDateKey(stay.startDateKey);
    final s1 = parseDateKey(stay.endDateKey);
    if (s0 == null || s1 == null) return false;
    if (ts != null && s0.isBefore(ts)) return false;
    if (te != null && s1.isAfter(te)) return false;
    return true;
  }
}
