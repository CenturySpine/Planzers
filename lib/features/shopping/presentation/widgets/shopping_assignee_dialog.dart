import 'package:flutter/material.dart';
import 'package:planerz/features/auth/data/user_display_label.dart'
    show avatarInitialFromDisplayLabel;
import 'package:planerz/features/trips/data/trip_member.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Trip participant who can be put in charge of shopping items: only
/// participants with an account, since taking care of an item is tied to a
/// user (`claimedBy`).
class ShoppingAssignee {
  const ShoppingAssignee({
    required this.userId,
    required this.label,
    this.photoUrl = '',
  });

  final String userId;
  final String label;
  final String photoUrl;
}

/// Assignable participants of a trip, sorted by name: current members
/// ([memberUserIds]) whose participant slot is linked to an account.
List<ShoppingAssignee> shoppingAssigneesFor({
  required List<TripMember> participants,
  required List<String> memberUserIds,
  required Map<String, String> labelsById,
  required Map<String, String> photoUrlsByUserId,
}) {
  final members = memberUserIds.map((id) => id.trim()).toSet();
  final seen = <String>{};
  final assignees = <ShoppingAssignee>[];
  for (final participant in participants) {
    final userId = participant.userId?.trim() ?? '';
    if (userId.isEmpty || !members.contains(userId) || !seen.add(userId)) {
      continue;
    }
    assignees.add(
      ShoppingAssignee(
        userId: userId,
        label: labelsById[userId] ?? participant.participantName,
        photoUrl: photoUrlsByUserId[userId] ?? '',
      ),
    );
  }
  assignees.sort(
    (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
  );
  return assignees;
}

/// Asks who takes care of shopping items. Returns the chosen user id, an
/// empty string for "nobody" (offered when [allowNobody]), or null when
/// cancelled.
Future<String?> showShoppingAssigneeDialog(
  BuildContext context, {
  required List<ShoppingAssignee> assignees,
  String? initialUserId,
  bool allowNobody = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ShoppingAssigneeDialog(
      assignees: assignees,
      initialUserId: initialUserId?.trim() ?? '',
      allowNobody: allowNobody,
    ),
  );
}

class _ShoppingAssigneeDialog extends StatefulWidget {
  const _ShoppingAssigneeDialog({
    required this.assignees,
    required this.initialUserId,
    required this.allowNobody,
  });

  final List<ShoppingAssignee> assignees;
  final String initialUserId;
  final bool allowNobody;

  @override
  State<_ShoppingAssigneeDialog> createState() =>
      _ShoppingAssigneeDialogState();
}

class _ShoppingAssigneeDialogState extends State<_ShoppingAssigneeDialog> {
  /// Selected user id; empty means "nobody" (or no choice yet).
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUserId;
    final isKnown = widget.assignees.any((a) => a.userId == initial);
    _selectedId = isKnown ? initial : '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final canConfirm = _selectedId.isNotEmpty || widget.allowNobody;

    return AlertDialog(
      title: Text(l10n.shoppingAssignDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: RadioGroup<String>(
          groupValue: _selectedId,
          onChanged: (value) {
            if (value != null) setState(() => _selectedId = value);
          },
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final assignee in widget.assignees)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Radio<String>(value: assignee.userId),
                    title: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: colorScheme.secondaryContainer,
                          foregroundColor: colorScheme.onSecondaryContainer,
                          foregroundImage: assignee.photoUrl.trim().isNotEmpty
                              ? NetworkImage(assignee.photoUrl.trim())
                              : null,
                          child: Text(
                            avatarInitialFromDisplayLabel(assignee.label),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(assignee.label)),
                      ],
                    ),
                    onTap: () => setState(() => _selectedId = assignee.userId),
                  ),
                if (widget.allowNobody)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Radio<String>(value: ''),
                    title: Text(l10n.shoppingAssignNobody),
                    onTap: () => setState(() => _selectedId = ''),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed:
              canConfirm ? () => Navigator.of(context).pop(_selectedId) : null,
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
