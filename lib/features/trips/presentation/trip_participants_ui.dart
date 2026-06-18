import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/l10n/app_localizations.dart';

BoxShadow _elev1Shadow() => BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 2,
      offset: const Offset(0, 1),
    );

/// [Icons.child_care] styled per the participants mockup (boxed toggle or plain).
class TripChildCareIcon extends StatelessWidget {
  const TripChildCareIcon({
    super.key,
    this.boxed = true,
    this.iconSize = 22,
    this.boxSize = 38,
  });

  final bool boxed;
  final double iconSize;
  final double boxSize;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      Icons.child_care,
      size: iconSize,
      color: boxed ? NeonPalette.accent : NeonPalette.outline,
    );
    if (!boxed) {
      return icon;
    }
    return Container(
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(
        color: Color.lerp(NeonPalette.surface, NeonPalette.accent, 0.13),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}

/// M3-style tab bar for the participants / groups screen.
class TripParticipantsTabBar extends StatelessWidget {
  const TripParticipantsTabBar({
    super.key,
    required this.controller,
    required this.participantsLabel,
    required this.groupsLabel,
  });

  final TabController controller;
  final String participantsLabel;
  final String groupsLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.scaffoldBackground,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: NeonPalette.divider)),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return Row(
              children: [
                _TabButton(
                  label: participantsLabel,
                  selected: controller.index == 0,
                  onTap: () => controller.animateTo(0),
                ),
                _TabButton(
                  label: groupsLabel,
                  selected: controller.index == 1,
                  onTap: () => controller.animateTo(1),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? NeonPalette.primary : NeonPalette.onSurfaceVariant,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            if (selected)
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: NeonPalette.primary,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TripParticipantsFab extends StatelessWidget {
  const TripParticipantsFab({
    super.key,
    required this.onPressed,
    required this.tooltip,
    required this.heroTag,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FloatingActionButton(
        heroTag: heroTag,
        tooltip: tooltip,
        onPressed: onPressed,
        elevation: 3,
        highlightElevation: 4,
        backgroundColor: NeonPalette.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.add, size: 26),
      ),
    );
  }
}

class TripParticipantsPrimaryCallout extends StatelessWidget {
  const TripParticipantsPrimaryCallout({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: NeonPalette.participantsCalloutBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NeonPalette.participantsCalloutBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: NeonPalette.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: NeonPalette.deep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TripParticipantsSearchField extends StatelessWidget {
  const TripParticipantsSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      textField: true,
      label: l10n.nameSearchLabel,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: NeonPalette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NeonPalette.divider, width: 1.5),
          boxShadow: [_elev1Shadow()],
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 20, color: NeonPalette.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 14, color: NeonPalette.deep),
                decoration: InputDecoration(
                  hintText: l10n.nameSearchHint,
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: NeonPalette.outline,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear, size: 20),
                tooltip: l10n.nameSearchClear,
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }
}

enum TripParticipantRoleChipKind {
  owner,
  admin,
  childPlanned,
  planned,
  you,
}

class TripParticipantRoleChip extends StatelessWidget {
  const TripParticipantRoleChip({super.key, required this.kind});

  final TripParticipantRoleChipKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = switch (kind) {
      TripParticipantRoleChipKind.owner => l10n.tripParticipantsRoleChipOwner,
      TripParticipantRoleChipKind.admin => l10n.roleAdmin,
      TripParticipantRoleChipKind.childPlanned =>
        l10n.tripParticipantsRoleChipChildPlanned,
      TripParticipantRoleChipKind.planned =>
        l10n.tripParticipantsRoleChipPlanned,
      TripParticipantRoleChipKind.you => l10n.tripParticipantsRoleChipYou,
    };
    final bg = switch (kind) {
      TripParticipantRoleChipKind.owner => NeonPalette.participantsChipOwnerBg,
      TripParticipantRoleChipKind.admin => NeonPalette.participantsChipAdminBg,
      TripParticipantRoleChipKind.childPlanned => NeonPalette.participantsChipChildBg,
      TripParticipantRoleChipKind.planned => NeonPalette.participantsChipNeutralBg,
      TripParticipantRoleChipKind.you => NeonPalette.participantsChipNeutralBg,
    };
    final fg = switch (kind) {
      TripParticipantRoleChipKind.owner => NeonPalette.participantsChipOwnerFg,
      TripParticipantRoleChipKind.admin => NeonPalette.participantsChipAdminFg,
      TripParticipantRoleChipKind.childPlanned => NeonPalette.participantsChipChildFg,
      TripParticipantRoleChipKind.planned => NeonPalette.participantsChipNeutralFg,
      TripParticipantRoleChipKind.you => NeonPalette.participantsChipNeutralFg,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: kind == TripParticipantRoleChipKind.you ? 10 : 11,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: fg,
        ),
      ),
    );
  }
}

TripParticipantRoleChipKind? roleChipKindForParticipant({
  required bool isOwnerRow,
  required bool isAdmin,
  required bool isClaimed,
  required bool isChild,
}) {
  if (isOwnerRow) return TripParticipantRoleChipKind.owner;
  if (isAdmin && isClaimed) return TripParticipantRoleChipKind.admin;
  if (!isClaimed && isChild) return TripParticipantRoleChipKind.childPlanned;
  if (!isClaimed) return TripParticipantRoleChipKind.planned;
  return null;
}

/// Name shown in participant rows when the child marker is already in the avatar/chip.
String tripParticipantVisibleName(String displayLabel, {required bool isChild}) {
  if (!isChild) return displayLabel;
  return stripTripMemberChildLabelPrefix(displayLabel);
}

class TripParticipantNameAndChips extends StatelessWidget {
  const TripParticipantNameAndChips({
    super.key,
    required this.displayLabel,
    required this.isOwnParticipantRow,
    required this.isOwnerRow,
    required this.isAdmin,
    required this.isClaimed,
    required this.isChild,
    this.nameStyle,
  });

  final String displayLabel;
  final bool isOwnParticipantRow;
  final bool isOwnerRow;
  final bool isAdmin;
  final bool isClaimed;
  final bool isChild;
  final TextStyle? nameStyle;

  @override
  Widget build(BuildContext context) {
    final roleChip = roleChipKindForParticipant(
      isOwnerRow: isOwnerRow,
      isAdmin: isAdmin,
      isClaimed: isClaimed,
      isChild: isChild,
    );
    final chips = <TripParticipantRoleChipKind>[
      if (isOwnParticipantRow) TripParticipantRoleChipKind.you,
      if (roleChip != null) roleChip,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tripParticipantVisibleName(displayLabel, isChild: isChild),
          style: nameStyle ??
              const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: NeonPalette.deep,
              ),
        ),
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final chip in chips) TripParticipantRoleChip(kind: chip),
              ],
            ),
          ),
      ],
    );
  }
}

Widget _buildNeonParticipantProfileBadge({
  required String displayLabel,
  Map<String, dynamic>? profileData,
  required double size,
}) {
  final initial = avatarInitialFromDisplayLabel(displayLabel);
  final fallback = Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: NeonPalette.participantsAvatarBg,
      shape: BoxShape.circle,
    ),
    child: Text(
      initial,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: NeonPalette.primary,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
        height: 1.0,
      ),
    ),
  );

  final photoUrl = tripMemberStoredProfileBadgeUrl(profileData);
  if (photoUrl.isEmpty) {
    return fallback;
  }

  return SizedBox(
    width: size,
    height: size,
    child: ClipOval(
      child: Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    ),
  );
}

class TripParticipantAvatar extends StatelessWidget {
  const TripParticipantAvatar({
    super.key,
    required this.displayLabel,
    required this.isClaimed,
    required this.isChild,
    required this.isOwnerRow,
    required this.isAdmin,
    this.profileData,
    this.size = 40,
  });

  final String displayLabel;
  final bool isClaimed;
  final bool isChild;
  final bool isOwnerRow;
  final bool isAdmin;
  final Map<String, dynamic>? profileData;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badgeSize = size >= 48 ? 18.0 : 16.0;

    Widget avatarContent;
    if (isChild) {
      avatarContent = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: NeonPalette.participantsAvatarBg,
          shape: BoxShape.circle,
        ),
        child: TripChildCareIcon(
          boxed: false,
          iconSize: size * 0.55,
        ),
      );
    } else if (isClaimed) {
      avatarContent = _buildNeonParticipantProfileBadge(
        displayLabel: displayLabel,
        profileData: profileData,
        size: size,
      );
    } else {
      avatarContent = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: NeonPalette.participantsAvatarBg,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person_outline,
          size: size * 0.55,
          color: NeonPalette.outline,
        ),
      );
    }

    Widget? roleBadge;
    if (isOwnerRow) {
      roleBadge = _RoleMicroBadge(
        size: badgeSize,
        background: NeonPalette.primary,
        icon: Icons.star_rounded,
        borderColor: NeonPalette.surface,
      );
    } else if (isAdmin && isClaimed) {
      roleBadge = _RoleMicroBadge(
        size: badgeSize,
        background: NeonPalette.participantsAdminBadgeBg,
        icon: Icons.shield_rounded,
        borderColor: NeonPalette.surface,
      );
    }

    if (roleBadge == null) {
      return SizedBox(width: size, height: size, child: avatarContent);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatarContent,
          Positioned(right: -2, bottom: -2, child: roleBadge),
        ],
      ),
    );
  }
}

class _RoleMicroBadge extends StatelessWidget {
  const _RoleMicroBadge({
    required this.size,
    required this.background,
    required this.icon,
    required this.borderColor,
  });

  final double size;
  final Color background;
  final IconData icon;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Icon(icon, size: size * 0.58, color: Colors.white),
    );
  }
}

class TripParticipantRowCard extends StatelessWidget {
  const TripParticipantRowCard({
    super.key,
    required this.displayLabel,
    required this.isOwnParticipantRow,
    required this.isOwnerRow,
    required this.isAdmin,
    required this.isClaimed,
    required this.isChild,
    this.profileData,
    required this.onTap,
  });

  final String displayLabel;
  final bool isOwnParticipantRow;
  final bool isOwnerRow;
  final bool isAdmin;
  final bool isClaimed;
  final bool isChild;
  final Map<String, dynamic>? profileData;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: NeonPalette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: NeonPalette.primary.withValues(alpha: 0.08),
        highlightColor: NeonPalette.primary.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 4, 11),
          child: Row(
            children: [
              TripParticipantAvatar(
                displayLabel: displayLabel,
                isClaimed: isClaimed,
                isChild: isChild,
                isOwnerRow: isOwnerRow,
                isAdmin: isAdmin,
                profileData: profileData,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TripParticipantNameAndChips(
                  displayLabel: displayLabel,
                  isOwnParticipantRow: isOwnParticipantRow,
                  isOwnerRow: isOwnerRow,
                  isAdmin: isAdmin,
                  isClaimed: isClaimed,
                  isChild: isChild,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: NeonPalette.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripParticipantSheetAction {
  const TripParticipantSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.showChevron = false,
    this.filledIcon = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? iconColor;
  final bool showChevron;
  final bool filledIcon;
  final bool danger;
  final VoidCallback onTap;
}

Future<void> showTripParticipantActionSheet({
  required BuildContext context,
  required String displayLabel,
  required bool isOwnParticipantRow,
  required bool isOwnerRow,
  required bool isAdmin,
  required bool isClaimed,
  required bool isChild,
  Map<String, dynamic>? profileData,
  required List<TripParticipantSheetAction> actions,
}) {

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.34),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Spacer(),
            Material(
              color: NeonPalette.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              elevation: 16,
              shadowColor: Colors.black.withValues(alpha: 0.18),
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Row(
                      children: [
                        TripParticipantAvatar(
                          displayLabel: displayLabel,
                          isClaimed: isClaimed,
                          isChild: isChild,
                          isOwnerRow: isOwnerRow,
                          isAdmin: isAdmin,
                          profileData: profileData,
                          size: 48,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TripParticipantNameAndChips(
                            displayLabel: displayLabel,
                            isOwnParticipantRow: isOwnParticipantRow,
                            isOwnerRow: isOwnerRow,
                            isAdmin: isAdmin,
                            isClaimed: isClaimed,
                            isChild: isChild,
                            nameStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: NeonPalette.deep,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: NeonPalette.divider),
                  if (actions.isNotEmpty)
                    for (var index = 0; index < actions.length; index++)
                      _SheetActionTile(
                        action: actions[index],
                        showDivider: index > 0,
                      ),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SheetActionTile extends StatelessWidget {
  const _SheetActionTile({
    required this.action,
    required this.showDivider,
  });

  final TripParticipantSheetAction action;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final iconColor = action.iconColor ??
        (action.danger ? NeonPalette.accent : NeonPalette.onSurfaceVariant);
    final labelColor = action.danger ? NeonPalette.accent : NeonPalette.deep;

    return Column(
      children: [
        if (showDivider) Divider(height: 1, color: NeonPalette.divider),
        InkWell(
          onTap: action.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Icon(
                    action.icon,
                    size: 22,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.label,
                        style: TextStyle(
                          fontSize: 15,
                          color: labelColor,
                        ),
                      ),
                      if (action.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          action.subtitle!,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: NeonPalette.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action.showChevron)
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: NeonPalette.outline,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class TripParticipantGroupCard extends StatelessWidget {
  const TripParticipantGroupCard({
    super.key,
    required this.label,
    required this.metaLine,
    required this.memberNamesLine,
    this.onEdit,
    this.onDelete,
    this.isDeleting = false,
  });

  final String label;
  final String metaLine;
  final String memberNamesLine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isDeleting;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: NeonPalette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: NeonPalette.participantsGroupIconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.group_rounded,
                  size: 24,
                  color: NeonPalette.participantsGroupIconFg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: NeonPalette.deep,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metaLine,
                      style: const TextStyle(
                        fontSize: 13,
                        color: NeonPalette.onSurfaceVariant,
                      ),
                    ),
                    if (memberNamesLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        memberNamesLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: NeonPalette.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onEdit != null || onDelete != null)
                Column(
                  children: [
                    if (onEdit != null)
                      IconButton(
                        tooltip: AppLocalizations.of(context)!.commonEdit,
                        onPressed: isDeleting ? null : onEdit,
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 20,
                          color: NeonPalette.onSurfaceVariant,
                        ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          maximumSize: const Size(36, 36),
                        ),
                      ),
                    if (onDelete != null)
                      IconButton(
                        tooltip: AppLocalizations.of(context)!
                            .tripParticipantsRemoveAction,
                        onPressed: isDeleting ? null : onDelete,
                        icon: isDeleting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: NeonPalette.accent,
                              ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          maximumSize: const Size(36, 36),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
    );
  }
}

class TripParticipantsGroupsEmpty extends StatelessWidget {
  const TripParticipantsGroupsEmpty({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.groups_outlined,
              size: 52,
              color: NeonPalette.divider,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: NeonPalette.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TripParticipantsInputShell extends StatefulWidget {
  const TripParticipantsInputShell({
    super.key,
    this.icon,
    required this.child,
    this.height = 44,
  });

  final IconData? icon;
  final Widget child;
  final double height;

  @override
  State<TripParticipantsInputShell> createState() =>
      _TripParticipantsInputShellState();
}

class _TripParticipantsInputShellState extends State<TripParticipantsInputShell> {
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocus);

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: NeonPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused ? NeonPalette.primary : NeonPalette.divider,
          width: focused ? 2 : 1.5,
        ),
      ),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: 18,
              color: focused ? NeonPalette.primary : NeonPalette.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class TripParticipantsDialogShell extends StatelessWidget {
  const TripParticipantsDialogShell({
    super.key,
    this.title,
    required this.child,
    required this.actions,
  });

  final String? title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NeonPalette.surface,
      elevation: 8,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null && title!.isNotEmpty) ...[
                Text(
                  title!,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: NeonPalette.deep,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Flexible(child: child),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextButton tripParticipantsDialogButton({
  required BuildContext context,
  required String label,
  required VoidCallback onPressed,
  bool primary = false,
  bool danger = false,
}) {
  final color = danger
      ? NeonPalette.accent
      : primary
          ? NeonPalette.primary
          : NeonPalette.onSurfaceVariant;
  return TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    child: Text(label),
  );
}

class TripParticipantRemoveDialogHeader extends StatelessWidget {
  const TripParticipantRemoveDialogHeader({
    super.key,
    required this.displayLabel,
    required this.isOwnerRow,
    required this.isAdmin,
    required this.isClaimed,
    required this.isChild,
    this.profileData,
  });

  final String displayLabel;
  final bool isOwnerRow;
  final bool isAdmin;
  final bool isClaimed;
  final bool isChild;
  final Map<String, dynamic>? profileData;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: NeonPalette.participantsDangerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NeonPalette.participantsDangerBorder),
      ),
      child: Row(
        children: [
          TripParticipantAvatar(
            displayLabel: displayLabel,
            isClaimed: isClaimed,
            isChild: isChild,
            isOwnerRow: isOwnerRow,
            isAdmin: isAdmin,
            profileData: profileData,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TripParticipantNameAndChips(
              displayLabel: displayLabel,
              isOwnParticipantRow: false,
              isOwnerRow: isOwnerRow,
              isAdmin: isAdmin,
              isClaimed: isClaimed,
              isChild: isChild,
              nameStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: NeonPalette.deep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only parts field styling for the group editor (value remains editable
/// via controller in the parent dialog).
class TripParticipantsPartsField extends StatelessWidget {
  const TripParticipantsPartsField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.helperText,
  });

  final TextEditingController controller;
  final String? helperText;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TripParticipantsInputShell(
          icon: Icons.pie_chart_outline,
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: NeonPalette.deep,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (helperText != null && helperText!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            helperText!,
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: NeonPalette.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
