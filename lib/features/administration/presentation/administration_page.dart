import 'package:flutter/material.dart';

class AdministrationPage extends StatelessWidget {
  const AdministrationPage({super.key});

  static const String routePath = '/administration';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
      ),
      body: const SizedBox.shrink(),
    );
  }
}
