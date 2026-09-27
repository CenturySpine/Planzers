import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:planerz/features/wallet/data/wallet_document_category.dart';

/// File types accepted in the wallet (must match `storage.rules` and
/// `firestore.rules`). Browsers can display all of them except HEIC outside
/// Safari, which is then opened as a plain file.
const Map<String, String> walletContentTypeByExtension = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

const int walletMaxFileSizeBytes = 15 * 1024 * 1024;
const int walletMaxDocumentsPerTrip = 50;
const int walletMaxNameLength = 80;

enum WalletDocumentKind {
  file,
  barcode;

  static WalletDocumentKind fromFirestore(Object? raw) =>
      raw == barcode.name ? barcode : file;
}

class WalletDocumentFile {
  const WalletDocumentFile({
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    required this.originalFileName,
  });

  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final String originalFileName;

  bool get isPdf => contentType == 'application/pdf';
  bool get isImage => contentType.startsWith('image/');

  static WalletDocumentFile? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final storagePath = (raw['storagePath'] as String?)?.trim() ?? '';
    if (storagePath.isEmpty) return null;
    return WalletDocumentFile(
      storagePath: storagePath,
      contentType: (raw['contentType'] as String?)?.trim() ?? '',
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
      originalFileName: (raw['originalFileName'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'storagePath': storagePath,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        'originalFileName': originalFileName,
      };
}

/// Content of a scanned QR code / barcode; the code is redrawn from it.
class WalletBarcode {
  const WalletBarcode({required this.format, required this.payload});

  final String format;
  final String payload;

  static WalletBarcode? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final payload = raw['payload'] as String? ?? '';
    if (payload.isEmpty) return null;
    return WalletBarcode(
      format: (raw['format'] as String?)?.trim() ?? '',
      payload: payload,
    );
  }

  Map<String, dynamic> toMap() => {'format': format, 'payload': payload};
}

/// A personal travel document, stored under
/// `trips/{tripId}/travelerModules/{uid}/walletDocuments/{id}` and visible
/// only to its owner.
class WalletDocument {
  const WalletDocument({
    required this.id,
    required this.name,
    required this.category,
    required this.kind,
    this.eventDate,
    this.file,
    this.barcode,
    this.activityId,
    this.createdAt,
  });

  final String id;
  final String name;
  final WalletDocumentCategory category;
  final WalletDocumentKind kind;
  final DateTime? eventDate;
  final WalletDocumentFile? file;
  final WalletBarcode? barcode;

  /// Planning activity this document belongs to (only its owner sees the
  /// link). May point at an activity deleted since.
  final String? activityId;
  final DateTime? createdAt;

  factory WalletDocument.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return WalletDocument(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      category: WalletDocumentCategory.fromFirestore(data['category']),
      kind: WalletDocumentKind.fromFirestore(data['kind']),
      eventDate: (data['eventDate'] as Timestamp?)?.toDate(),
      file: WalletDocumentFile.fromMap(data['file']),
      barcode: WalletBarcode.fromMap(data['barcode']),
      activityId: switch ((data['activityId'] as String?)?.trim()) {
        final String id when id.isNotEmpty => id,
        _ => null,
      },
      // Pending server timestamps read as null until the write is confirmed.
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Chronological order: dated documents first (by date), then undated ones
/// by creation (newest last).
int compareWalletDocuments(WalletDocument a, WalletDocument b) {
  final aDate = a.eventDate;
  final bDate = b.eventDate;
  if (aDate != null && bDate != null) {
    final byDate = aDate.compareTo(bDate);
    if (byDate != 0) return byDate;
  } else if (aDate != null) {
    return -1;
  } else if (bDate != null) {
    return 1;
  }
  final aCreated = a.createdAt;
  final bCreated = b.createdAt;
  if (aCreated != null && bCreated != null) {
    final byCreation = aCreated.compareTo(bCreated);
    if (byCreation != 0) return byCreation;
  } else if (aCreated == null && bCreated != null) {
    return 1;
  } else if (aCreated != null && bCreated == null) {
    return -1;
  }
  return a.id.compareTo(b.id);
}
