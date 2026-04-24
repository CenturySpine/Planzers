import 'package:flutter/material.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/presentation/widgets/permission_min_role_selector.dart';

const double _permissionsColumnSpacing = 12;

class TripPermissionItemRow extends StatelessWidget {
  const TripPermissionItemRow({
    super.key,
    required this.title,
    required this.minRole,
    required this.icon,
    required this.busy,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final TripPermissionRole minRole;
  final IconData icon;
  final bool busy;
  final bool enabled;
  final ValueChanged<TripPermissionRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(child: Text(title)),
              ],
            ),
          ),
          const SizedBox(width: _permissionsColumnSpacing),
          Expanded(
            flex: 4,
            child: PermissionMinRoleSelector(
              value: minRole,
              busy: busy,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class TripPermissionsColumnsHeader extends StatelessWidget {
  const TripPermissionsColumnsHeader({
    super.key,
    required this.actionLabel,
    required this.minRoleLabel,
  });

  final String actionLabel;
  final String minRoleLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        );

    Widget buildCartouche(String label) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: textStyle),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: buildCartouche(actionLabel),
          ),
          const SizedBox(width: _permissionsColumnSpacing),
          Expanded(
            flex: 4,
            child: buildCartouche(minRoleLabel),
          ),
        ],
      ),
    );
  }
}
