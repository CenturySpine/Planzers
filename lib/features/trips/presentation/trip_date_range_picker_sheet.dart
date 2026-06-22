import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Visual tokens for [showTripDateRangePickerSheet] — decoupled from any app palette.
@immutable
class TripDateRangePickerStyle {
  const TripDateRangePickerStyle({
    required this.primary,
    required this.primarySoft,
    required this.primaryTint,
    required this.deep,
    required this.onSurfaceVariant,
    required this.divider,
    required this.outline,
    required this.surface,
    required this.textSecondary,
  });

  final Color primary;
  final Color primarySoft;
  final Color primaryTint;
  final Color deep;
  final Color onSurfaceVariant;
  final Color divider;
  final Color outline;
  final Color surface;
  final Color textSecondary;
}

/// Result of the trip date range bottom sheet.
@immutable
class TripDateRangePickerResult {
  const TripDateRangePickerResult({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;
}

/// Bottom-sheet calendar for a single day or an inclusive date range (Mon-first week).
Future<TripDateRangePickerResult?> showTripDateRangePickerSheet({
  required BuildContext context,
  required TripDateRangePickerStyle style,
  required DateTime initialStart,
  DateTime? initialEnd,
  bool single = false,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final now = DateTime.now();
  final low = firstDate ?? DateTime(now.year - 1);
  final high = lastDate ?? DateTime(now.year + 2, 12, 31);

  return showModalBottomSheet<TripDateRangePickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    builder: (sheetContext) => _TripDateRangePickerSheet(
      style: style,
      initialStart: DateUtils.dateOnly(initialStart),
      initialEnd: initialEnd != null ? DateUtils.dateOnly(initialEnd) : null,
      single: single,
      firstDate: DateUtils.dateOnly(low),
      lastDate: DateUtils.dateOnly(high),
    ),
  );
}

class _TripDateRangePickerSheet extends StatefulWidget {
  const _TripDateRangePickerSheet({
    required this.style,
    required this.initialStart,
    required this.initialEnd,
    required this.single,
    required this.firstDate,
    required this.lastDate,
  });

  final TripDateRangePickerStyle style;
  final DateTime initialStart;
  final DateTime? initialEnd;
  final bool single;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_TripDateRangePickerSheet> createState() =>
      _TripDateRangePickerSheetState();
}

class _TripDateRangePickerSheetState extends State<_TripDateRangePickerSheet> {
  late DateTime _visibleMonth;
  late DateTime? _start;
  late DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.single
        ? widget.initialStart
        : (widget.initialEnd ?? widget.initialStart);
    _visibleMonth = DateTime(_start!.year, _start!.month);
  }

  void _pickDay(DateTime day) {
    setState(() {
      if (widget.single) {
        _start = day;
        _end = day;
        return;
      }
      if (_start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _start = day;
      } else if (DateUtils.isSameDay(day, _start!)) {
        _end = day;
      } else {
        _end = day;
      }
    });
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  bool _isDayDisabled(DateTime day) {
    return day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate);
  }

  int _nightCount() {
    if (_start == null || _end == null) return 0;
    return _end!.difference(_start!).inDays;
  }

  String _shortDateLabel(BuildContext context, DateTime? date) {
    if (date == null) return '—';
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('EEE d MMM', locale).format(date);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final style = widget.style;
    final monthLabel =
        DateFormat.yMMMM(Localizations.localeOf(context).toString())
            .format(_visibleMonth);
    final weekdayHeaders = _weekdayHeaders(context);
    final cells = _buildMonthCells(_visibleMonth);
    final canSave = widget.single
        ? _start != null
        : _start != null && _end != null;

    return SafeArea(
      top: false,
      child: Material(
        color: style.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.single
                          ? l10n.tripDatePickerSingleKicker
                          : l10n.tripDatePickerRangeKicker,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: style.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (widget.single)
                      Text(
                        _shortDateLabel(context, _start),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: _start != null ? style.deep : style.outline,
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _shortDateLabel(context, _start),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color:
                                    _start != null ? style.deep : style.outline,
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_forward, size: 18, color: style.outline),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _shortDateLabel(context, _end),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: _end != null ? style.deep : style.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: style.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                child: Row(
                  children: [
                    _MonthNavButton(
                      icon: Icons.chevron_left,
                      color: style.textSecondary,
                      hoverColor: style.primaryTint,
                      onPressed: () => _shiftMonth(-1),
                    ),
                    Expanded(
                      child: Text(
                        monthLabel[0].toUpperCase() + monthLabel.substring(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: style.deep,
                        ),
                      ),
                    ),
                    _MonthNavButton(
                      icon: Icons.chevron_right,
                      color: style.textSecondary,
                      hoverColor: style.primaryTint,
                      onPressed: () => _shiftMonth(1),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    for (final label in weekdayHeaders)
                      Expanded(
                        child: SizedBox(
                          height: 28,
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: style.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 44,
                  ),
                  itemCount: cells.length,
                  itemBuilder: (context, index) {
                    final cell = cells[index];
                    if (cell == null) {
                      return const SizedBox.shrink();
                    }
                    return _CalendarDayCell(
                      day: cell,
                      style: style,
                      disabled: _isDayDisabled(cell),
                      rangeStart: _start,
                      rangeEnd: _end,
                      single: widget.single,
                      onTap: () {
                        if (!_isDayDisabled(cell)) _pickDay(cell);
                      },
                    );
                  },
                ),
              ),
              Divider(height: 1, color: style.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.single
                            ? l10n.tripDatePickerSingleSummary
                            : _end != null
                                ? l10n.tripCreateNightsDays(
                                    _nightCount(),
                                    _nightCount() + 1,
                                  )
                                : l10n.tripDatePickerChooseEnd,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: style.primary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        l10n.commonCancel,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: style.textSecondary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: canSave
                          ? () {
                              Navigator.of(context).pop(
                                TripDateRangePickerResult(
                                  start: _start!,
                                  end: widget.single ? _start! : _end!,
                                ),
                              );
                            }
                          : null,
                      child: Text(
                        l10n.commonSave,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: canSave ? style.primary : style.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _weekdayHeaders(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final format = DateFormat.E(locale);
    final monday = DateTime(2024, 1, 1);
    return List.generate(7, (index) {
      final label = format.format(monday.add(Duration(days: index)));
      if (label.isEmpty) return label;
      return label[0].toUpperCase();
    });
  }

  List<DateTime?> _buildMonthCells(DateTime month) {
    const firstDayOfWeek = DateTime.monday;
    final firstOfMonth = DateTime(month.year, month.month);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    var leading = (firstOfMonth.weekday - firstDayOfWeek) % 7;
    if (leading < 0) leading += 7;

    final cells = <DateTime?>[for (var i = 0; i < leading; i++) null];
    for (var day = 1; day <= daysInMonth; day++) {
      cells.add(DateTime(month.year, month.month, day));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }
}

class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({
    required this.icon,
    required this.color,
    required this.hoverColor,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final Color hoverColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 22, color: color),
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.style,
    required this.disabled,
    required this.rangeStart,
    required this.rangeEnd,
    required this.single,
    required this.onTap,
  });

  final DateTime day;
  final TripDateRangePickerStyle style;
  final bool disabled;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final bool single;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isEndpoint = _isEndpoint();
    final inRange = _isInRange();
    final isStartHalf = _isRangeStartHalf();
    final isEndHalf = _isRangeEndHalf();

    return Stack(
      alignment: Alignment.center,
      children: [
        if (!single && inRange)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: style.primarySoft),
            ),
          ),
        if (!single && isStartHalf)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, style.primarySoft],
                  stops: const [0.5, 0.5],
                ),
              ),
            ),
          ),
        if (!single && isEndHalf)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [style.primarySoft, Colors.transparent],
                  stops: const [0.5, 0.5],
                ),
              ),
            ),
          ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: disabled ? null : onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isEndpoint ? style.primary : Colors.transparent,
                  ),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              isEndpoint ? FontWeight.w600 : FontWeight.w500,
                          color: disabled
                              ? style.outline.withValues(alpha: 0.5)
                              : isEndpoint
                                  ? Colors.white
                                  : style.deep,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _isEndpoint() {
    if (single) {
      return rangeStart != null && DateUtils.isSameDay(day, rangeStart!);
    }
    if (rangeStart != null && DateUtils.isSameDay(day, rangeStart!)) {
      return true;
    }
    if (rangeEnd != null && DateUtils.isSameDay(day, rangeEnd!)) {
      return true;
    }
    return false;
  }

  bool _isInRange() {
    if (single || rangeStart == null || rangeEnd == null) return false;
    return day.isAfter(rangeStart!) &&
        day.isBefore(rangeEnd!) &&
        !DateUtils.isSameDay(day, rangeStart!) &&
        !DateUtils.isSameDay(day, rangeEnd!);
  }

  bool _isRangeStartHalf() {
    if (single || rangeStart == null || rangeEnd == null) return false;
    if (rangeEnd!.isAtSameMomentAs(rangeStart!)) return false;
    return DateUtils.isSameDay(day, rangeStart!) && !DateUtils.isSameDay(day, rangeEnd!);
  }

  bool _isRangeEndHalf() {
    if (single || rangeStart == null || rangeEnd == null) return false;
    if (rangeEnd!.isAtSameMomentAs(rangeStart!)) return false;
    return DateUtils.isSameDay(day, rangeEnd!) && !DateUtils.isSameDay(day, rangeStart!);
  }
}
