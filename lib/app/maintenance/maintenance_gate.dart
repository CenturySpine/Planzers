import 'package:flutter/material.dart';
import 'package:planerz/l10n/app_localizations.dart';

const kMaintenanceMode = true;

class MaintenanceGate extends StatelessWidget {
  const MaintenanceGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kMaintenanceMode) return child;

    return PopScope(
      canPop: false,
      child: _MaintenanceScreen(),
    );
  }
}

class _MaintenanceScreen extends StatelessWidget {
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
