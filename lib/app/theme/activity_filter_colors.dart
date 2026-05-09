import 'package:flutter/material.dart';
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

extension ActivityFilterGroupColors on ActivityFilterGroup {
  Color get filterColor => switch (this) {
        ActivityFilterGroup.repas => const Color(0xFFF59E0B),
        ActivityFilterGroup.nuits => const Color(0xFF8B5CF6),
        ActivityFilterGroup.loisirs => const Color(0xFF10B981),
        ActivityFilterGroup.trajets => const Color(0xFF3B82F6),
      };

  Color get filterLightBgColor => switch (this) {
        ActivityFilterGroup.repas => const Color(0xFFFFF6E7),
        ActivityFilterGroup.nuits => const Color(0xFFF4EEFF),
        ActivityFilterGroup.loisirs => const Color(0xFFEAFBF4),
        ActivityFilterGroup.trajets => const Color(0xFFEEF5FF),
      };

  Color get filterBorderColor => switch (this) {
        ActivityFilterGroup.repas => const Color(0xFFF8D9A0),
        ActivityFilterGroup.nuits => const Color(0xFFDCCEFF),
        ActivityFilterGroup.loisirs => const Color(0xFFBCE8D8),
        ActivityFilterGroup.trajets => const Color(0xFFC9DEFF),
      };

  IconData get filterIcon => switch (this) {
        ActivityFilterGroup.repas => Icons.restaurant_outlined,
        ActivityFilterGroup.nuits => Icons.hotel_outlined,
        ActivityFilterGroup.loisirs => Icons.hiking_outlined,
        ActivityFilterGroup.trajets => Icons.directions_bus_outlined,
      };
}
