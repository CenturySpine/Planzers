import 'dart:typed_data';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';

Future<WalletBarcode?> decodeWalletBarcodeFromImage({
  required Uint8List bytes,
  required String contentType,
  String? filePath,
}) async {
  if (filePath == null || filePath.isEmpty) return null;
  final controller = MobileScannerController(autoStart: false);
  try {
    final capture = await controller.analyzeImage(filePath);
    final barcode = capture?.barcodes
        .where((b) => (b.rawValue ?? '').isNotEmpty)
        .firstOrNull;
    if (barcode == null) return null;
    return WalletBarcode(format: barcode.format.name, payload: barcode.rawValue!);
  } catch (_) {
    return null;
  } finally {
    await controller.dispose();
  }
}

Future<void> prepareWalletBarcodeScanner() async {}
