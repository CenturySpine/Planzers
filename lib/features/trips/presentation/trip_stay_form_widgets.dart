import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/presentation/trip_date_range_picker_sheet.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Short weekday date label used on trip create / join stay forms.
String formatTripStayShortDate(BuildContext context, DateTime date) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat('EEE d MMM', locale).format(date);
}

TripDateRangePickerStyle neonTripDateRangePickerStyle() {
  return TripDateRangePickerStyle(
    primary: NeonPalette.primary,
    primarySoft: NeonPalette.primarySoft,
    primaryTint: NeonPalette.primaryTint,
    deep: NeonPalette.deep,
    onSurfaceVariant: NeonPalette.onSurfaceVariant,
    divider: NeonPalette.divider,
    outline: NeonPalette.outline,
    surface: NeonPalette.surface,
    textSecondary: NeonPalette.text700,
  );
}

class TripNeonPrefGroup extends StatelessWidget {
  const TripNeonPrefGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: NeonPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NeonPalette.divider),
          boxShadow: NeonPalette.elev1,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, thickness: 1, color: NeonPalette.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: children[i],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TripNeonSectionHeader extends StatelessWidget {
  const TripNeonSectionHeader({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: NeonPalette.primary),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: NeonPalette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class TripStayDateCard extends StatelessWidget {
  const TripStayDateCard({
    super.key,
    required this.kicker,
    required this.kickerIcon,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final String kicker;
  final IconData kickerIcon;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: NeonPalette.dateBorderSet,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(kickerIcon, size: 14, color: NeonPalette.primary),
                  const SizedBox(width: 5),
                  Text(
                    kicker,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: NeonPalette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: NeonPalette.deep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripMealBoundCard extends StatelessWidget {
  const TripMealBoundCard({
    super.key,
    required this.dayLabel,
    required this.dayIcon,
    required this.question,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.bordered = true,
  });

  final String dayLabel;
  final IconData dayIcon;
  final String question;
  final TripDayPart selected;
  final ValueChanged<TripDayPart>? onSelected;
  final bool enabled;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = <(TripDayPart, String, IconData, IconData)>[
      (
        TripDayPart.morning,
        l10n.tripCreateMealBreakfast,
        Icons.bakery_dining_outlined,
        Icons.bakery_dining,
      ),
      (
        TripDayPart.midday,
        l10n.tripCreateMealLunch,
        Icons.lunch_dining_outlined,
        Icons.lunch_dining,
      ),
      (
        TripDayPart.evening,
        l10n.tripCreateMealDinner,
        Icons.dinner_dining_outlined,
        Icons.dinner_dining,
      ),
    ];

    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(dayIcon, size: 16, color: NeonPalette.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                dayLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: NeonPalette.deep,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 2, bottom: 10),
          child: Text(
            question,
            style: const TextStyle(
              fontSize: 12,
              color: NeonPalette.onSurfaceVariant,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: NeonPalette.segmentTrack,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (final option in options) ...[
                  Expanded(
                    child: _MealSegmentOption(
                      label: option.$2,
                      outlinedIcon: option.$3,
                      filledIcon: option.$4,
                      selected: selected == option.$1,
                      enabled: enabled,
                      onTap: onSelected == null
                          ? null
                          : () => onSelected!(option.$1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    if (!bordered) {
      return inner;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: NeonPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NeonPalette.divider, width: 1.5),
        boxShadow: NeonPalette.elev1,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: inner,
      ),
    );
  }
}

class _MealSegmentOption extends StatelessWidget {
  const _MealSegmentOption({
    required this.label,
    required this.outlinedIcon,
    required this.filledIcon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData outlinedIcon;
  final IconData filledIcon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? NeonPalette.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? filledIcon : outlinedIcon,
                size: 18,
                color: selected
                    ? NeonPalette.primary
                    : NeonPalette.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.1,
                  color: selected
                      ? NeonPalette.primary
                      : NeonPalette.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripNeonSwitch extends StatelessWidget {
  const TripNeonSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: onChanged == null
                ? Color.lerp(NeonPalette.surface, NeonPalette.outline, 0.22)
                : (value ? NeonPalette.primary : NeonPalette.divider),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onChanged == null
                    ? Color.lerp(Colors.white, NeonPalette.outline, 0.30)
                    : Colors.white,
                boxShadow: onChanged == null
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
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

class TripNeonOptCard extends StatelessWidget {
  const TripNeonOptCard({
    super.key,
    required this.child,
    this.disabled = false,
  });

  final Widget child;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: disabled
              ? Color.lerp(NeonPalette.surface, NeonPalette.outline, 0.06)
              : NeonPalette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NeonPalette.divider),
          boxShadow: disabled ? null : NeonPalette.elev1,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: child,
        ),
      ),
    );
  }
}
