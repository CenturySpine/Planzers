import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Compact list density (handoff default).
const double tripActivitiesCardGap = 10;
const double tripActivitiesCardPaddingY = 11;

const _presencesColor = Color(0xFFEC4899);

/// Category filter chips — Repas / Nuits / Loisirs / Trajets + Présences (disabled).
class TripActivitiesFilterChips extends StatelessWidget {
  const TripActivitiesFilterChips({
    super.key,
    required this.activeFilters,
    required this.filterLabels,
    required this.onToggle,
  });

  final Set<ActivityFilterGroup> activeFilters;
  final Map<ActivityFilterGroup, String> filterLabels;
  final ValueChanged<ActivityFilterGroup> onToggle;

  static const _chipGroups = ActivityFilterGroup.values;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < _chipGroups.length; i++) ...[
            Expanded(
              child: _ActivityFilterChip(
                label: filterLabels[_chipGroups[i]]!,
                icon: _chipGroups[i].filterIcon,
                color: _chipGroups[i].filterColor,
                selected: activeFilters.contains(_chipGroups[i]),
                onToggle: () => onToggle(_chipGroups[i]),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: _ActivityFilterChip(
              label: l10n.activitiesFilterPresences,
              icon: Icons.groups_outlined,
              color: _presencesColor,
              selected: false,
              disabled: true,
              disabledTooltip: l10n.commonComingSoon,
              onToggle: () {},
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityFilterChip extends StatelessWidget {
  const _ActivityFilterChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onToggle,
    this.disabled = false,
    this.disabledTooltip,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onToggle;
  final bool disabled;
  final String? disabledTooltip;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color : NeonPalette.surface;
    final iconColor = selected ? Colors.white : color;
    final labelColor = selected ? Colors.white : NeonPalette.deep;

    Widget chip = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: selected
            ? null
            : Border.all(color: NeonPalette.divider),
        boxShadow: selected ? null : NeonPalette.elev1,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 23, color: iconColor),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ],
      ),
    );

    if (disabled) {
      chip = Opacity(opacity: 0.4, child: chip);
    }

    return Tooltip(
      message: disabled ? (disabledTooltip ?? '') : '',
      child: GestureDetector(
        onTap: disabled ? null : onToggle,
        child: chip,
      ),
    );
  }
}

/// Segmented control for Suggestions / Planifiées / Agenda tabs.
class TripActivitiesSegmentedTabBar extends StatelessWidget {
  const TripActivitiesSegmentedTabBar({
    super.key,
    required this.labels,
  });

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: NeonPalette.surfaceHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return Row(
                children: [
                  for (var index = 0; index < labels.length; index++)
                    Expanded(
                      child: _SegmentTab(
                        label: labels[index],
                        selected: controller.index == index,
                        onTap: () => controller.animateTo(index),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? NeonPalette.surface : Colors.transparent,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: NeonPalette.elev1,
                )
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? NeonPalette.deep : NeonPalette.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Agenda day selector — Alt 1 grouped card with month row + underline days.
class TripActivitiesAgendaWeekStrip extends StatelessWidget {
  const TripActivitiesAgendaWeekStrip({
    super.key,
    required this.weekDays,
    required this.selectedDay,
    required this.plannedDays,
    required this.tripStartDate,
    required this.tripEndDate,
    required this.onSelectDay,
    required this.onMoveBackward,
    required this.onMoveForward,
  });

  final List<DateTime> weekDays;
  final DateTime selectedDay;
  final Set<DateTime> plannedDays;
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;
  final ValueChanged<DateTime> onSelectDay;
  final VoidCallback onMoveBackward;
  final VoidCallback onMoveForward;

  static const _chevronSlotWidth = 30.0;

  @override
  Widget build(BuildContext context) {
    final localeTag = Localizations.localeOf(context).toString();
    final monthSpans = _agendaMonthSpans(weekDays, localeTag: localeTag);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: NeonPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NeonPalette.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: _chevronSlotWidth),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < monthSpans.length; i++)
                          Expanded(
                            flex: monthSpans[i].dayCount,
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: i < monthSpans.length - 1
                                    ? const Border(
                                        right: BorderSide(
                                          color: NeonPalette.divider,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Text(
                                monthSpans[i].monthLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: NeonPalette.deep,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: _chevronSlotWidth),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: _chevronSlotWidth,
                    child: IconButton(
                      onPressed: onMoveBackward,
                      icon: const Icon(Icons.chevron_left, size: 19),
                      tooltip:
                          AppLocalizations.of(context)!.activitiesPreviousWeek,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: _chevronSlotWidth,
                        height: _chevronSlotWidth,
                      ),
                      visualDensity: VisualDensity.compact,
                      color: NeonPalette.onSurfaceVariant,
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        for (final day in weekDays)
                          Expanded(
                            child: _AgendaUnderlineDayCell(
                              day: day,
                              isSelected:
                                  tripActivitiesSameDay(day, selectedDay),
                              isToday: tripActivitiesSameDay(
                                day,
                                tripActivityDateOnly(DateTime.now()),
                              ),
                              isOutsideTrip: _isDayOutsideTrip(
                                day,
                                tripStartDate,
                                tripEndDate,
                              ),
                              hasPlannedActivities: plannedDays.contains(day),
                              onTap: () => onSelectDay(day),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: _chevronSlotWidth,
                    child: IconButton(
                      onPressed: onMoveForward,
                      icon: const Icon(Icons.chevron_right, size: 19),
                      tooltip:
                          AppLocalizations.of(context)!.activitiesNextWeek,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: _chevronSlotWidth,
                        height: _chevronSlotWidth,
                      ),
                      visualDensity: VisualDensity.compact,
                      color: NeonPalette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgendaUnderlineDayCell extends StatelessWidget {
  const _AgendaUnderlineDayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.isOutsideTrip,
    required this.hasPlannedActivities,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final bool isOutsideTrip;
  final bool hasPlannedActivities;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localeTag = Localizations.localeOf(context).toString();
    final weekdayLabel =
        DateFormat('EEE', localeTag).format(day).toUpperCase();
    final borderColor = isSelected
        ? NeonPalette.primary
        : isToday
            ? NeonPalette.outline
            : NeonPalette.divider;
    final textColor = isSelected ? NeonPalette.primary : NeonPalette.deep;
    final weekdayColor =
        isSelected ? NeonPalette.primary : NeonPalette.onSurfaceVariant;
    final dotColor = isSelected
        ? NeonPalette.primary
        : hasPlannedActivities
            ? NeonPalette.secondary
            : Colors.transparent;

    return Opacity(
      opacity: isOutsideTrip ? 0.4 : 1,
      child: GestureDetector(
        onTap: isOutsideTrip ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderColor, width: 2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    weekdayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: weekdayColor,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    DateFormat('d').format(day),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgendaMonthSpan {
  const _AgendaMonthSpan({required this.monthLabel, required this.dayCount});

  final String monthLabel;
  final int dayCount;
}

List<_AgendaMonthSpan> _agendaMonthSpans(
  List<DateTime> weekDays, {
  required String localeTag,
}) {
  final spans = <_AgendaMonthSpan>[];
  for (final day in weekDays) {
    final label = _agendaMonthLabel(day, localeTag);
    if (spans.isEmpty || spans.last.monthLabel != label) {
      spans.add(_AgendaMonthSpan(monthLabel: label, dayCount: 1));
    } else {
      final previous = spans.removeLast();
      spans.add(
        _AgendaMonthSpan(
          monthLabel: previous.monthLabel,
          dayCount: previous.dayCount + 1,
        ),
      );
    }
  }
  return spans;
}

String _agendaMonthLabel(DateTime day, String localeTag) {
  final raw = DateFormat('MMMM', localeTag).format(day);
  if (raw.isEmpty) return raw;
  return '${raw[0].toUpperCase()}${raw.substring(1)}';
}

bool _isDayOutsideTrip(
  DateTime day,
  DateTime? tripStartDate,
  DateTime? tripEndDate,
) {
  final normalizedDay = tripActivityDateOnly(day);
  final start =
      tripStartDate == null ? null : tripActivityDateOnly(tripStartDate);
  final end = tripEndDate == null ? null : tripActivityDateOnly(tripEndDate);
  if (start != null && normalizedDay.isBefore(start)) return true;
  if (end != null && normalizedDay.isAfter(end)) return true;
  return false;
}

/// Day separator rail for the Planifiées tab.
class TripActivityDaySeparatorRail extends StatelessWidget {
  const TripActivityDaySeparatorRail({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: NeonPalette.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: NeonPalette.divider, height: 1)),
        ],
      ),
    );
  }
}

/// Shared Direction A card shell for planning list items.
class TripPlanningListCardShell extends StatelessWidget {
  const TripPlanningListCardShell({
    super.key,
    required this.categoryColor,
    required this.categoryLightBg,
    required this.leadingIcon,
    required this.titleRow,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.subtitleItalic = false,
    this.showCategoryBand = true,
  });

  final Color categoryColor;
  final Color categoryLightBg;
  final IconData leadingIcon;
  final Widget titleRow;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool subtitleItalic;
  final bool showCategoryBand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.surface,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: NeonPalette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: showCategoryBand
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: categoryColor, width: 4),
                  ),
                )
              : const BoxDecoration(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, tripActivitiesCardPaddingY,
                14, tripActivitiesCardPaddingY),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: categoryLightBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(leadingIcon, size: 22, color: categoryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleRow,
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: subtitleItalic
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: NeonPalette.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Participant count pill for meal cards.
class TripPlanningParticipantCountPill extends StatelessWidget {
  const TripPlanningParticipantCountPill({
    super.key,
    required this.count,
    required this.categoryLightBg,
    required this.categoryInk,
  });

  final int count;
  final Color categoryLightBg;
  final Color categoryInk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: categoryLightBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 16, color: categoryInk),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: categoryInk,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Search field for Suggestions / Planifiées tabs (handoff `.pl-search`).
class TripActivitiesSearchField extends StatelessWidget {
  const TripActivitiesSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      textField: true,
      label: l10n.activitiesSearchHint,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: NeonPalette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NeonPalette.divider),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: 20,
                  color: NeonPalette.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      fontSize: 15,
                      color: NeonPalette.deep,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.activitiesSearchHint,
                      hintStyle: const TextStyle(
                        fontSize: 15,
                        color: NeonPalette.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    tooltip: l10n.nameSearchClear,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    color: NeonPalette.onSurfaceVariant,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Link icon button trailing slot when an item has a link but no image.
class TripPlanningLinkTrailingButton extends StatelessWidget {
  const TripPlanningLinkTrailingButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.surfaceHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.link,
            size: 20,
            color: NeonPalette.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
