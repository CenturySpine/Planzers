import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_create_form.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripActivityCreatePage extends StatelessWidget {
  const TripActivityCreatePage({
    super.key,
    required this.tripId,
    this.allowedCategories,
    this.initialLocation,
    this.initialAddress = '',
    this.initialPlannedDay,
  });

  final String tripId;

  /// When set, restricts the category picker to these categories and pre-selects the first one.
  final List<TripActivityCategory>? allowedCategories;

  /// Place picked on the trip map, with its address when found.
  final GeoPoint? initialLocation;
  final String initialAddress;

  /// Day the date picker opens on.
  final DateTime? initialPlannedDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.activitiesNewActivity),
      ),
      body: TripActivityCreateForm(
        tripId: tripId,
        allowedCategories: allowedCategories,
        initialLocation: initialLocation,
        initialAddress: initialAddress,
        initialPlannedDay: initialPlannedDay,
        // The new activity id is handed back to whoever opened the page
        // (e.g. a meal choosing the restaurant it creates).
        onCreated: (activityId) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.activitiesAdded)),
          );
          context.pop(activityId);
        },
      ),
    );
  }
}
