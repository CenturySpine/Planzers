import 'dart:typed_data';

import 'package:planerz/features/wallet/data/wallet_document.dart';

import 'wallet_barcode_decoder_stub.dart'
    if (dart.library.io) 'wallet_barcode_decoder_io.dart'
    if (dart.library.js_interop) 'wallet_barcode_decoder_web.dart' as impl;

/// Looks for a QR code / barcode in an image (screenshot, photo).
/// Returns null when none is found. [filePath] is used on native platforms,
/// [bytes] on the web.
Future<WalletBarcode?> decodeWalletBarcodeFromImage({
  required Uint8List bytes,
  required String contentType,
  String? filePath,
}) {
  return impl.decodeWalletBarcodeFromImage(
    bytes: bytes,
    contentType: contentType,
    filePath: filePath,
  );
}

/// Must complete before starting the camera scanner (web: loads the bundled
/// barcode library the scanner relies on).
Future<void> prepareWalletBarcodeScanner() => impl.prepareWalletBarcodeScanner();
