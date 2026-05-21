import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/administration/data/maintenance_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class MaintenanceGate extends ConsumerWidget {
  const MaintenanceGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maintenanceAsync = ref.watch(maintenanceOngoingProvider);
    final isOwnerAsync = ref.watch(isApplicationOwnerProvider);

    final isMaintenanceOngoing = switch (maintenanceAsync) {
      AsyncData(:final value) => value,
      _ => false,
    };
    if (!isMaintenanceOngoing) return child;

    if (isOwnerAsync.isLoading &&
        FirebaseAuth.instance.currentUser != null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isApplicationOwner = isOwnerAsync.asData?.value ?? false;
    if (!isApplicationOwner) {
      return const PopScope(
        canPop: false,
        child: _MaintenanceScreen(),
      );
    }

    return child;
  }
}

class _MaintenanceScreen extends StatelessWidget {
  const _MaintenanceScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.construction_outlined,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.maintenanceTitle,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.maintenanceBody,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
