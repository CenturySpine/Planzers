import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Asks for the planned day then time of an activity; null when cancelled.
/// Opens on [current], otherwise on [fallbackDay], otherwise today.
Future<DateTime?> pickTripActivityDateTime(
  BuildContext context, {
  DateTime? current,
  DateTime? fallbackDay,
}) async {
  final now = DateTime.now();
  final localCurrent = current?.toLocal();
  final initialDate = DateUtils.dateOnly(localCurrent ?? fallbackDay ?? now);
  final minSelectableDate = DateTime(now.year - 5);
  final maxSelectableDate = DateTime(now.year + 5);
  final pickedDate = await showDatePicker(
    context: context,
    locale: Localizations.localeOf(context),
    initialDate: initialDate,
    firstDate: initialDate.isBefore(minSelectableDate)
        ? initialDate
        : minSelectableDate,
    lastDate: initialDate.isAfter(maxSelectableDate)
        ? initialDate
        : maxSelectableDate,
    helpText: AppLocalizations.of(context)!.activitiesPlannedDateHelp,
  );
  if (pickedDate == null || !context.mounted) return null;
  final initialTime = TimeOfDay.fromDateTime(localCurrent ?? now);
  final pickedTime = await showTimePicker(
    context: context,
    initialTime: initialTime,
  );
  if (pickedTime == null) return null;
  return DateTime(
    pickedDate.year,
    pickedDate.month,
    pickedDate.day,
    pickedTime.hour,
    pickedTime.minute,
  );
}
