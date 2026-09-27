import 'package:flutter/widgets.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Fixed list of personal document categories; drives the icon shown in the
/// wallet list. Stored in Firestore by [name] (must match `firestore.rules`).
enum WalletDocumentCategory {
  plane,
  train,
  bus,
  boat,
  lodging,
  vehicleRental,
  activity,
  identity,
  insurance,
  other;

  static WalletDocumentCategory fromFirestore(Object? raw) {
    for (final category in values) {
      if (category.name == raw) return category;
    }
    return other;
  }

  IconData get icon => switch (this) {
        plane => PhosphorIconsRegular.airplane,
        train => PhosphorIconsRegular.train,
        bus => PhosphorIconsRegular.bus,
        boat => PhosphorIconsRegular.boat,
        lodging => PhosphorIconsRegular.bed,
        vehicleRental => PhosphorIconsRegular.car,
        activity => PhosphorIconsRegular.ticket,
        identity => PhosphorIconsRegular.identificationCard,
        insurance => PhosphorIconsRegular.firstAidKit,
        other => PhosphorIconsRegular.clipboardText,
      };

  String label(AppLocalizations l10n) => switch (this) {
        plane => l10n.walletCategoryPlane,
        train => l10n.walletCategoryTrain,
        bus => l10n.walletCategoryBus,
        boat => l10n.walletCategoryBoat,
        lodging => l10n.walletCategoryLodging,
        vehicleRental => l10n.walletCategoryVehicleRental,
        activity => l10n.walletCategoryActivity,
        identity => l10n.walletCategoryIdentity,
        insurance => l10n.walletCategoryInsurance,
        other => l10n.walletCategoryOther,
      };
}
