import 'package:aura/services/intense_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntenseLogic (#8)', () {
    const logic = IntenseLogic();
    final now = DateTime(2026, 6, 30, 12, 0);

    test('triggers when a prior call is within 5 minutes', () {
      final prior = [now.subtract(const Duration(minutes: 3))];
      expect(logic.triggers(prior, now), isTrue);
    });

    test('does not trigger when prior call is older than 5 minutes', () {
      final prior = [now.subtract(const Duration(minutes: 6))];
      expect(logic.triggers(prior, now), isFalse);
    });

    test('does not trigger with no prior calls', () {
      expect(logic.triggers(const [], now), isFalse);
    });

    test('exactly 5 minutes is inclusive', () {
      final prior = [now.subtract(const Duration(minutes: 5))];
      expect(logic.triggers(prior, now), isTrue);
    });
  });

  group('TimeWindow (#4)', () {
    test('ring window contains times inside the range', () {
      const w = TimeWindow(startMinute: 8 * 60, endMinute: 22 * 60);
      expect(w.contains(12 * 60), isTrue);
      expect(w.contains(22 * 60 + 30), isFalse); // after 22:00 -> would be muted
      expect(w.contains(7 * 60), isFalse);
    });

    test('daysMask gates the active days', () {
      const weekdaysOnly = TimeWindow(startMinute: 0, endMinute: 1440, daysMask: 0x3E); // Mon..Fri
      expect(weekdaysOnly.appliesOn(0), isFalse); // Sunday
      expect(weekdaysOnly.appliesOn(1), isTrue); // Monday
      expect(weekdaysOnly.appliesOn(6), isFalse); // Saturday
    });
  });
}
