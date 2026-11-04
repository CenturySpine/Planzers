import 'package:flutter/widgets.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/carpool/data/trip_carpool.dart';
import 'package:planerz/l10n/app_localizations.dart';

String tripCarpoolDirectionLabel(
  AppLocalizations l10n,
  TripCarpoolDirection direction,
) {
  return switch (direction) {
    TripCarpoolDirection.outbound => l10n.tripCarpoolDirectionOutbound,
    TripCarpoolDirection.returnTrip => l10n.tripCarpoolDirectionReturn,
  };
}

IconData tripCarpoolDirectionIcon(TripCarpoolDirection direction) {
  return switch (direction) {
    TripCarpoolDirection.outbound => PhosphorIconsRegular.arrowRight,
    TripCarpoolDirection.returnTrip => PhosphorIconsRegular.arrowLeft,
  };
}
