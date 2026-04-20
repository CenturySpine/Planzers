import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/core/notifications/unread_counters_sync.dart';
import 'package:planzers/core/push/fcm_token_sync.dart';
import 'package:planzers/features/account/data/account_repository.dart';
import 'package:planzers/features/auth/data/users_repository.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  final usersRepository = ref.watch(usersRepositoryProvider);
  final accountRepository = ref.watch(accountRepositoryProvider);
  return FirebaseAuth.instance.authStateChanges().asyncMap((user) async {
    if (user != null) {
      await usersRepository.ensureUserDocument(user);
      unawaited(accountRepository.syncMyGoogleProfilePhotoToStorage());
      unawaited(syncFcmTokenAfterSignIn(user));
      unawaited(resyncMyUnreadCountersAfterSignIn());
    }
    return user;
  });
});

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.go('/sign-in');
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.go('/trips');
          });
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        body: Center(
          child: Text('Erreur auth: $error'),
        ),
      ),
    );
  }
}
