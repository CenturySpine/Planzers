import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Single date for form rows, or placeholder when unset.
String formatOptionalTripDate(BuildContext context, DateTime? d) {
  final l10n = AppLocalizations.of(context)!;
  if (d == null) return l10n.commonNotProvided;
  return DateFormat.yMMMEd(Localizations.localeOf(context).toString())
      .format(d);
}

/// User-facing label for optional trip bounds.
String formatTripDateRange(BuildContext context, DateTime? start, DateTime? end) {
  final l10n = AppLocalizations.of(context)!;
  final fmt = DateFormat.yMMMEd(Localizations.localeOf(context).toString());
  if (start != null && end != null) {
    return l10n.tripDateRangeBetween(fmt.format(start), fmt.format(end));
  }
  if (start != null) {
    return l10n.tripDateRangeFrom(fmt.format(start));
  }
  if (end != null) {
    return l10n.tripDateRangeUntil(fmt.format(end));
  }
  return '';
}

/// Single calendar day for day-trip outings.
String formatTripSingleDayDate(BuildContext context, DateTime? date) {
  if (date == null) return '';
  return DateFormat.yMMMEd(Localizations.localeOf(context).toString())
      .format(date);
}

/// Compares calendar days in local time.
bool isEndBeforeStart(DateTime? start, DateTime? end) {
  if (start == null || end == null) return false;
  final s = DateUtils.dateOnly(start);
  final e = DateUtils.dateOnly(end);
  return e.isBefore(s);
}

/// Compact range for headers, e.g. "25 – 29 sept. 2026" or
/// "30 sept. – 2 oct. 2026". Falls back to [formatTripDateRange] for open ranges.
String formatTripDateRangeCompact(
  BuildContext context,
  DateTime? start,
  DateTime? end,
) {
  if (start == null || end == null) {
    return formatTripDateRange(context, start, end);
  }
  final locale = Localizations.localeOf(context).toString();
  final full = DateFormat.yMMMd(locale);
  if (DateUtils.isSameDay(start, end)) return full.format(start);
  if (start.year == end.year && start.month == end.month) {
    return '${DateFormat.d(locale).format(start)} – ${full.format(end)}';
  }
  if (start.year == end.year) {
    return '${DateFormat.MMMd(locale).format(start)} – ${full.format(end)}';
  }
  return '${full.format(start)} – ${full.format(end)}';
}
