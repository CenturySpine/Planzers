import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(firestore: FirebaseFirestore.instance);
});

final usersDataByIdsKeyStreamProvider = StreamProvider.autoDispose
    .family<Map<String, Map<String, dynamic>>, String>((ref, idsKey) {
  final ids = _idsFromStableKey(idsKey);
  return ref.watch(usersRepositoryProvider).watchUsersDataByIds(ids);
});

String stableUsersIdsKey(Iterable<String> ids) {
  final unique = <String>{};
  for (final id in ids) {
    final trimmed = id.trim();
    if (trimmed.isNotEmpty) unique.add(trimmed);
  }
  if (unique.isEmpty) return '';
  final sorted = unique.toList()..sort();
  return sorted.join('|');
}

List<String> _idsFromStableKey(String idsKey) {
  if (idsKey.trim().isEmpty) return const <String>[];
  return idsKey
      .split('|')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
}

class UsersRepository {
  UsersRepository({required this.firestore});

  final FirebaseFirestore firestore;

  String _bestAuthPhoneNumber(User user) {
    final direct = (user.phoneNumber ?? '').trim();
    if (direct.isNotEmpty) return direct;
    for (final info in user.providerData) {
      final candidate = (info.phoneNumber ?? '').trim();
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  /// Common ITU-T E.164 country codes used to split [user.phoneNumber] into
  /// [phoneCountryCode] and local [phoneNumber] when Firebase Auth returns the
  /// E.164 form without a separator (e.g. `+33783836613`). Unknown prefixes
  /// fall back to storing the raw E.164 in the number field.
  static const List<String> _knownE164CountryCodes = <String>[
    '+1',
    '+7',
    '+20',
    '+27',
    '+30',
    '+31',
    '+32',
    '+33',
    '+34',
    '+36',
    '+39',
    '+40',
    '+41',
    '+43',
    '+44',
    '+45',
    '+46',
    '+47',
    '+48',
    '+49',
    '+90',
    '+212',
    '+213',
    '+216',
    '+352',
    '+377',
    '+972',
  ];

  ({String countryCode, String number}) _splitPhoneNumber(String rawPhone) {
    final normalized = rawPhone.trim();
    if (normalized.isEmpty) {
      return (countryCode: '', number: '');
    }

    final spaced =
        RegExp(r'^(\+[0-9]{1,4})\s+([0-9 ]+)$').firstMatch(normalized);
    if (spaced != null) {
      return (
        countryCode: spaced.group(1)?.trim() ?? '',
        number: spaced.group(2)?.trim() ?? normalized,
      );
    }

    String? bestPrefix;
    for (final prefix in _knownE164CountryCodes) {
      if (normalized.startsWith(prefix)) {
        if (bestPrefix == null || prefix.length > bestPrefix.length) {
          bestPrefix = prefix;
        }
      }
    }
    if (bestPrefix != null) {
      return (
        countryCode: bestPrefix,
        number: normalized.substring(bestPrefix.length),
      );
    }

    return (countryCode: '', number: normalized);
  }

  Future<void> ensureUserDocument(User user) async {
    final userRef = firestore.collection('users').doc(user.uid);

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final now = FieldValue.serverTimestamp();
      final googlePhotoUrl = (user.photoURL ?? '').trim();
      final authPhoneNumber = _bestAuthPhoneNumber(user);
      final splitPhone = _splitPhoneNumber(authPhoneNumber);
      final hasAuthPhone = authPhoneNumber.isNotEmpty;
      final authDisplayName = (user.displayName ?? '').trim();
      final initialAccountName = authDisplayName.isNotEmpty
          ? authDisplayName
          : authPhoneNumber.isNotEmpty
              ? authPhoneNumber
              : (user.email ?? '').trim();
      final baseData = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'account': {
          'email': user.email,
          if (hasAuthPhone) 'phoneNumber': splitPhone.number,
          if (hasAuthPhone) 'phoneCountryCode': splitPhone.countryCode,
        },
        'lastSignInAt': now,
      };
      if (initialAccountName.isNotEmpty) {
        (baseData['account'] as Map<String, dynamic>)['name'] =
            initialAccountName;
      }
      if (googlePhotoUrl.isNotEmpty) {
        baseData['googlePhotoUrl'] = googlePhotoUrl;
        (baseData['account'] as Map<String, dynamic>)['googlePhotoUrl'] =
            googlePhotoUrl;
      }

      if (snapshot.exists) {
        final existing = snapshot.data() ?? const <String, dynamic>{};
        final existingAccount =
            (existing['account'] as Map<String, dynamic>?) ?? const {};
        final existingAccountPhoto =
            (existingAccount['photoUrl'] as String?)?.trim() ?? '';
        final existingRootPhoto =
            (existing['photoUrl'] as String?)?.trim() ?? '';
        final existingName = (existingAccount['name'] as String?)?.trim() ?? '';
        final hasCustomPhoto =
            existingAccountPhoto.isNotEmpty || existingRootPhoto.isNotEmpty;

        // Never overwrite user-managed profile fields on subsequent sign-ins.
        // An empty value (e.g. user cleared their phone or email) is an
        // intentional choice and must survive across reconnections.
        final patch = <String, dynamic>{...baseData};
        patch.remove('email');
        final patchAccount = (patch['account'] as Map<String, dynamic>);
        patchAccount.remove('email');
        patchAccount.remove('phoneNumber');
        patchAccount.remove('phoneCountryCode');
        if (existingName.isNotEmpty) {
          patchAccount.remove('name');
        }
        if (!hasCustomPhoto && googlePhotoUrl.isNotEmpty) {
          patch['photoUrl'] = googlePhotoUrl;
          patchAccount['photoUrl'] = googlePhotoUrl;
        }
        transaction.set(userRef, patch, SetOptions(merge: true));
      } else {
        final initialAccount = Map<String, dynamic>.from(
          baseData['account'] as Map<String, dynamic>,
        );
        if (googlePhotoUrl.isNotEmpty) {
          initialAccount['photoUrl'] = googlePhotoUrl;
          initialAccount['googlePhotoUrl'] = googlePhotoUrl;
        }
        transaction.set(userRef, {
          ...baseData,
          if (googlePhotoUrl.isNotEmpty) 'photoUrl': googlePhotoUrl,
          'account': initialAccount,
          'createdAt': now,
        });
      }
    });
  }

  /// Latest map of `users/{uid}.data()` for the given [ids].
  ///
  /// Firestore limits `whereIn` to 30 values; larger [ids] lists are queried in
  /// chunks and merged.
  Stream<Map<String, Map<String, dynamic>>> watchUsersDataByIds(
      List<String> ids) {
    final unique = <String>{};
    for (final id in ids) {
      final t = id.trim();
      if (t.isNotEmpty) unique.add(t);
    }
    if (unique.isEmpty) {
      return Stream.value(const <String, Map<String, dynamic>>{});
    }

    const maxIn = 30;
    final list = unique.toList();
    if (list.length <= maxIn) {
      return firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: list)
          .snapshots()
          .map((snap) => {for (final d in snap.docs) d.id: d.data()});
    }

    final chunks = <List<String>>[];
    for (var i = 0; i < list.length; i += maxIn) {
      final end = i + maxIn > list.length ? list.length : i + maxIn;
      chunks.add(list.sublist(i, end));
    }

    late final StreamController<Map<String, Map<String, dynamic>>> controller;
    final latest =
        List<Map<String, Map<String, dynamic>>?>.filled(chunks.length, null);
    var subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emitIfComplete() {
      if (latest.any((m) => m == null)) return;
      final out = <String, Map<String, dynamic>>{};
      for (final part in latest) {
        out.addAll(part!);
      }
      controller.add(out);
    }

    controller = StreamController<Map<String, Map<String, dynamic>>>(
      onListen: () {
        for (var i = 0; i < chunks.length; i++) {
          final index = i;
          subscriptions.add(
            firestore
                .collection('users')
                .where(FieldPath.documentId, whereIn: chunks[index])
                .snapshots()
                .listen((snap) {
              latest[index] = {
                for (final d in snap.docs) d.id: d.data(),
              };
              emitIfComplete();
            }),
          );
        }
      },
      onCancel: () {
        for (final s in subscriptions) {
          s.cancel();
        }
        subscriptions = [];
      },
    );

    return controller.stream;
  }
}
