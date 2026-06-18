import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/core/intl/app_language.dart';

const Color _kSemanticError = Color(0xFFBA1A1A);
const Color _kSemanticWarning = Color(0xFFC49A00);

List<BoxShadow> get _accountCardShadow => [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.06),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
    ];

/// Uppercase section label above account cards.
class AccountSectionHeader extends StatelessWidget {
  const AccountSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: NeonPalette.onSurfaceVariant,
          letterSpacing: 0.5,
          height: 1.2,
        ),
      ),
    );
  }
}

/// White card container with elevation-1 shadow.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: NeonPalette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _accountCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Divider indented after the icon pill column.
class AccountCardDivider extends StatelessWidget {
  const AccountCardDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 64),
      color: NeonPalette.divider,
    );
  }
}

enum AccountIconTint { primary, warning, accent }

/// Rounded square icon background used in info and preference rows.
class AccountIconPill extends StatelessWidget {
  const AccountIconPill({
    super.key,
    required this.icon,
    this.tint = AccountIconTint.primary,
    this.filled = false,
  });

  final IconData icon;
  final AccountIconTint tint;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tint) {
      AccountIconTint.primary => (
          NeonPalette.nameIconBackground,
          NeonPalette.primary,
        ),
      AccountIconTint.warning => (
          Color.lerp(NeonPalette.surface, _kSemanticWarning, 0.16)!,
          _kSemanticWarning,
        ),
      AccountIconTint.accent => (
          Color.lerp(NeonPalette.surface, NeonPalette.accent, 0.14)!,
          NeonPalette.accent,
        ),
    };

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: 20,
        color: foreground,
        fill: filled ? 1 : 0,
      ),
    );
  }
}

/// Read-only info row with label, value and edit affordance.
class AccountInfoRow extends StatelessWidget {
  const AccountInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onEdit,
    required this.editTooltip,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onEdit;
  final String editTooltip;

  @override
  Widget build(BuildContext context) {
    final trimmed = value.trim();
    final isEmpty = trimmed.isEmpty;
    final displayValue = isEmpty ? '—' : trimmed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      child: Row(
        children: [
          AccountIconPill(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: NeonPalette.onSurfaceVariant,
                    letterSpacing: 0.3,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w500,
                    color: isEmpty ? NeonPalette.outline : NeonPalette.deep,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          AccountEditButton(onPressed: onEdit, tooltip: editTooltip),
        ],
      ),
    );
  }
}

class AccountEditButton extends StatelessWidget {
  const AccountEditButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: NeonPalette.primaryTint,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: const SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              Icons.edit_outlined,
              size: 17,
              color: NeonPalette.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tinted background wrapper for inline field editing.
class AccountEditWrap extends StatelessWidget {
  const AccountEditWrap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: Color.lerp(NeonPalette.surface, NeonPalette.primary, 0.04),
      child: child,
    );
  }
}

/// Bordered input shell matching the handoff `.input-shell` style.
class AccountInputShell extends StatefulWidget {
  const AccountInputShell({
    super.key,
    required this.icon,
    required this.child,
    this.hasError = false,
  });

  final IconData icon;
  final Widget child;
  final bool hasError;

  @override
  State<AccountInputShell> createState() => _AccountInputShellState();
}

class _AccountInputShellState extends State<AccountInputShell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.hasError
        ? _kSemanticError
        : _focused
            ? NeonPalette.primary
            : NeonPalette.divider;
    final borderWidth = (_focused || widget.hasError) ? 2.0 : 1.5;

    return Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: NeonPalette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 18,
              color: _focused ? NeonPalette.primary : NeonPalette.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

/// Save / cancel round action buttons beside editable fields.
class AccountEditActions extends StatelessWidget {
  const AccountEditActions({
    super.key,
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
    required this.saveTooltip,
    required this.cancelTooltip,
  });

  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String saveTooltip;
  final String cancelTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: saveTooltip,
          child: Material(
            color: NeonPalette.primary,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isSaving ? null : onSave,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: cancelTooltip,
          child: Material(
            color: Colors.transparent,
            shape: CircleBorder(
              side: BorderSide(color: NeonPalette.outline, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isSaving ? null : onCancel,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: NeonPalette.text700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Preference navigation row inside the preferences card.
class AccountPrefTile extends StatelessWidget {
  const AccountPrefTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tint = AccountIconTint.primary,
    this.filled = false,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final AccountIconTint tint;
  final bool filled;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
          child: Row(
            children: [
              AccountIconPill(icon: icon, tint: tint, filled: filled),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: NeonPalette.deep,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: NeonPalette.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  const Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: NeonPalette.divider,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// FR / EN flag selector styled per the handoff language pills.
class AccountLanguageSelector extends StatelessWidget {
  const AccountLanguageSelector({
    super.key,
    required this.currentLanguage,
    required this.isUpdating,
    required this.onSelect,
    required this.frenchTooltip,
    required this.englishTooltip,
  });

  final AppLanguage currentLanguage;
  final bool isUpdating;
  final ValueChanged<AppLanguage> onSelect;
  final String frenchTooltip;
  final String englishTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FlagPill(
          assetPath: 'assets/images/flag_fr.svg',
          selected: currentLanguage == AppLanguage.frFr,
          enabled: !isUpdating,
          tooltip: frenchTooltip,
          onTap: () => onSelect(AppLanguage.frFr),
        ),
        const SizedBox(width: 6),
        _FlagPill(
          assetPath: 'assets/images/flag_us.svg',
          selected: currentLanguage == AppLanguage.enUs,
          enabled: !isUpdating,
          tooltip: englishTooltip,
          onTap: () => onSelect(AppLanguage.enUs),
        ),
      ],
    );
  }
}

class _FlagPill extends StatelessWidget {
  const _FlagPill({
    required this.assetPath,
    required this.selected,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  final String assetPath;
  final bool selected;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? NeonPalette.nameEditPillBackground : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? NeonPalette.primary : NeonPalette.divider,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: SvgPicture.asset(
              assetPath,
              width: 18,
              height: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class AccountHelpText extends StatelessWidget {
  const AccountHelpText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: NeonPalette.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }
}

/// Outlined full-width push notifications button (web only).
class AccountNotificationsButton extends StatelessWidget {
  const AccountNotificationsButton({
    super.key,
    required this.label,
    required this.isEnabling,
    required this.onPressed,
  });

  final String label;
  final bool isEnabling;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: NeonPalette.outline, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isEnabling)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(
                    Icons.notifications_active_outlined,
                    size: 20,
                    color: NeonPalette.primary,
                  ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: NeonPalette.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile header: avatar, camera pill, display name and email.
class AccountProfileHeader extends StatelessWidget {
  const AccountProfileHeader({
    super.key,
    required this.photoUrl,
    required this.displayLabel,
    required this.email,
    required this.isPhotoBusy,
    required this.onCameraTap,
    required this.cameraTooltip,
  });

  final String photoUrl;
  final String displayLabel;
  final String email;
  final bool isPhotoBusy;
  final VoidCallback onCameraTap;
  final String cameraTooltip;

  @override
  Widget build(BuildContext context) {
    final initial = displayLabel.trim().isNotEmpty
        ? displayLabel.trim()[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
      child: Column(
        children: [
          SizedBox(
            width: 88,
            height: 88 + 12,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  child: _buildAvatar(photoUrl, initial),
                ),
                Positioned(
                  right: -2,
                  bottom: 0,
                  child: Tooltip(
                    message: cameraTooltip,
                    child: Material(
                      color: NeonPalette.primary,
                      shape: CircleBorder(
                        side: BorderSide(
                          color: NeonPalette.scaffoldBackground,
                          width: 2.5,
                        ),
                      ),
                      elevation: 1,
                      shadowColor: Colors.black.withValues(alpha: 0.06),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: isPhotoBusy ? null : onCameraTap,
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: Center(
                            child: isPhotoBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.photo_camera_outlined,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            displayLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: NeonPalette.deep,
              letterSpacing: -0.2,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: NeonPalette.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String photoUrl, String initial) {
    if (photoUrl.isEmpty) {
      return Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: NeonPalette.primarySoft,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: NeonPalette.primary,
            height: 1,
          ),
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: 88,
        height: 88,
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: NeonPalette.primarySoft,
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: NeonPalette.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for profile photo actions.
class AccountPhotoBottomSheet extends StatelessWidget {
  const AccountPhotoBottomSheet({
    super.key,
    required this.title,
    required this.galleryLabel,
    required this.cameraLabel,
    required this.deleteLabel,
    required this.showDelete,
    required this.onGallery,
    required this.onCamera,
    required this.onDelete,
  });

  final String title;
  final String galleryLabel;
  final String cameraLabel;
  final String deleteLabel;
  final bool showDelete;
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NeonPalette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: NeonPalette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: NeonPalette.deep,
                  ),
                ),
              ),
            ),
            _SheetAction(
              icon: Icons.photo_library_outlined,
              label: galleryLabel,
              onTap: onGallery,
            ),
            _SheetAction(
              icon: Icons.photo_camera_outlined,
              label: cameraLabel,
              onTap: onCamera,
            ),
            if (showDelete)
              _SheetAction(
                icon: Icons.delete_outline,
                label: deleteLabel,
                onTap: onDelete,
                destructive: true,
              ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? _kSemanticError : NeonPalette.text700;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: NeonPalette.divider)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: destructive ? _kSemanticError : NeonPalette.deep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Destructive photo removal dialog with inverted button emphasis.
class AccountRemovePhotoDialog extends StatelessWidget {
  const AccountRemovePhotoDialog({
    super.key,
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.deleteLabel,
    required this.photoUrl,
    required this.displayLabel,
  });

  final String title;
  final String body;
  final String cancelLabel;
  final String deleteLabel;
  final String photoUrl;
  final String displayLabel;

  @override
  Widget build(BuildContext context) {
    final initial = displayLabel.trim().isNotEmpty
        ? displayLabel.trim()[0].toUpperCase()
        : '?';

    return Dialog(
      backgroundColor: NeonPalette.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogAvatar(photoUrl: photoUrl, initial: initial),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: NeonPalette.deep,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: NeonPalette.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(
                      foregroundColor: _kSemanticError,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    child: Text(deleteLabel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: FilledButton.styleFrom(
                      backgroundColor: NeonPalette.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 11,
                      ),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    child: Text(cancelLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogAvatar extends StatelessWidget {
  const _DialogAvatar({required this.photoUrl, required this.initial});

  final String photoUrl;
  final String initial;

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isEmpty) {
      return CircleAvatar(
        radius: 32,
        backgroundColor: NeonPalette.primarySoft,
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: NeonPalette.primary,
          ),
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: 64,
        height: 64,
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => CircleAvatar(
            radius: 32,
            backgroundColor: NeonPalette.primarySoft,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: NeonPalette.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
