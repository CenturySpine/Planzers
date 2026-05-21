import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/user_display_label.dart'
    show avatarInitialFromDisplayLabel;
import 'package:planerz/features/ingredients/presentation/ingredient_line_editor.dart';
import 'package:planerz/features/shopping/data/shopping_item.dart';
import 'package:planerz/features/shopping/data/shopping_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class ShoppingItemRow extends ConsumerStatefulWidget {
  const ShoppingItemRow({
    super.key,
    required this.tripId,
    required this.item,
    required this.usersDataById,
    required this.normalizedLabelCounts,
    this.autoFocusLabel = false,
    this.onAutoFocusHandled,
    this.onToggleCheckedOverride,
    this.onSetClaimedByOverride,
    this.onSaveOverride,
    this.onDeleteOverride,
    this.structureLocked = false,
    this.customMenuItems,
    this.onCustomMenuAction,
  });

  final String tripId;
  final ShoppingItem item;
  final Map<String, Map<String, dynamic>> usersDataById;
  final Map<String, int> normalizedLabelCounts;
  final bool autoFocusLabel;
  final VoidCallback? onAutoFocusHandled;
  final Future<void> Function(bool checked)? onToggleCheckedOverride;
  final Future<void> Function(String? claimedBy)? onSetClaimedByOverride;
  final Future<void> Function(IngredientLineValue value)? onSaveOverride;
  final Future<void> Function()? onDeleteOverride;

  /// Non-admins cannot edit label/qty/delete when the parent list is locked.
  final bool structureLocked;

  final List<IngredientLineCustomMenuItem>? customMenuItems;
  final void Function(String actionId)? onCustomMenuAction;

  @override
  ConsumerState<ShoppingItemRow> createState() => _ShoppingItemRowState();
}

class _ShoppingItemRowState extends ConsumerState<ShoppingItemRow> {
  String _photoUrlFromUserData(Map<String, dynamic>? userData) {
    if (userData == null) return '';
    final account = (userData['account'] as Map<String, dynamic>?) ?? const {};
    final accountPhoto = (account['photoUrl'] as String?)?.trim() ?? '';
    if (accountPhoto.isNotEmpty) return accountPhoto;
    return (userData['photoUrl'] as String?)?.trim() ?? '';
  }

  bool _isDuplicateLabel(String value) {
    final normalized = _normalizeItemLabel(value);
    if (normalized.isEmpty) return false;
    final totalCount = widget.normalizedLabelCounts[normalized] ?? 0;
    final ownMatches = _normalizeItemLabel(widget.item.label) == normalized ? 1 : 0;
    return (totalCount - ownMatches) > 0;
  }

  Future<void> _toggleChecked(bool? value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final claimedBy = widget.item.claimedBy?.trim() ?? '';
    if (claimedBy.isEmpty || claimedBy != uid) return;
    if (widget.onToggleCheckedOverride != null) {
      await widget.onToggleCheckedOverride!(value ?? false);
      return;
    }
    await ref.read(shoppingRepositoryProvider).setChecked(
          tripId: widget.tripId,
          itemId: widget.item.id,
          checked: value ?? false,
        );
  }

  Future<void> _delete() async {
    if (widget.onDeleteOverride != null) {
      await widget.onDeleteOverride!();
      return;
    }
    await ref.read(shoppingRepositoryProvider).deleteItem(
          tripId: widget.tripId,
          itemId: widget.item.id,
        );
  }

  Future<void> _confirmAndDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.shoppingDeleteItemTitle),
          content: Text(l10n.shoppingDeleteItemBody),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;
    await _delete();
  }

  Future<void> _toggleClaim() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    final claimedBy = widget.item.claimedBy?.trim() ?? '';
    if (claimedBy.isNotEmpty && claimedBy != uid) return;

    final nextClaimedBy = claimedBy == uid ? null : uid;
    if (widget.onSetClaimedByOverride != null) {
      await widget.onSetClaimedByOverride!(nextClaimedBy);
      return;
    }
    await ref.read(shoppingRepositoryProvider).setClaimedBy(
          tripId: widget.tripId,
          itemId: widget.item.id,
          claimedBy: nextClaimedBy,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isChecked = widget.item.checked;
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid.trim() ?? '';
    final claimedBy = widget.item.claimedBy?.trim() ?? '';
    final isClaimedByMe = claimedBy.isNotEmpty && claimedBy == currentUid;
    final isClaimedByOther = claimedBy.isNotEmpty && claimedBy != currentUid;
    final canToggleChecked = isClaimedByMe;
    final claimedByUserData = claimedBy.isEmpty ? null : widget.usersDataById[claimedBy];
    final claimedByLabel = () {
      if (claimedByUserData != null) {
        final account =
            (claimedByUserData['account'] as Map<String, dynamic>?) ?? const {};
        final name = (account['name'] as String?)?.trim() ?? '';
        if (name.isNotEmpty) return name;
      }
      return AppLocalizations.of(context)!.shoppingTravelerFallback;
    }();
    final claimedByPhotoUrl = _photoUrlFromUserData(claimedByUserData);
    final labelStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          decoration: isChecked ? TextDecoration.lineThrough : TextDecoration.none,
          color: isChecked ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
        );

    return IngredientLineEditor(
      label: widget.item.label,
      quantityValue: widget.item.quantityValue,
      quantityUnit: widget.item.quantityUnit,
      structureLocked: widget.structureLocked,
      onSave: (value) async {
        if (widget.onSaveOverride != null) {
          await widget.onSaveOverride!(value);
          return;
        }
        await ref.read(shoppingRepositoryProvider).updateItem(
              tripId: widget.tripId,
              itemId: widget.item.id,
              label: value.label,
              checked: widget.item.checked,
              quantityValue: value.quantityValue,
              quantityUnit: value.quantityUnit,
            );
      },
      onDelete: _confirmAndDelete,
      autoFocusLabel: widget.autoFocusLabel,
      onAutoFocusHandled: widget.onAutoFocusHandled,
      isDuplicateLabel: _isDuplicateLabel,
      labelStyle: labelStyle,
      customMenuItems: widget.customMenuItems,
      onCustomMenuAction: widget.onCustomMenuAction,
      prefixWidgets: [
        Checkbox(
          value: isChecked,
          onChanged: canToggleChecked ? _toggleChecked : null,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Transform.translate(
          offset: const Offset(-4, 0),
          child: _ClaimButton(
            isClaimedByMe: isClaimedByMe,
            isClaimedByOther: isClaimedByOther,
            claimedByLabel: claimedByLabel,
            claimedByPhotoUrl: claimedByPhotoUrl,
            onTap: _toggleClaim,
            l10n: AppLocalizations.of(context)!,
          ),
        ),
      ],
    );
  }
}

class _ClaimButton extends StatelessWidget {
  const _ClaimButton({
    required this.isClaimedByMe,
    required this.isClaimedByOther,
    required this.claimedByLabel,
    required this.claimedByPhotoUrl,
    required this.onTap,
    required this.l10n,
  });

  final bool isClaimedByMe;
  final bool isClaimedByOther;
  final String claimedByLabel;
  final String claimedByPhotoUrl;
  final Future<void> Function() onTap;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const badgeSize = 26.0;
    const badgeRadius = 11.0;

    Widget claimAvatar({
      required String label,
      required String photoUrl,
      required Color backgroundColor,
      required Color foregroundColor,
    }) {
      final cleanUrl = photoUrl.trim();
      return CircleAvatar(
        radius: badgeRadius,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        foregroundImage: cleanUrl.isNotEmpty ? NetworkImage(cleanUrl) : null,
        child: Text(
          avatarInitialFromDisplayLabel(label),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
    }

    final compactStyle = IconButton.styleFrom(
      padding: const EdgeInsets.all(2),
      minimumSize: const Size(badgeSize, badgeSize),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    if (isClaimedByMe) {
      final avatar = claimAvatar(
        label: claimedByLabel,
        photoUrl: claimedByPhotoUrl,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      );
      return IconButton(
        style: compactStyle,
        tooltip: l10n.shoppingClaimRemoveMine,
        onPressed: () => onTap(),
        icon: avatar,
      );
    }

    if (isClaimedByOther) {
      final avatar = claimAvatar(
        label: claimedByLabel,
        photoUrl: claimedByPhotoUrl,
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
      );
      return Tooltip(
        message: l10n.shoppingClaimAlreadyBy(claimedByLabel),
        child: SizedBox(
          width: badgeSize,
          height: badgeSize,
          child: Center(child: avatar),
        ),
      );
    }

    return IconButton(
      style: compactStyle,
      tooltip: l10n.shoppingClaimTake,
      onPressed: () => onTap(),
      icon: const Icon(Icons.accessibility_new_outlined, size: 17),
    );
  }
}

String _normalizeItemLabel(String raw) {
  return raw.trim().toLowerCase();
}
