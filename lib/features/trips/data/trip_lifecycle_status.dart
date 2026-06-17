import 'package:planerz/features/trips/data/trip.dart';

enum TripLifecycleStatus {
  planned,
  preparation,
}

TripLifecycleStatus tripLifecycleStatusFromFirestore(String? raw) {
  switch (raw?.trim()) {
    case 'preparation':
      return TripLifecycleStatus.preparation;
    default:
      return TripLifecycleStatus.planned;
  }
}

String tripLifecycleStatusToFirestore(TripLifecycleStatus status) {
  return switch (status) {
    TripLifecycleStatus.planned => 'planned',
    TripLifecycleStatus.preparation => 'preparation',
  };
}

extension TripLifecycleStatusX on Trip {
  bool get isInPreparation =>
      lifecycleStatus == TripLifecycleStatus.preparation;
}
