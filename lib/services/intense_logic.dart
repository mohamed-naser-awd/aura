/// Dart mirror of the intense-mode trigger (feature #8) used for unit tests and any
/// in-app preview. The authoritative runtime check lives in native `RulesSnapshot.kt` /
/// `EventLog.kt`; this keeps the rule definition documented and testable on the Dart side.
class IntenseLogic {
  const IntenseLogic({this.window = const Duration(minutes: 5)});

  final Duration window;

  /// Given the timestamps of prior calls from a number and the [now] arrival, returns
  /// true if a previous call landed within [window] before now (i.e. the 2nd call in 5 min).
  bool triggers(List<DateTime> priorCalls, DateTime now) {
    for (final t in priorCalls) {
      final delta = now.difference(t);
      if (!delta.isNegative && delta <= window) return true;
    }
    return false;
  }
}

/// Time-window evaluation (feature #4) mirror, for tests.
class TimeWindow {
  const TimeWindow({required this.startMinute, required this.endMinute, this.daysMask = 0x7F});

  final int startMinute;
  final int endMinute;
  final int daysMask;

  bool appliesOn(int dayOfWeek) => (daysMask >> dayOfWeek) & 1 == 1;

  bool contains(int minuteOfDay) => minuteOfDay >= startMinute && minuteOfDay < endMinute;
}
