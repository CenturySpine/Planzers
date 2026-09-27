import 'dart:typed_data';

import 'package:planerz/features/wallet/data/wallet_document.dart';

Future<WalletBarcode?> decodeWalletBarcodeFromImage({
  required Uint8List bytes,
  required String contentType,
  String? filePath,
}) async =>
    null;

Future<void> prepareWalletBarcodeScanner() async {}
