import 'package:cloud_firestore/cloud_firestore.dart';

/// Unit types for shopping item quantities.
enum ShoppingUnit {
  unit,
  grams,
  kilograms;

  String get label => switch (this) {
        ShoppingUnit.unit => 'unité',
        ShoppingUnit.grams => 'g',
        ShoppingUnit.kilograms => 'kg',
      };

  String get firestoreValue => switch (this) {
        ShoppingUnit.unit => 'unit',
        ShoppingUnit.grams => 'g',
        ShoppingUnit.kilograms => 'kg',
      };

  static ShoppingUnit fromFirestore(dynamic raw) {
    final s = (raw is String ? raw : raw?.toString() ?? '').trim().toLowerCase();
    for (final e in ShoppingUnit.values) {
      if (e.firestoreValue == s) return e;
    }
    return ShoppingUnit.unit;
  }
}

/// A shopping list item for a trip
/// (`trips/{tripId}/shoppingItems/{itemId}`).
class ShoppingItem {
  ShoppingItem({
    required this.id,
    required this.label,
    required this.checked,
    required this.quantityValue,
    required this.quantityUnit,
    required this.createdAt,
    this.order = 0,
    this.createdBy,
  });

  final String id;
  final String label;
  final bool checked;
  final double quantityValue;
  final ShoppingUnit quantityUnit;
  final DateTime createdAt;
  final int order;
  final String? createdBy;

  factory ShoppingItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};

    final createdAtRaw = data['createdAt'];
    final createdAt = switch (createdAtRaw) {
      Timestamp ts => ts.toDate(),
      String s => DateTime.tryParse(s) ?? DateTime.now(),
      _ => DateTime.now(),
    };

    final quantityRaw = data['quantityValue'];
    final quantityValue = switch (quantityRaw) {
      num n => n.toDouble(),
      _ => 1.0,
    };

    final orderRaw = data['order'];
    final order = switch (orderRaw) {
      int n => n,
      num n => n.toInt(),
      _ => 0,
    };

    final checkedRaw = data['checked'];
    final checked = checkedRaw is bool
        ? checkedRaw
        : checkedRaw is String
            ? checkedRaw.toLowerCase() == 'true'
            : false;

    return ShoppingItem(
      id: doc.id,
      label: (data['label'] as String?)?.trim() ?? '',
      checked: checked,
      quantityValue: quantityValue,
      quantityUnit: ShoppingUnit.fromFirestore(data['quantityUnit']),
      createdAt: createdAt,
      order: order,
      createdBy: (data['createdBy'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toMap() => {
        'label': label.trim(),
        'checked': checked,
        'quantityValue': quantityValue,
        'quantityUnit': quantityUnit.firestoreValue,
        'order': order,
      };
}
