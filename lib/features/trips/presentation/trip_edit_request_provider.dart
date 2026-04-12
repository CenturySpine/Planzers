import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When [state] becomes `true`, [TripOverviewPage] opens trip metadata editing once.
///
/// The overview resets this notifier after handling (e.g. shell AppBar "edit trip").
final tripEditRequestedProvider =
    NotifierProvider.autoDispose.family<TripEditRequested, bool, String>(
  TripEditRequested.new,
);

class TripEditRequested extends Notifier<bool> {
  /// [tripId] scopes the family instance; editing logic uses the same id from UI.
  TripEditRequested(String _);

  @override
  bool build() => false;

  void request() => state = true;

  void clear() => state = false;
}
