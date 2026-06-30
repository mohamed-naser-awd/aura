import 'package:aura/core/phone_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneNumber.digits', () {
    test('strips formatting and symbols', () {
      expect(PhoneNumber.digits('+1 (555) 123-4567'), '15551234567');
    });
  });

  group('PhoneNumber.suffix', () {
    test('returns last n digits', () {
      expect(PhoneNumber.suffix('+1 555 123 4567', n: 9), '551234567');
    });
    test('short numbers returned whole', () {
      expect(PhoneNumber.suffix('1234', n: 9), '1234');
    });
  });

  group('PhoneNumber.looseMatch (WhatsApp contacts-only matching)', () {
    test('matches across country-code / formatting differences', () {
      expect(PhoneNumber.looseMatch('+1 555 123 4567', '5551234567'), isTrue);
      expect(PhoneNumber.looseMatch('(555) 123-4567', '001 555 123 4567'), isTrue);
    });
    test('does not match different numbers', () {
      expect(PhoneNumber.looseMatch('5551234567', '5559999999'), isFalse);
    });
    test('empty does not match', () {
      expect(PhoneNumber.looseMatch('', '5551234567'), isFalse);
    });
  });
}
