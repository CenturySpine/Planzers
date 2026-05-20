import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/core/notifications/unread_counters_sync.dart';
import 'package:planerz/core/push/fcm_token_sync.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/auth/display_name_setup_dialog.dart';
import 'package:planerz/l10n/app_localizations.dart';

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

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _navigating = false;

  Future<void> _checkNameAndNavigate() async {
    if (_navigating || !mounted) return;
    _navigating = true;
    try {
      final snapshot = await ref
          .read(accountRepositoryProvider)
          .watchMyUserDocument()
          .first;
      if (!mounted) return;
      final name =
          (snapshot.data()?['account'] as Map<String, dynamic>?)?['name']
              as String?;
      if (accountNameNeedsSetup(name)) {
        final l10n = AppLocalizations.of(context)!;
        final saved = await showDisplayNameSetupDialog(context);
        if (!mounted) return;
        if (!saved) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(l10n.profileNameRequiredMessage)),
          );
          await FirebaseAuth.instance.signOut();
          return;
        }
      }
      if (mounted) context.go('/trips');
    } catch (e) {
      debugPrint('AuthGate name check error: $e');
      if (mounted) context.go('/trips');
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go('/sign-in');
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkNameAndNavigate();
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
          child: Text(
            AppLocalizations.of(context)!.authErrorWithDetails(error.toString()),
          ),
        ),
      ),
    );
  }
}
