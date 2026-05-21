import 'package:flutter/material.dart';

class AdminMaintenancePage extends StatelessWidget {
  const AdminMaintenancePage({super.key});

  static const String routePath = '/administration/maintenance';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance'),
      ),
      body: const SizedBox.shrink(),
    );
  }
}
