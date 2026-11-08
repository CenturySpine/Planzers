import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/shopping/data/shopping_category.dart';
import 'package:planerz/l10n/app_localizations.dart';

void main() {
  final reference = (jsonDecode(
    File('liste_categories_courses.json').readAsStringSync(),
  )['categories'] as List)
      .cast<Map<String, dynamic>>();

  test('uses the categories of the AI consolidation, in the same order', () {
    expect(
      kShoppingCategoryIds,
      reference.map((category) => category['id']).toList(),
    );
  });

  test('names every category like the AI consolidation does', () {
    for (final (locale, key) in [
      (const Locale('fr'), 'fr'),
      (const Locale('en'), 'en')
    ]) {
      final l10n = lookupAppLocalizations(locale);
      for (final category in reference) {
        expect(
          shoppingCategoryLabel(l10n, category['id'] as String),
          category[key],
          reason: '${category['id']} ($key)',
        );
      }
    }
  });

  test('keeps only known category ids', () {
    expect(knownShoppingCategoryId(' boissons '), 'boissons');
    expect(knownShoppingCategoryId('999'), isNull);
    expect(knownShoppingCategoryId(''), isNull);
    expect(knownShoppingCategoryId(null), isNull);
  });
}
