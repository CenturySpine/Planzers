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
}
