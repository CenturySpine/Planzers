import 'package:flutter/material.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/l10n/app_localizations.dart';

class PermissionMinRoleSelector extends StatelessWidget {
  const PermissionMinRoleSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.busy = false,
    this.enabled = true,
    this.availableRoles,
  });

  final TripPermissionRole value;
  final ValueChanged<TripPermissionRole> onChanged;
  final bool busy;
  final bool enabled;
  final List<TripPermissionRole>? availableRoles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final roles = availableRoles ??
        const <TripPermissionRole>[
          TripPermissionRole.participant,
          TripPermissionRole.admin,
          TripPermissionRole.owner,
        ];
    return DropdownButton<TripPermissionRole>(
      isExpanded: true,
      value: value,
      onChanged: enabled
          ? (next) {
              if (next == null || next == value) return;
              onChanged(next);
            }
          : null,
      items: roles
          .map(
            (role) => DropdownMenuItem<TripPermissionRole>(
              value: role,
              child: Text(_labelForRole(l10n, role)),
            ),
          )
          .toList(),
    );
  }
}

String permissionRoleLabel(
  BuildContext context,
  TripPermissionRole role,
) {
  final l10n = AppLocalizations.of(context)!;
  return _labelForRole(l10n, role);
}

String _labelForRole(
  AppLocalizations l10n,
  TripPermissionRole role,
) {
  return switch (role) {
    TripPermissionRole.participant => l10n.roleParticipant,
    TripPermissionRole.chef => l10n.roleChef,
    TripPermissionRole.admin => l10n.roleAdmin,
    TripPermissionRole.owner => l10n.roleOwner,
  };
}
