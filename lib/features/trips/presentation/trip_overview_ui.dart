import 'package:flutter/material.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';

class TripOverviewParticipantPreviewEntry {
  const TripOverviewParticipantPreviewEntry({
    required this.initial,
    required this.photoUrl,
  });

  final String initial;
  final String photoUrl;
}

class TripOverviewSectionHeader extends StatelessWidget {
  const TripOverviewSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: NeonPalette.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class TripOverviewBanner extends StatelessWidget {
  const TripOverviewBanner({
    super.key,
    required this.title,
    this.destination,
    this.dateLabel,
    required this.imageUrl,
    required this.busy,
    this.onPick,
    this.onPhotoMenu,
    required this.emptyLabel,
    required this.addPhotoLabel,
  });

  final String title;
  final String? destination;
  final String? dateLabel;
  final String imageUrl;
  final bool busy;
  final VoidCallback? onPick;
  final VoidCallback? onPhotoMenu;
  final String emptyLabel;
  final String addPhotoLabel;

  static const double _height = 196;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: _height,
        decoration: BoxDecoration(
          boxShadow: NeonPalette.elev1,
          gradient: hasImage
              ? null
              : LinearGradient(
                  begin: const Alignment(-0.5, -1),
                  end: const Alignment(1, 1),
                  colors: NeonPalette.overviewBannerGradient,
                  stops: const [0, 0.6, 1],
                ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPick,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasImage)
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: const Alignment(-0.5, -1),
                            end: const Alignment(1, 1),
                            colors: NeonPalette.overviewBannerGradient,
                            stops: const [0, 0.6, 1],
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              size: 42, color: Colors.white70),
                        ),
                      );
                    },
                  ),
                if (!hasImage && !busy)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 36,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          onPick == null ? emptyLabel : addPhotoLabel,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        NeonPalette.deep.withValues(alpha: 0.86),
                        NeonPalette.deep.withValues(alpha: 0.42),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                if (onPhotoMenu != null)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      color: const Color(0x750F0A28),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: busy ? null : onPhotoMenu,
                        customBorder: const CircleBorder(),
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: busy
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.photo_camera_outlined,
                                  size: 20,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                  ),
                if (busy && hasImage)
                  const ColoredBox(
                    color: Color(0x42000000),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (destination != null && destination!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                destination!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (dateLabel != null && dateLabel!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.date_range_outlined,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                dateLabel!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
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

class TripOverviewActionPills extends StatelessWidget {
  const TripOverviewActionPills({
    super.key,
    required this.announcementsLabel,
    required this.announcementsAlertCount,
    required this.onAnnouncementsTap,
    this.photosLabel,
    this.onPhotosTap,
  });

  final String announcementsLabel;
  final int announcementsAlertCount;
  final VoidCallback onAnnouncementsTap;
  final String? photosLabel;
  final VoidCallback? onPhotosTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TripOverviewActionPill(
            label: announcementsLabel,
            icon: Icons.campaign_outlined,
            alertCount: announcementsAlertCount,
            onTap: onAnnouncementsTap,
          ),
        ),
        if (photosLabel != null && onPhotosTap != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _TripOverviewActionPill(
              label: photosLabel!,
              icon: Icons.photo_library_outlined,
              onTap: onPhotosTap!,
            ),
          ),
        ],
      ],
    );
  }
}

class _TripOverviewActionPill extends StatelessWidget {
  const _TripOverviewActionPill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.alertCount = 0,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int alertCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.primaryTint,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: NeonPalette.primarySoft),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: NeonPalette.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: NeonPalette.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (alertCount > 0) ...[
                const SizedBox(width: 6),
                Badge.count(
                  count: alertCount,
                  child: const SizedBox(width: 8, height: 8),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TripOverviewLinkCard extends StatelessWidget {
  const TripOverviewLinkCard({
    super.key,
    required this.url,
    required this.preview,
    this.trailing,
    required this.onOpen,
  });

  final String url;
  final Map<String, dynamic> preview;
  final Widget? trailing;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final previewTitle = ((preview['title'] as String?) ?? '').trim();
    final primaryText = previewTitle.isNotEmpty ? previewTitle : url;

    return Material(
      color: NeonPalette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: NeonPalette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              LinkPreviewThumbnail(preview: preview, size: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NeonPalette.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: NeonPalette.accent,
                      ),
                    ),
                    if (previewTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: NeonPalette.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ] else
                const Icon(
                  Icons.open_in_new,
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

class TripOverviewParticipantsCard extends StatelessWidget {
  const TripOverviewParticipantsCard({
    super.key,
    required this.countLabel,
    required this.participantsLabel,
    required this.participants,
    required this.onCardTap,
    required this.onManageTap,
    this.inviteCodeLabel,
    this.inviteCode,
    this.shareCodeLabel,
    this.onShareCodeTap,
    this.shareCodeBusy = false,
  });

  final String countLabel;
  final String participantsLabel;
  final List<TripOverviewParticipantPreviewEntry> participants;
  final VoidCallback onCardTap;
  final VoidCallback onManageTap;
  final String? inviteCodeLabel;
  final String? inviteCode;
  final String? shareCodeLabel;
  final VoidCallback? onShareCodeTap;
  final bool shareCodeBusy;

  @override
  Widget build(BuildContext context) {
    final showInviteRow =
        inviteCodeLabel != null && onShareCodeTap != null;

    return Material(
      color: NeonPalette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: NeonPalette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onCardTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            countLabel,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: NeonPalette.deep,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              participantsLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: NeonPalette.deep,
                              ),
                            ),
                          ),
                          Material(
                            color: NeonPalette.nameEditPillBackground,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: onManageTap,
                              customBorder: const CircleBorder(),
                              child: const SizedBox(
                                width: 36,
                                height: 36,
                                child: Icon(
                                  Icons.assignment_ind_outlined,
                                  size: 20,
                                  color: NeonPalette.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TripOverviewParticipantAvatars(participants: participants),
                    ],
                  ),
                ),
              ),
            ),
            if (showInviteRow) ...[
              const Divider(height: 1, color: NeonPalette.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.vpn_key_outlined,
                      size: 18,
                      color: NeonPalette.primary,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      inviteCodeLabel!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: NeonPalette.text700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        inviteCode ?? '···',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: NeonPalette.primary,
                          letterSpacing: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: shareCodeBusy ? null : onShareCodeTap,
                      icon: shareCodeBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share, size: 16),
                      label: Text(shareCodeLabel ?? ''),
                      style: TextButton.styleFrom(
                        foregroundColor: NeonPalette.primary,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
    );
  }
}

class TripOverviewParticipantAvatars extends StatelessWidget {
  const TripOverviewParticipantAvatars({super.key, required this.participants});

  final List<TripOverviewParticipantPreviewEntry> participants;

  static const double _size = 34;
  static const double _overlap = 8;
  static const int _maxVisible = 7;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleCount = participants.length <= _maxVisible
        ? participants.length
        : _maxVisible;
    final remaining = participants.length - visibleCount;
    final itemCount = visibleCount + (remaining > 0 ? 1 : 0);
    final rowWidth =
        _size + (itemCount - 1) * (_size - _overlap).clamp(0, _size);

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: rowWidth,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < visibleCount; i++)
              Positioned(
                left: i * (_size - _overlap),
                child: _AvatarBubble(entry: participants[i]),
              ),
            if (remaining > 0)
              Positioned(
                left: visibleCount * (_size - _overlap),
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: NeonPalette.surfaceHighest,
                    shape: BoxShape.circle,
                    border: Border.all(color: NeonPalette.surface, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+$remaining',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: NeonPalette.onSurfaceVariant,
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

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({required this.entry});

  final TripOverviewParticipantPreviewEntry entry;

  static const TextStyle _initialStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: NeonPalette.primary,
  );

  Widget _initialFallback() {
    return ColoredBox(
      color: NeonPalette.participantsAvatarBg,
      child: Center(
        child: Text(entry.initial, style: _initialStyle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = TripOverviewParticipantAvatars._size;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: NeonPalette.surface, width: 2),
      ),
      child: ClipOval(
        child: entry.photoUrl.isEmpty
            ? _initialFallback()
            : Image.network(
                entry.photoUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _initialFallback(),
              ),
      ),
    );
  }
}

class TripOverviewModuleTile extends StatelessWidget {
  const TripOverviewModuleTile({
    super.key,
    required this.label,
    required this.icon,
    required this.countLabel,
    required this.viewLabel,
    required this.tileColor,
    required this.inkColor,
    required this.onTap,
    this.statusText,
    this.alertCount = 0,
  });

  final String label;
  final IconData icon;
  final String countLabel;
  final String viewLabel;
  final Color tileColor;
  final Color inkColor;
  final VoidCallback onTap;
  final String? statusText;
  final int alertCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: NeonPalette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    countLabel,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: inkColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: NeonPalette.deep,
                      ),
                    ),
                  ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: tileColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Badge.count(
                      count: alertCount,
                      isLabelVisible: alertCount > 0,
                      child: Icon(icon, size: 20, color: inkColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    statusText ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: NeonPalette.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        viewLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: inkColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: inkColor, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripOverviewSettingsCard extends StatelessWidget {
  const TripOverviewSettingsCard({super.key, required this.rows});

  final List<TripOverviewSettingsRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NeonPalette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: NeonPalette.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++)
            _TripOverviewSettingsRow(
              data: rows[i],
              showDivider: i > 0,
            ),
        ],
      ),
    );
  }
}

class TripOverviewSettingsRowData {
  const TripOverviewSettingsRowData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

class _TripOverviewSettingsRow extends StatelessWidget {
  const _TripOverviewSettingsRow({
    required this.data,
    required this.showDivider,
  });

  final TripOverviewSettingsRowData data;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final color = data.danger ? NeonPalette.error : NeonPalette.text700;
    final labelColor = data.danger ? NeonPalette.error : NeonPalette.deep;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDivider) const Divider(height: 1, color: NeonPalette.divider),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: data.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Icon(data.icon, size: 22, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      data.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: labelColor,
                      ),
                    ),
                  ),
                  if (!data.danger)
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: NeonPalette.outline,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
