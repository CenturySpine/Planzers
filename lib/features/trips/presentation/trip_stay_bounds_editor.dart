import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planerz/l10n/app_localizations.dart';

import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';

/// Inclusive stay range: from date+part through date+part (matin / midi / soir).
class TripStayBoundsEditor extends StatelessWidget {
  const TripStayBoundsEditor({
    super.key,
    required this.tripStartDate,
    required this.tripEndDate,
    required this.value,
    required this.onChanged,
  });

  final DateTime? tripStartDate;
  final DateTime? tripEndDate;
  final TripMemberStay value;
  final ValueChanged<TripMemberStay> onChanged;

  static DateTimeRange _pickerBounds(DateTime? tripStart, DateTime? tripEnd) {
    final now = DateTime.now();
    if (tripStart != null && tripEnd != null) {
      final a = DateUtils.dateOnly(tripStart);
      final b = DateUtils.dateOnly(tripEnd);
      final first = a.isBefore(b) ? a : b;
      final last = a.isBefore(b) ? b : a;
      return DateTimeRange(start: first, end: last);
    }
    final low = DateTime(now.year - 1);
    final high = DateTime(now.year + 2, 12, 31);
    return DateTimeRange(start: low, end: high);
  }

  Future<void> _pickDate(
    BuildContext context, {
    required bool isStart,
  }) async {
    final bounds = _pickerBounds(tripStartDate, tripEndDate);
    final initial = TripMemberStay.parseDateKey(
          isStart ? value.startDateKey : value.endDateKey,
        ) ??
        bounds.start;
    final picked = await showDatePicker(
      context: context,
      locale: Localizations.localeOf(context),
      initialDate: _clampDate(initial, bounds),
      firstDate: bounds.start,
      lastDate: bounds.end,
    );
    if (picked == null) return;
    final key = TripMemberStay.dateKeyFromDateTime(picked);
    if (isStart) {
      onChanged(value.copyWith(startDateKey: key));
    } else {
      onChanged(value.copyWith(endDateKey: key));
    }
  }

  DateTime _clampDate(DateTime d, DateTimeRange bounds) {
    if (d.isBefore(bounds.start)) return bounds.start;
    if (d.isAfter(bounds.end)) return bounds.end;
    return d;
  }

  String _dateLabel(BuildContext context, String dateKey) {
    final d = TripMemberStay.parseDateKey(dateKey);
    if (d == null) return dateKey;
    return DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .format(d);
  }

  String _dayPartLabel(AppLocalizations l10n, TripDayPart part) {
    return switch (part) {
      TripDayPart.morning => l10n.dayPartMorning,
      TripDayPart.midday => l10n.dayPartMidday,
      TripDayPart.evening => l10n.dayPartEvening,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.tripStayPresenceDatesTitle,
          style: textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.tripStayMealsIncludedHint,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _BoundRow(
          label: l10n.tripStayFromLabel,
          dateLabel: _dateLabel(context, value.startDateKey),
          part: value.startDayPart,
          partLabelFor: (part) => _dayPartLabel(l10n, part),
          onPickDate: () => _pickDate(context, isStart: true),
          onPartChanged: (p) => onChanged(value.copyWith(startDayPart: p)),
        ),
        const SizedBox(height: 12),
        _BoundRow(
          label: l10n.tripStayToLabel,
          dateLabel: _dateLabel(context, value.endDateKey),
          part: value.endDayPart,
          partLabelFor: (part) => _dayPartLabel(l10n, part),
          onPickDate: () => _pickDate(context, isStart: false),
          onPartChanged: (p) => onChanged(value.copyWith(endDayPart: p)),
        ),
      ],
    );
  }
}

class _BoundRow extends StatelessWidget {
  const _BoundRow({
    required this.label,
    required this.dateLabel,
    required this.part,
    required this.partLabelFor,
    required this.onPickDate,
    required this.onPartChanged,
  });

  final String label;
  final String dateLabel;
  final TripDayPart part;
  final String Function(TripDayPart part) partLabelFor;
  final VoidCallback onPickDate;
  final ValueChanged<TripDayPart> onPartChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: OutlinedButton(
            onPressed: onPickDate,
            child: Text(dateLabel),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton<TripDayPart>(
            value: part,
            onChanged: (v) {
              if (v != null) onPartChanged(v);
            },
            items: TripDayPart.values
                .map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Text(partLabelFor(p)),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
