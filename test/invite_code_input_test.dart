import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/trips/data/invite_code_input.dart';

void main() {
  test('sanitize strips separators and caps length', () {
    expect(sanitizeInviteCodeInput('abC-dEf'), 'ABCDEF');
    expect(sanitizeInviteCodeInput('  pzx92k7q  '), 'PZX92K');
    expect(sanitizeInviteCodeInput('abc123xyz'), 'ABC123');
  });

  test('format builds token with middle hyphen', () {
    expect(formatInviteCodeToken('ABCDEF'), 'ABC-DEF');
    expect(formatInviteCodeToken('AB'), 'AB');
  });
}
