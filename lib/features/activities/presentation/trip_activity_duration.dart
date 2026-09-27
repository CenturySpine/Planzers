import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// "2 h", "1 h 30", "45 min".
String formatTripActivityDuration(Duration duration, AppLocalizations l10n) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return l10n.activitiesDurationMinutes(minutes);
  if (minutes == 0) return l10n.activitiesDurationHours(hours);
  return l10n.activitiesDurationHoursMinutes(
    hours,
    minutes.toString().padLeft(2, '0'),
  );
}

/// End time of a planned activity, e.g. "12:00", or "08:00" with a day
/// offset of 1 when it ends the next day.
({String time, int dayOffset})? tripActivityEndTime(
  BuildContext context,
  TripActivity activity,
) {
  final start = activity.plannedAt?.toLocal();
  final end = activity.plannedEndAt?.toLocal();
  if (start == null || end == null) return null;
  final dayOffset = DateUtils.dateOnly(end)
      .difference(DateUtils.dateOnly(start))
      .inDays;
  return (
    time: DateFormat.Hm(Localizations.localeOf(context).toString()).format(end),
    dayOffset: dayOffset,
  );
}

/// Duration row for the planning section of an activity: shows the current
/// value and opens [showTripActivityDurationDialog] when [onChanged] is set.
class TripActivityDurationButton extends StatelessWidget {
  const TripActivityDurationButton({
    super.key,
    required this.category,
    required this.durationMinutes,
    required this.onChanged,
  });

  final TripActivityCategory category;

  /// Custom value; null means the category default.
  final int? durationMinutes;

  /// Receives the new custom value (null when back to the default).
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final effective = Duration(
      minutes: durationMinutes ?? category.defaultDurationMinutes,
    );
    final onChanged = this.onChanged;
    return TextButton.icon(
      onPressed: onChanged == null
          ? null
          : () async {
              final picked = await showTripActivityDurationDialog(
                context,
                category: category,
                initialMinutes: effective.inMinutes,
              );
              if (picked == null) return;
              onChanged(
                picked == category.defaultDurationMinutes ? null : picked,
              );
            },
      icon: const Icon(PhosphorIconsRegular.timer),
      label: Text(
        l10n.activitiesDurationValue(
          formatTripActivityDuration(effective, l10n),
        ),
      ),
    );
  }
}

/// Returns the chosen duration in minutes, or null when cancelled.
Future<int?> showTripActivityDurationDialog(
  BuildContext context, {
  required TripActivityCategory category,
  required int initialMinutes,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _DurationDialog(
      category: category,
      initialMinutes: initialMinutes,
    ),
  );
}

class _DurationDialog extends StatefulWidget {
  const _DurationDialog({required this.category, required this.initialMinutes});

  final TripActivityCategory category;
  final int initialMinutes;

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  static const _minuteStep = 5;

  late final TextEditingController _hoursController;
  late int _minutes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hoursController =
        TextEditingController(text: '${widget.initialMinutes ~/ 60}');
    final remainder = widget.initialMinutes.remainder(60);
    _minutes = remainder - remainder % _minuteStep;
  }

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  void _submit() {
    final hours = int.tryParse(_hoursController.text.trim()) ?? -1;
    final total = hours * 60 + _minutes;
    if (hours < 0 || total <= 0 || total > tripActivityMaxDurationMinutes) {
      setState(
        () => _error = AppLocalizations.of(context)!.activitiesDurationInvalid,
      );
      return;
    }
    Navigator.of(context).pop(total);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final defaultMinutes = widget.category.defaultDurationMinutes;
    return AlertDialog(
      title: Text(l10n.activitiesDuration),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _hoursController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.activitiesDurationHoursField,
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _minutes,
                  decoration: InputDecoration(
                    labelText: l10n.activitiesDurationMinutesField,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (var m = 0; m < 60; m += _minuteStep)
                      DropdownMenuItem(
                        value: m,
                        child: Text(m.toString().padLeft(2, '0')),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _minutes = value ?? 0;
                    _error = null;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(defaultMinutes),
              child: Text(
                l10n.activitiesDurationDefault(
                  formatTripActivityDuration(
                    Duration(minutes: defaultMinutes),
                    l10n,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
