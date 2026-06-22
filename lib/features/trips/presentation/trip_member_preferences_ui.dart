import 'package:flutter/material.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripMemberPreferencesHead extends StatelessWidget {
  const TripMemberPreferencesHead({
    super.key,
    required this.tripName,
  });

  final String tripName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trimmed = tripName.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.tune, size: 15, color: NeonPalette.primary),
              const SizedBox(width: 6),
              Text(
                l10n.tripUserPreferencesHeadKicker.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: NeonPalette.primary,
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
            l10n.tripUserPreferencesHeadSubtitle,
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
    final trimmed = displayName.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.tripUserPreferencesParticipatingAs,
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
