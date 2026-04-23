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

/// Compares calendar days in local time.
bool isEndBeforeStart(DateTime? start, DateTime? end) {
  if (start == null || end == null) return false;
  final s = DateUtils.dateOnly(start);
  final e = DateUtils.dateOnly(end);
  return e.isBefore(s);
}
