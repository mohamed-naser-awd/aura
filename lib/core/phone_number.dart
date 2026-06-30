/// Phone-number normalization used to match incoming numbers against group members.
///
/// The native side does a digit-only comparison; this keeps Dart in sync. For full
/// E.164 normalization with a region, use `libphonenumber_plugin` in
/// [normalizeToE164] (left as a thin wrapper so call sites are stable).
class PhoneNumber {
  PhoneNumber._();

  /// Cheap, dependency-free normalization: keep digits and a leading '+'.
  /// Matches `normalize()` in `RulesSnapshot.kt` / `EventLog.kt`.
  static String normalize(String raw) {
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (_isDigit(c) || (c == '+' && i == 0)) buffer.write(c);
    }
    return buffer.toString();
  }

  /// Placeholder for region-aware E.164 normalization via libphonenumber.
  /// TODO(aura): wire a region-aware normalizer using the device/SIM region.
  static Future<String> normalizeToE164(String raw, {String region = 'CA'}) async {
    return normalize(raw);
  }

  /// Digits only (no '+'), used for loose suffix matching across formatting/country-code
  /// differences (e.g. matching a call-log number to a WhatsApp-synced contact).
  static String digits(String raw) {
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (_isDigit(raw[i])) buffer.write(raw[i]);
    }
    return buffer.toString();
  }

  /// The last [n] digits of a number, for suffix comparison. Shorter numbers return as-is.
  static String suffix(String raw, {int n = 9}) {
    final d = digits(raw);
    return d.length <= n ? d : d.substring(d.length - n);
  }

  /// True if two numbers share the same trailing [n] digits (loose equality).
  static bool looseMatch(String a, String b, {int n = 9}) {
    final sa = suffix(a, n: n);
    final sb = suffix(b, n: n);
    return sa.isNotEmpty && sa == sb;
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
}
