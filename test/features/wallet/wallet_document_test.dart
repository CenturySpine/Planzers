import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_document_category.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';
import 'package:planerz/features/wallet/presentation/wallet_barcode_view.dart';

WalletDocument _doc(String id, {DateTime? eventDate, DateTime? createdAt}) {
  return WalletDocument(
    id: id,
    name: id,
    category: WalletDocumentCategory.other,
    kind: WalletDocumentKind.file,
    eventDate: eventDate,
    createdAt: createdAt,
  );
}

void main() {
  group('compareWalletDocuments', () {
    test('dated documents come first, in chronological order', () {
      final docs = [
        _doc('undated', createdAt: DateTime(2026, 1, 1)),
        _doc('late', eventDate: DateTime(2026, 10, 20)),
        _doc('early', eventDate: DateTime(2026, 10, 12)),
      ]..sort(compareWalletDocuments);
      expect(docs.map((d) => d.id), ['early', 'late', 'undated']);
    });

    test('undated documents keep creation order, pending ones last', () {
      final docs = [
        _doc('pending'),
        _doc('second', createdAt: DateTime(2026, 2, 1)),
        _doc('first', createdAt: DateTime(2026, 1, 1)),
      ]..sort(compareWalletDocuments);
      expect(docs.map((d) => d.id), ['first', 'second', 'pending']);
    });
  });

  test('unknown category falls back to other', () {
    expect(WalletDocumentCategory.fromFirestore('train'),
        WalletDocumentCategory.train);
    expect(WalletDocumentCategory.fromFirestore('spaceship'),
        WalletDocumentCategory.other);
    expect(WalletDocumentCategory.fromFirestore(null),
        WalletDocumentCategory.other);
  });

  test('file extension is lower-cased and mapped to an accepted type', () {
    expect(walletFileExtension('Billet.PDF'), 'pdf');
    expect(walletFileExtension('photo.jpeg'), 'jpeg');
    expect(walletFileExtension('archive'), '');
    expect(walletFileExtension('trailing.'), '');
    expect(walletContentTypeByExtension['pdf'], 'application/pdf');
    expect(walletContentTypeByExtension['html'], isNull);
  });

  test('stored barcode formats are redrawn with the same symbology', () {
    expect(walletBarcodeSymbology('qrCode').name, 'QR-Code');
    expect(walletBarcodeSymbology('aztec').name, 'Aztec');
    expect(walletBarcodeSymbology('pdf417').name, 'PDF417');
    expect(walletBarcodeSymbology('code128').name, 'CODE 128');
    // Unknown formats still show the content, as a QR code.
    expect(walletBarcodeSymbology('unknown').name, 'QR-Code');
  });
}
