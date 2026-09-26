import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';

/// Filter groups for the Planning screen — palette-independent, always applied
/// regardless of which brand palette the user has selected.
enum ActivityFilterGroup { repas, nuits, loisirs, trajets }

extension TripActivityCategoryFilterGroup on TripActivityCategory {
  ActivityFilterGroup get filterGroup => switch (this) {
        TripActivityCategory.restaurant => ActivityFilterGroup.repas,
        TripActivityCategory.accommodation => ActivityFilterGroup.nuits,
        TripActivityCategory.transport => ActivityFilterGroup.trajets,
        _ => ActivityFilterGroup.loisirs,
      };
}

/// Business category hues (Riviera). Each hue exists in three steps:
/// - `filterColor`: the vivid hue (icons, dots, bands, selected chips);
/// - `filterLightBgColor`: a soft tint for icon tiles and pills;
/// - `filterInkColor`: a darker step readable as text on white / tint.
extension ActivityFilterGroupColors on ActivityFilterGroup {
  Color get filterColor => switch (this) {
        ActivityFilterGroup.repas => const Color(0xFFF2891F),
        ActivityFilterGroup.nuits => const Color(0xFF5B5BD6),
        ActivityFilterGroup.loisirs => const Color(0xFFDB3F76),
        ActivityFilterGroup.trajets => const Color(0xFF1F84D6),
      };

  Color get filterLightBgColor => switch (this) {
        ActivityFilterGroup.repas => const Color(0xFFFFF1E2),
        ActivityFilterGroup.nuits => const Color(0xFFECECFB),
        ActivityFilterGroup.loisirs => const Color(0xFFFCE8EF),
        ActivityFilterGroup.trajets => const Color(0xFFE4F1FC),
      };

  Color get filterBorderColor => switch (this) {
        ActivityFilterGroup.repas => const Color(0xFFF9CFA3),
        ActivityFilterGroup.nuits => const Color(0xFFC9C9F3),
        ActivityFilterGroup.loisirs => const Color(0xFFF3BCD0),
        ActivityFilterGroup.trajets => const Color(0xFFB7D8F4),
      };

  Color get filterInkColor => switch (this) {
        ActivityFilterGroup.repas => const Color(0xFFA35200),
        ActivityFilterGroup.nuits => const Color(0xFF4343B8),
        ActivityFilterGroup.loisirs => const Color(0xFFB42A5C),
        ActivityFilterGroup.trajets => const Color(0xFF1667A8),
      };

  IconData get filterIcon => switch (this) {
        ActivityFilterGroup.repas => Icons.restaurant_rounded,
        ActivityFilterGroup.nuits => Icons.bedtime_rounded,
        ActivityFilterGroup.loisirs => Icons.local_activity_rounded,
        ActivityFilterGroup.trajets => Icons.commute_rounded,
      };
}

/// "Présence" pseudo-category (participants on site) — uses the Lagon chrome
/// hue, since it is about people rather than an activity type.
abstract final class PresenceCategoryColors {
  static const Color color = AppTokens.primary;
  static const Color lightBg = AppTokens.primaryTint;
  static const Color ink = AppTokens.primaryDark;
  static const IconData icon = Icons.groups_rounded;
}
