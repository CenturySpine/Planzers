import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Single calendar day picker for day-trip outings (no meal day-part bounds).
class TripSingleDayDateField extends StatelessWidget {
  const TripSingleDayDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final low = DateTime(now.year - 1);
    final high = DateTime(now.year + 2, 12, 31);
    final initial =
        value != null ? DateUtils.dateOnly(value!) : DateUtils.dateOnly(now);
    final picked = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: initial.isBefore(low)
          ? low
          : initial.isAfter(high)
              ? high
              : initial,
      firstDate: low,
      lastDate: high,
    );
    if (picked == null) return;
    onChanged(DateUtils.dateOnly(picked));
  }

  String _dateLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null) return l10n.commonNotProvided;
    return DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .format(value!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _pickDate(context),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(_dateLabel(context)),
          ),
        ),
      ],
    );
  }
}
