import 'package:flutter/material.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// "Mes documents" — a personal, per-traveler document wallet (tickets, QR
/// codes, booking screenshots...), visible only to its owner. This is a
/// static mockup for now: no real upload/storage is wired yet — the
/// wallet's actual storage design is deferred to a later chantier.
class TripWalletPage extends StatelessWidget {
  const TripWalletPage({super.key, required this.tripId});

  final String tripId;

  static const List<_MockWalletDocument> _mockDocuments = [
    _MockWalletDocument(
      icon: Icons.confirmation_number_outlined,
      name: 'Billet de train.pdf',
      date: '12/10/2026',
    ),
    _MockWalletDocument(
      icon: Icons.qr_code_2_outlined,
      name: 'QR code hôtel.png',
      date: '15/10/2026',
    ),
    _MockWalletDocument(
      icon: Icons.image_outlined,
      name: "Capture réservation.jpg",
      date: '18/10/2026',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        appBar: AppBar(
          title: Text(l10n.tripWalletPageTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: l10n.tripWalletAddDocument,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.tripOverviewTileComingSoon)),
                );
              },
            ),
          ],
        ),
        body: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: _mockDocuments.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final document = _mockDocuments[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      ActivityFilterGroup.trajets.filterLightBgColor,
                  child: Icon(
                    document.icon,
                    color: ActivityFilterGroup.trajets.filterInkColor,
                  ),
                ),
                title: Text(document.name),
                subtitle: Text(document.date),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MockWalletDocument {
  const _MockWalletDocument({
    required this.icon,
    required this.name,
    required this.date,
  });

  final IconData icon;
  final String name;
  final String date;
}
