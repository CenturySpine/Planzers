import 'package:flutter/material.dart';
import 'package:planerz/features/trips/data/trip.dart';

/// Provides the live [Trip] for the current trip hub (shell + tab pages).
class TripScope extends InheritedWidget {
  const TripScope({
    super.key,
    required this.trip,
    required super.child,
  });

  final Trip trip;

  static Trip of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TripScope>();
    assert(scope != null, 'TripScope not found');
    return scope!.trip;
  }

  @override
  bool updateShouldNotify(TripScope oldWidget) =>
      !identical(trip, oldWidget.trip);
}
