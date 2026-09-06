import 'package:cloud_firestore/cloud_firestore.dart';

/// Origin of a packing-list ("À emporter") item.
///
/// - [self]: added by the traveler themselves; fully editable by them.
/// - [admin]: pushed from a trip organiser's list. Read-only for the
///   traveler except for the check state. Its Firestore document id matches
///   the id of the source item in the organiser's own list, so successive
///   pushes reconcile the list item by item (rename, removal) without ever
///   inflating it with duplicates.
enum PackingItemScope {
  self('self'),
  admin('admin');

  const PackingItemScope(this.value);

  final String value;

  static PackingItemScope fromValue(Object? raw) {
    final s = (raw is String ? raw : '').trim().toLowerCase();
    return s == 'admin' ? PackingItemScope.admin : PackingItemScope.self;
  }
}

/// One line of a traveler's "À emporter" list
/// (`trips/{tripId}/packingLists/{participantId}/items/{itemId}`).
class PackingItem {
  const PackingItem({
    required this.id,
    required this.label,
    required this.checked,
    required this.scope,
    this.createdAt,
  });

  final String id;
  final String label;
  final bool checked;
  final PackingItemScope scope;
  final DateTime? createdAt;

  /// True when the item comes from a pushed organiser list and cannot be
  /// edited or removed by the traveler (only checked/unchecked).
  bool get isFromOrganiser => scope == PackingItemScope.admin;

  factory PackingItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawCreatedAt = data['createdAt'];
    return PackingItem(
      id: doc.id,
      label: (data['label'] as String?)?.trim() ?? '',
      checked: data['checked'] == true,
      scope: PackingItemScope.fromValue(data['scope']),
      createdAt: rawCreatedAt is Timestamp ? rawCreatedAt.toDate() : null,
    );
  }
}

/// Per-traveler activation state of the "À emporter" module
/// (`trips/{tripId}/packingLists/{participantId}`).
///
/// [enabled] is a three-state flag:
/// - `null`  — the traveler never decided; a push may switch it on.
/// - `true`  — the module is shown on the trip overview.
/// - `false` — the traveler explicitly hid it; a later push updates the
///   underlying list but never forces the module back on.
class PackingListConfig {
  const PackingListConfig({this.enabled});

  final bool? enabled;

  bool get isVisible => enabled == true;

  factory PackingListConfig.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    if (!doc.exists) return const PackingListConfig();
    final raw = doc.data()?['enabled'];
    return PackingListConfig(enabled: raw is bool ? raw : null);
  }
}

const Map<String, String> _diacriticFolds = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae',
};

/// Fold used to sort list items alphabetically in a French-friendly way:
/// case-insensitive and accent-insensitive.
String packingItemSortKey(String label) {
  final lower = label.trim().toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_diacriticFolds[ch] ?? ch);
  }
  return buffer.toString();
}
