import 'dart:js_interop';
import 'dart:typed_data';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';

// Helpers defined in web/vendor/zxing/planerz_barcode.js.
@JS('planerzBarcode.ensureLoaded')
external JSPromise<JSAny?> _ensureLoaded();

@JS('planerzBarcode.decodeImage')
external JSPromise<_DecodedBarcode?> _decodeImage(
  JSUint8Array bytes,
  String mimeType,
);

extension type _DecodedBarcode._(JSObject _) implements JSObject {
  external String? get format;
  external String? get text;
}

/// ZXing JS format names → [BarcodeFormat] names (the stored format).
const Map<String, BarcodeFormat> _formatsByZxingName = {
  'QR_CODE': BarcodeFormat.qrCode,
  'AZTEC': BarcodeFormat.aztec,
  'PDF_417': BarcodeFormat.pdf417,
  'DATA_MATRIX': BarcodeFormat.dataMatrix,
  'CODE_128': BarcodeFormat.code128,
  'CODE_39': BarcodeFormat.code39,
  'CODE_93': BarcodeFormat.code93,
  'CODABAR': BarcodeFormat.codabar,
  'EAN_13': BarcodeFormat.ean13,
  'EAN_8': BarcodeFormat.ean8,
  'UPC_A': BarcodeFormat.upcA,
  'UPC_E': BarcodeFormat.upcE,
  'ITF': BarcodeFormat.itf14,
};

Future<WalletBarcode?> decodeWalletBarcodeFromImage({
  required Uint8List bytes,
  required String contentType,
  String? filePath,
}) async {
  try {
    final decoded = await _decodeImage(bytes.toJS, contentType).toDart;
    final payload = decoded?.text ?? '';
    if (decoded == null || payload.isEmpty) return null;
    final format = _formatsByZxingName[decoded.format] ?? BarcodeFormat.unknown;
    return WalletBarcode(format: format.name, payload: payload);
  } catch (_) {
    return null;
  }
}

Future<void> prepareWalletBarcodeScanner() async {
  await _ensureLoaded().toDart;
  // Same bundled library for the live camera: no CDN, works with the
  // offline cache, identical formats on every browser.
  MobileScannerPlatform.instance
    ..setWebBarcodeReader(WebBarcodeReader.zxingJs)
    ..setBarcodeLibraryScriptUrl('vendor/zxing/zxing-library-0.23.0.min.js');
}
