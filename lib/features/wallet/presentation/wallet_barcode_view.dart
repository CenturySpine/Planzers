import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Stored format name (mobile_scanner `BarcodeFormat.name`) → drawing
/// symbology. Unknown formats fall back to a QR code carrying the same
/// content.
Barcode walletBarcodeSymbology(String format) => switch (format) {
      'aztec' => Barcode.aztec(),
      // Taller rows than the default: flat rows are not read back reliably.
      'pdf417' => Barcode.pdf417(moduleHeight: 3),
      'dataMatrix' => Barcode.dataMatrix(),
      'code128' => Barcode.code128(),
      'code39' => Barcode.code39(),
      'code93' => Barcode.code93(),
      'codabar' => Barcode.codabar(),
      'ean13' => Barcode.ean13(),
      'ean8' => Barcode.ean8(),
      'upcA' => Barcode.upcA(),
      'upcE' => Barcode.upcE(),
      'itf' || 'itf14' || 'itf2of5' => Barcode.itf(),
      _ => Barcode.qrCode(),
    };

/// Black on white, as large as the space allows: what a ticket inspector's
/// reader expects.
class WalletBarcodeView extends StatelessWidget {
  const WalletBarcodeView({super.key, required this.barcode});

  final WalletBarcode barcode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final symbology = walletBarcodeSymbology(barcode.format);
    final isLinear = symbology.name != Barcode.qrCode().name &&
        symbology.name != Barcode.aztec().name &&
        symbology.name != Barcode.dataMatrix().name;
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AspectRatio(
          aspectRatio: isLinear ? 2.5 : 1,
          child: BarcodeWidget(
            barcode: symbology,
            data: barcode.payload,
            color: Colors.black,
            backgroundColor: Colors.white,
            drawText: false,
            errorBuilder: (context, _) => Center(
              child: Text(l10n.walletCodeRenderFailed, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
