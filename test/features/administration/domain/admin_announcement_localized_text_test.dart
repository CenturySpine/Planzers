import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/administration/domain/admin_announcement_localized_text.dart';

void main() {
  test('returns exact locale section when exact locale exists', () {
    const rawText = '''
[fr-FR]
Bonjour tout le monde

[en-US]
Hello everyone
''';

    final resolvedText = resolveAdminAnnouncementText(
      rawText,
      const Locale('fr', 'FR'),
    );

    expect(resolvedText, 'Bonjour tout le monde');
  });

  test('falls back to language-only section when exact locale is missing', () {
    const rawText = '''
[fr]
Bonjour les amis

[en-US]
Hello everyone
''';

    final resolvedText = resolveAdminAnnouncementText(
      rawText,
      const Locale('fr', 'FR'),
    );

    expect(resolvedText, 'Bonjour les amis');
  });

  test('falls back to first section when locale does not match', () {
    const rawText = '''
[en-US]
Hello everyone

[fr-FR]
Bonjour tout le monde
''';

    final resolvedText = resolveAdminAnnouncementText(
      rawText,
      const Locale('es', 'ES'),
    );

    expect(resolvedText, 'Hello everyone');
  });

  test('returns raw text when no locale headers are present', () {
    const rawText = 'Annonce sans section localisee';

    final resolvedText = resolveAdminAnnouncementText(
      rawText,
      const Locale('fr', 'FR'),
    );

    expect(resolvedText, rawText);
  });

  test('parses locale headers case-insensitively with underscore separators',
      () {
    const rawText = '''
[FR_fr]
Bonjour en francais

[EN_us]
Hello in English
''';

    final resolvedText = resolveAdminAnnouncementText(
      rawText,
      const Locale('fr', 'FR'),
    );

    expect(resolvedText, 'Bonjour en francais');
  });

  test('assembleAdminAnnouncementMultilingualText builds canonical sections',
      () {
    final assembled = assembleAdminAnnouncementMultilingualText(
      'Salut',
      'Hi',
    );
    expect(
      assembled,
      '[fr-FR]\nSalut\n\n[en-US]\nHi',
    );
  });

  test(
      'assembleAdminAnnouncementMultilingualText omits empty locale bodies',
      () {
    expect(
      assembleAdminAnnouncementMultilingualText('Salut', ''),
      '[fr-FR]\nSalut',
    );
    expect(
      assembleAdminAnnouncementMultilingualText('', 'Hi'),
      '[en-US]\nHi',
    );
    expect(assembleAdminAnnouncementMultilingualText('', ''), '');
  });

  test(
      'falls back when matched locale section is empty but another is filled',
      () {
    const rawText = '''
[fr-FR]
Bonjour

[en-US]

''';

    expect(
      resolveAdminAnnouncementText(rawText, const Locale('en', 'US')),
      'Bonjour',
    );
  });

  test(
      'falls back to first non-empty section when locale unmatched and lead '
      'section is empty',
      () {
    const rawText = '''
[fr-FR]

[en-US]
Hello
''';

    expect(
      resolveAdminAnnouncementText(rawText, const Locale('es', 'ES')),
      'Hello',
    );
  });

  test(
      'splitAdminAnnouncementForEditing maps stored sections to editors',
      () {
    const rawText = '''
[fr-FR]
Ligne fr

[en-US]
Line en
''';
    final split = splitAdminAnnouncementForEditing(rawText);
    expect(split.frFr, 'Ligne fr');
    expect(split.enUs, 'Line en');
  });

  test(
      'splitAdminAnnouncementForEditing puts raw text in FR when no headers',
      () {
    const rawText = 'Pas de balises';
    final split = splitAdminAnnouncementForEditing(rawText);
    expect(split.frFr, 'Pas de balises');
    expect(split.enUs, '');
  });

  test('assemble then split round-trips fr/en bodies', () {
    const fr = 'Bonjour';
    const en = 'Hello';
    final assembled = assembleAdminAnnouncementMultilingualText(fr, en);
    final split = splitAdminAnnouncementForEditing(assembled);
    expect(split.frFr, fr);
    expect(split.enUs, en);
  });

  test('assemble then split round-trips French-only bodies', () {
    const fr = 'Bonjour';
    final assembled = assembleAdminAnnouncementMultilingualText(fr, '');
    expect(assembled, '[fr-FR]\nBonjour');
    final split = splitAdminAnnouncementForEditing(assembled);
    expect(split.frFr, fr);
    expect(split.enUs, '');
  });

  test('splitAdminAnnouncementForEditing uses [fr] and [en] fallback bodies',
      () {
    const rawText = '''
[fr]
Bonjour

[en-US]
Hello
''';
    final split = splitAdminAnnouncementForEditing(rawText);
    expect(split.frFr, 'Bonjour');
    expect(split.enUs, 'Hello');
  });
}
