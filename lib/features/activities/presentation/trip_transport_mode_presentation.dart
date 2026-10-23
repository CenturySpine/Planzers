import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/l10n/app_localizations.dart';

extension TripTransportModePresentation on TripTransportMode {
  IconData get icon => switch (this) {
        TripTransportMode.walk => PhosphorIconsRegular.personSimpleWalk,
        TripTransportMode.bike => PhosphorIconsRegular.bicycle,
        TripTransportMode.car => PhosphorIconsRegular.car,
        TripTransportMode.bus => PhosphorIconsRegular.bus,
        TripTransportMode.train => PhosphorIconsRegular.train,
        TripTransportMode.plane => PhosphorIconsRegular.airplane,
        TripTransportMode.boat => PhosphorIconsRegular.boat,
        TripTransportMode.other => PhosphorIconsRegular.dotsThreeCircle,
      };

  String label(AppLocalizations l10n) => switch (this) {
        TripTransportMode.walk => l10n.activityTransportModeWalk,
        TripTransportMode.bike => l10n.activityTransportModeBike,
        TripTransportMode.car => l10n.activityTransportModeCar,
        TripTransportMode.bus => l10n.activityTransportModeBus,
        TripTransportMode.train => l10n.activityTransportModeTrain,
        TripTransportMode.plane => l10n.activityTransportModePlane,
        TripTransportMode.boat => l10n.activityTransportModeBoat,
        TripTransportMode.other => l10n.activityTransportModeOther,
      };
}

extension TripActivityIconPresentation on TripActivity {
  /// The transport mode's icon once chosen, else the category's.
  IconData get displayIcon => transportMode?.icon ?? category.categoryIcon;
}

/// One chip per transport mode; tapping the selected one clears it.
class TripTransportModeChips extends StatelessWidget {
  const TripTransportModeChips({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TripTransportMode? value;

  /// Null disables the chips.
  final ValueChanged<TripTransportMode?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in TripTransportMode.values)
          FilterChip(
            avatar: Icon(mode.icon, size: 18),
            label: Text(mode.label(l10n)),
            selected: value == mode,
            onSelected: onChanged == null
                ? null
                : (selected) => onChanged!(selected ? mode : null),
          ),
      ],
    );
  }
}
