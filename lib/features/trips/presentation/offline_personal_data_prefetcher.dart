import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/packing/data/packing_repository.dart';
import 'package:planerz/features/trips/data/traveler_modules_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';

/// Keeps the traveler's personal data of their current and upcoming trips
/// (personal modules, document list, packing list) listened to while the
/// trips list is shown, so the offline cache holds it even for a trip not
/// opened since signing in. Renders nothing.
class OfflinePersonalDataPrefetcher extends ConsumerWidget {
  const OfflinePersonalDataPrefetcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final trips = ref.watch(tripsStreamProvider).asData?.value ?? const [];
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    for (final trip in trips) {
      // Application owners may list other people's trips: skip those.
      if (!trip.memberUserIds.contains(uid)) continue;
      final endDate = trip.endDate;
      if (endDate != null && endDate.isBefore(cutoff)) continue;
      final modules =
          ref.watch(myTravelerModulesStreamProvider(trip.id)).asData?.value;
      if (modules?.walletEnabled ?? false) {
        ref.watch(myWalletDocumentsStreamProvider(trip.id));
      }
      ref.watch(myPackingListConfigStreamProvider(trip.id));
      ref.watch(myPackingItemsStreamProvider(trip.id));
    }
    return const SizedBox.shrink();
  }
}
