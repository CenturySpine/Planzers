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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Activer la maintenance'),
                  enabled: !_isUpdating,
                  onTap: _isUpdating
                      ? null
                      : () => _setMaintenanceOngoing(true),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Désactiver la maintenance'),
                  enabled: !_isUpdating,
                  onTap: _isUpdating
                      ? null
                      : () => _setMaintenanceOngoing(false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
