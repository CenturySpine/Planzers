import 'package:flutter/material.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripNeonPrefsScreenHead extends StatelessWidget {
  const TripNeonPrefsScreenHead({
    super.key,
    required this.kicker,
    required this.centerTitle,
    required this.subtitle,
    this.icon = Icons.tune,
  });

  final String kicker;
  final String centerTitle;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final trimmed = centerTitle.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: NeonPalette.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  kicker.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: NeonPalette.primary,
                  ),
                ),
              ),
            ],
          ),
          if (trimmed.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '«\u00a0$trimmed\u00a0»',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: NeonPalette.deep,
              ),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: NeonPalette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class TripMemberPreferencesHead extends StatelessWidget {
  const TripMemberPreferencesHead({
    super.key,
    required this.tripName,
  });

  final String tripName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TripNeonPrefsScreenHead(
      kicker: l10n.tripUserPreferencesHeadKicker,
      centerTitle: tripName,
      subtitle: l10n.tripUserPreferencesHeadSubtitle,
    );
  }
}

class TripNeonPrefsNameRow extends StatelessWidget {
  const TripNeonPrefsNameRow({
    super.key,
    required this.leadLabel,
    required this.displayName,
    required this.onEdit,
  });

  final String leadLabel;
  final String displayName;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trimmed = displayName.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                leadLabel,
                style: const TextStyle(
                  fontSize: 14,
                  color: NeonPalette.text700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '«\u00a0${trimmed.isEmpty ? '…' : trimmed}\u00a0»',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: NeonPalette.deep,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onEdit,
          style: TextButton.styleFrom(
            foregroundColor: NeonPalette.primary,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: Text(
            l10n.commonEdit,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class TripMemberPreferencesNameRow extends StatelessWidget {
  const TripMemberPreferencesNameRow({
    super.key,
    required this.displayName,
    required this.onEdit,
  });

  final String displayName;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TripNeonPrefsNameRow(
      leadLabel: l10n.tripUserPreferencesParticipatingAs,
      displayName: displayName,
      onEdit: onEdit,
    );
  }
}
