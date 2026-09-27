import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:planerz/features/wallet/data/wallet_barcode_decoder.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Live camera scan of a QR code / barcode. Pops with the first code read
/// ([WalletBarcode]), or null when the user leaves.
class WalletBarcodeScanPage extends StatefulWidget {
  const WalletBarcodeScanPage({super.key});

  @override
  State<WalletBarcodeScanPage> createState() => _WalletBarcodeScanPageState();
}

class _WalletBarcodeScanPageState extends State<WalletBarcodeScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  bool _prepareFailed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await prepareWalletBarcodeScanner();
      if (!mounted) return;
      await _controller.start();
    } catch (_) {
      if (mounted) setState(() => _prepareFailed = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final barcode = capture.barcodes
        .where((b) => (b.rawValue ?? '').isNotEmpty)
        .firstOrNull;
    if (barcode == null) return;
    _done = true;
    Navigator.of(context).pop(
      WalletBarcode(format: barcode.format.name, payload: barcode.rawValue!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(l10n.walletAddScanCode)),
      body: _prepareFailed
          ? _ScanMessage(text: l10n.walletScanCameraError)
          : MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _ScanMessage(
                text: error.errorCode ==
                        MobileScannerErrorCode.permissionDenied
                    ? l10n.walletScanCameraDenied
                    : l10n.walletScanCameraError,
              ),
            ),
    );
  }
}

class _ScanMessage extends StatelessWidget {
  const _ScanMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
