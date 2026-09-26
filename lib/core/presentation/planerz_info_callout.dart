import 'package:flutter/material.dart';
import 'package:planerz/core/presentation/pz_components.dart';

/// Info callout — thin wrapper over the shared [PzCallout].
class PlanerzInfoCallout extends StatelessWidget {
  const PlanerzInfoCallout({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) => PzCallout(message: message);
}
