import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planerz/features/trips/data/trip_lifecycle_status.dart';

String tripEntryPath(String tripId, TripLifecycleStatus status) =>
    status == TripLifecycleStatus.preparation
        ? '/trips/$tripId/preparation'
        : '/trips/$tripId/overview';

Future<String> resolveTripEntryRedirect(String tripId) async {
  final cleanId = tripId.trim();
  if (cleanId.isEmpty) return '/trips';

  final snap =
      await FirebaseFirestore.instance.collection('trips').doc(cleanId).get();
  if (!snap.exists) return '/trips';

  final status = tripLifecycleStatusFromFirestore(
    snap.data()?['lifecycleStatus'] as String?,
  );
  return tripEntryPath(cleanId, status);
}
