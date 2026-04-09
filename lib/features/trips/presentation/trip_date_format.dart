import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Single date for form rows, or placeholder when unset.
String formatOptionalTripDate(DateTime? d) {
  if (d == null) return 'Non renseignée';
  return DateFormat.yMMMEd('fr_FR').format(d);
}

/// User-facing label for optional trip bounds (French UI).
String formatTripDateRange(DateTime? start, DateTime? end) {
  final fmt = DateFormat.yMMMEd('fr_FR');
  if (start != null && end != null) {
    return 'Du ${fmt.format(start)} au ${fmt.format(end)}';
  }
  if (start != null) {
    return 'À partir du ${fmt.format(start)}';
  }
  if (end != null) {
    return "Jusqu'au ${fmt.format(end)}";
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
