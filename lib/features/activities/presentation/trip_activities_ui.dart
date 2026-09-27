import 'package:planerz/app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/presentation/trip_activity_list_helpers.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Compact list density.
const double tripActivitiesCardGap = 8;
const double tripActivitiesCardPaddingY = 10;

/// Category filter chips — Repas / Nuits / Loisirs / Trajets + Présences
/// (disabled), as a single compact scrollable row.
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
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        children: [
          for (final group in _chipGroups) ...[
            TripCategoryFilterChip(
              label: filterLabels[group]!,
              icon: group.filterIcon,
              color: group.filterColor,
              lightBg: group.filterLightBgColor,
              ink: group.filterInkColor,
              selected: activeFilters.contains(group),
              onToggle: () => onToggle(group),
            ),
            const SizedBox(width: 6),
          ],
          TripCategoryFilterChip(
            label: l10n.activitiesFilterPresences,
            icon: PresenceCategoryColors.icon,
            color: PresenceCategoryColors.color,
            lightBg: PresenceCategoryColors.lightBg,
            ink: PresenceCategoryColors.ink,
            selected: false,
            disabled: true,
            disabledTooltip: l10n.commonComingSoon,
            onToggle: () {},
          ),
        ],
      ),
    );
  }
}

/// Standard category chip: icon in the category hue + label. Selected state
/// fills the chip with the category tint and border.
class TripCategoryFilterChip extends StatelessWidget {
  const TripCategoryFilterChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.lightBg,
    required this.ink,
    required this.selected,
    required this.onToggle,
    this.disabled = false,
    this.disabledTooltip,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color lightBg;
  final Color ink;
  final bool selected;
  final VoidCallback onToggle;
  final bool disabled;
  final String? disabledTooltip;

  @override
  Widget build(BuildContext context) {
    Widget chip = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? lightBg : AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(
          color: selected ? color : AppTokens.divider,
          width: selected ? 1.4 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? ink : AppTokens.deep,
            ),
          ),
        ],
      ),
    );

    if (disabled) {
      chip = Opacity(opacity: 0.45, child: chip);
    }

    return Tooltip(
      message: disabled ? (disabledTooltip ?? '') : '',
      child: Semantics(
        button: true,
        selected: selected,
        enabled: !disabled,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          onTap: disabled ? null : onToggle,
          child: chip,
        ),
      ),
    );
  }
}

/// Planning view switcher — the standard app [TabBar] (same look as every
/// other tabbed screen).
class TripActivitiesSegmentedTabBar extends StatelessWidget {
  const TripActivitiesSegmentedTabBar({
    super.key,
    required this.labels,
  });

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTokens.surface,
      child: TabBar(
        tabs: [for (final label in labels) Tab(height: 42, text: label)],
      ),
    );
  }
}

/// Agenda day selector: one week of day pills, with one colored dot per
/// category planned on that day.
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
    this.dayGroups = const {},
  });

  final List<DateTime> weekDays;
  final DateTime selectedDay;
  final Set<DateTime> plannedDays;
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;
  final ValueChanged<DateTime> onSelectDay;
  final VoidCallback onMoveBackward;
  final VoidCallback onMoveForward;

  /// Categories planned per day (date-only keys), used for the colored dots.
  final Map<DateTime, Set<ActivityFilterGroup>> dayGroups;

  static const _chevronSlotWidth = 32.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeTag = Localizations.localeOf(context).toString();
    final today = tripActivityDateOnly(DateTime.now());
    return Container(
      color: AppTokens.surface,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          SizedBox(
            width: _chevronSlotWidth,
            child: IconButton(
              onPressed: onMoveBackward,
              icon: const Icon(PhosphorIconsRegular.caretLeft, size: 22),
              tooltip: l10n.activitiesPreviousWeek,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: _chevronSlotWidth,
                height: 48,
              ),
              color: AppTokens.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (final day in weekDays)
                  Expanded(
                    child: _AgendaDayPill(
                      weekdayLabel: DateFormat('EEE', localeTag)
                          .format(day)
                          .replaceAll('.', '')
                          .toUpperCase(),
                      dayNumber: DateFormat('d').format(day),
                      isSelected: tripActivitiesSameDay(day, selectedDay),
                      isToday: tripActivitiesSameDay(day, today),
                      isOutsideTrip:
                          _isDayOutsideTrip(day, tripStartDate, tripEndDate),
                      groups: dayGroups[day] ??
                          (plannedDays.contains(day)
                              ? const {ActivityFilterGroup.loisirs}
                              : const {}),
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
              icon: const Icon(PhosphorIconsRegular.caretRight, size: 22),
              tooltip: l10n.activitiesNextWeek,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: _chevronSlotWidth,
                height: 48,
              ),
              color: AppTokens.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaDayPill extends StatelessWidget {
  const _AgendaDayPill({
    required this.weekdayLabel,
    required this.dayNumber,
    required this.isSelected,
    required this.isToday,
    required this.isOutsideTrip,
    required this.groups,
    required this.onTap,
  });

  final String weekdayLabel;
  final String dayNumber;
  final bool isSelected;
  final bool isToday;
  final bool isOutsideTrip;
  final Set<ActivityFilterGroup> groups;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? Colors.white : AppTokens.deep;
    final muted =
        isSelected ? Colors.white.withValues(alpha: 0.85) : AppTokens.outline;
    final orderedGroups = ActivityFilterGroup.values
        .where(groups.contains)
        .toList(growable: false);

    return Opacity(
      opacity: isOutsideTrip ? 0.35 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: isSelected ? AppTokens.primary : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            side: isToday && !isSelected
                ? const BorderSide(color: AppTokens.accent, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            onTap: isOutsideTrip ? null : onTap,
            child: SizedBox(
              height: 58,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekdayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dayNumber,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: fg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 5,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final g in orderedGroups)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : g.filterColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
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

/// Day header for the agenda (selected day) and the planned list.
class TripActivityDaySeparatorRail extends StatelessWidget {
  const TripActivityDaySeparatorRail({
    super.key,
    required this.label,
    this.trailing,
  });

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final text = label.isEmpty
        ? label
        : '${label[0].toUpperCase()}${label.substring(1)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTokens.deep,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTokens.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Timeline row for the agenda: time gutter (start at the top, optional end
/// at the bottom), a node in the category hue on a vertical rail, then the
/// card.
class TripAgendaTimelineRow extends StatelessWidget {
  const TripAgendaTimelineRow({
    super.key,
    required this.timeLabel,
    required this.color,
    required this.child,
    this.endTimeLabel,
    this.endDayOffset = 0,
    this.isFirst = false,
    this.isLast = false,
  });

  final String timeLabel;
  final Color color;
  final Widget child;

  /// End time, shown lighter under the start time.
  final String? endTimeLabel;

  /// Days between start and end (e.g. 1 for a night), shown as "+1".
  final int endDayOffset;
  final bool isFirst;
  final bool isLast;

  static const _timeStyle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    color: AppTokens.deep,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Lines the end marker up with the end time label.
  static const double _endMarkerBottom = tripActivitiesCardGap + 13;

  @override
  Widget build(BuildContext context) {
    final endTimeLabel = this.endTimeLabel;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    timeLabel,
                    textAlign: TextAlign.right,
                    style: _timeStyle,
                  ),
                ),
                if (endTimeLabel != null) ...[
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: tripActivitiesCardGap + 10,
                    ),
                    child: Text.rich(
                      TextSpan(
                        text: endTimeLabel,
                        children: [
                          if (endDayOffset > 0)
                            TextSpan(
                              text: AppLocalizations.of(context)!
                                  .activitiesEndDayOffset(endDayOffset),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: _timeStyle.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 22,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: isFirst ? 18 : 0,
                  bottom: !isLast
                      ? 0
                      : endTimeLabel != null
                          ? _endMarkerBottom + 4
                          : null,
                  height: isLast && endTimeLabel == null ? 18 : null,
                  child: Container(width: 2, color: AppTokens.divider),
                ),
                if (endTimeLabel != null)
                  Positioned(
                    bottom: _endMarkerBottom,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppTokens.scaffoldBackground,
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                      ),
                    ),
                  ),
                Positioned(
                  top: 13,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTokens.scaffoldBackground,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: tripActivitiesCardGap),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared card shell for planning list items (activities and meals).
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

  /// Kept for API compatibility; the Riviera card encodes the category with
  /// the icon tile only.
  final bool showCategoryBand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg - 2),
        side: const BorderSide(color: AppTokens.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              10, tripActivitiesCardPaddingY, 10, tripActivitiesCardPaddingY),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: categoryLightBg,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                alignment: Alignment.center,
                child: Icon(leadingIcon, size: 19, color: categoryColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                      style: const TextStyle(fontSize: 14),
                      child: titleRow,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: subtitleItalic
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: AppTokens.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
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
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: categoryLightBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsFill.user, size: 14, color: categoryInk),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: categoryInk,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Search field for list tabs — the standard themed text field.
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
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.activitiesSearchHint,
            prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(PhosphorIconsRegular.x, size: 18),
                    tooltip: l10n.nameSearchClear,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        );
      },
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
      color: AppTokens.surfaceMuted,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        onTap: onTap,
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            PhosphorIconsRegular.link,
            size: 18,
            color: AppTokens.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
