import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/users_repository.dart';

/// Resolves Firestore user payloads for activity authors keyed by `creatorIdsKey`
/// (`uid1|uid2|...`, sorted).
final tripActivityCreatorsDataProvider = StreamProvider.autoDispose
    .family<Map<String, Map<String, dynamic>>, String>((ref, creatorIdsKey) {
  final creatorIds = creatorIdsKey
      .split('|')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
  return ref.read(usersRepositoryProvider).watchUsersDataByIds(creatorIds);
});
