import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/administration/data/maintenance_repository.dart';

class AdminMaintenancePage extends ConsumerStatefulWidget {
  const AdminMaintenancePage({super.key});

  static const String routePath = '/administration/maintenance';

  @override
  ConsumerState<AdminMaintenancePage> createState() =>
      _AdminMaintenancePageState();
}

class _AdminMaintenancePageState extends ConsumerState<AdminMaintenancePage> {
  bool _isUpdating = false;

  Future<void> _setMaintenanceOngoing(bool ongoing) async {
    setState(() => _isUpdating = true);
    try {
      await ref
          .read(maintenanceRepositoryProvider)
          .setMaintenanceOngoing(ongoing);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec de la mise à jour : $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ongoingAsync = ref.watch(maintenanceOngoingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance'),
      ),
      body: ongoingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Impossible de charger l\'état de maintenance.',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        data: (isOngoing) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            Card(
              child: SwitchListTile(
                title: const Text('Activer la maintenance'),
                subtitle: const Text(
                  'Les utilisateurs voient l\'écran de maintenance ; '
                  'les propriétaires de l\'application conservent l\'accès.',
                ),
                value: isOngoing,
                onChanged: _isUpdating
                    ? null
                    : (value) => _setMaintenanceOngoing(value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
