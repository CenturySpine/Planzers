import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';
import 'package:planerz/features/wallet/data/wallet_barcode_decoder.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';

/// Tickets put their code on the first page(s); looking further would slow
/// the import of long documents for little gain.
const int _maxPagesScanned = 2;

/// Rendering width in pixels: enough for small codes to be readable.
const double _renderWidth = 1600;

/// Looks for a QR code / barcode on the first pages of a PDF: each page is
/// drawn as an image, then read like a screenshot. null when none is found.
Future<WalletBarcode?> decodeWalletBarcodeFromPdf(Uint8List bytes) async {
  PdfDocument? document;
  try {
    await pdfrxFlutterInitialize();
    document = await PdfDocument.openData(bytes);
    final pageCount = document.pages.length;
    for (var i = 0; i < pageCount && i < _maxPagesScanned; i++) {
      final page = document.pages[i];
      final rendered = await page.render(
        fullWidth: _renderWidth,
        fullHeight: _renderWidth * page.height / page.width,
        backgroundColor: 0xffffffff,
      );
      if (rendered == null) continue;
      final ui.Image image;
      try {
        image = await rendered.createImage();
      } finally {
        rendered.dispose();
      }
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) continue;
      final barcode = await decodeWalletBarcodeFromImage(
        bytes: png.buffer.asUint8List(),
        contentType: 'image/png',
      );
      if (barcode != null) return barcode;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    await document?.dispose();
  }
}
