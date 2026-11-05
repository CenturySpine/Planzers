import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/expenses/data/expense_attachment.dart';
import 'package:planerz/features/expenses/presentation/expense_attachments_section.dart';
import 'package:planerz/l10n/app_localizations.dart';

Uint8List _tinyJpeg() =>
    img.encodeJpg(img.Image(width: 4, height: 4), quality: 80);

Widget _host(Widget child) {
  return MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  test('receipts are stored with their expense, beside their thumbnail', () {
    expect(
      expenseAttachmentStoragePath('t1', 'e1', 'a1'),
      'trips/t1/expenses/e1/a1.jpg',
    );
    expect(
      expenseAttachmentThumbStoragePath('t1', 'e1', 'a1'),
      'trips/t1/expenses/e1/a1_thumb.jpg',
    );
  });

  test('receipts are listed oldest first, those being recorded last', () {
    final attachments = [
      const ExpenseAttachment(id: 'pending', url: 'u', thumbUrl: 't'),
      ExpenseAttachment(
        id: 'newer',
        url: 'u',
        thumbUrl: 't',
        createdAt: DateTime(2025, 6, 2),
      ),
      ExpenseAttachment(
        id: 'older',
        url: 'u',
        thumbUrl: 't',
        createdAt: DateTime(2025, 6, 1),
      ),
    ]..sort(compareExpenseAttachments);
    expect(
      attachments.map((a) => a.id),
      ['older', 'newer', 'pending'],
    );
  });

  testWidgets('picked receipts can be removed before saving', (tester) async {
    final removed = <int>[];
    await tester.pumpWidget(
      _host(
        PendingExpenseAttachments(
          photos: [_tinyJpeg(), _tinyJpeg()],
          onAdd: null,
          onRemove: removed.add,
        ),
      ),
    );
    expect(find.text('Justificatifs'), findsOneWidget);
    // Limit reached: no add button.
    expect(find.byIcon(PhosphorIconsRegular.plus), findsNothing);
    await tester.tap(find.byIcon(PhosphorIconsRegular.x).last);
    expect(removed, [1]);
  });

  testWidgets('receipts can be added while under the limit', (tester) async {
    var added = 0;
    await tester.pumpWidget(
      _host(
        PendingExpenseAttachments(
          photos: const [],
          onAdd: () => added++,
          onRemove: (_) {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('Ajouter un justificatif'));
    expect(added, 1);
  });

  testWidgets('picked receipts stay while saving', (tester) async {
    await tester.pumpWidget(
      _host(
        PendingExpenseAttachments(
          photos: [_tinyJpeg()],
          onAdd: null,
          onRemove: null,
        ),
      ),
    );
    expect(find.byIcon(PhosphorIconsRegular.x), findsNothing);
  });
}
