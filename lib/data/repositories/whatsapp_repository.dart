import '../../core/phone_number.dart';
import '../db/app_database.dart';
import '../native/whatsapp_service.dart';

/// Drives the opt-in WhatsApp probe and its cache. The UI reads the cache (instant);
/// scans run in the background and persist results so subsequent launches are fast.
class WhatsAppRepository {
  WhatsAppRepository(this._db, this._service);

  final AuraDatabase _db;
  final WhatsAppService _service;

  /// Digit-normalized numbers cached as being on WhatsApp.
  Stream<Set<String>> watchDetected() => _db.watchWhatsAppCache().map(
        (rows) => rows.where((r) => r.hasWhatsApp).map((r) => r.number).toSet(),
      );

  /// Numbers worth probing: distinct call-log + group-member numbers not checked recently.
  Future<List<String>> candidates({
    int max = 50,
    Duration staleAfter = const Duration(days: 7),
  }) async {
    final now = DateTime.now();
    final cache = await _db.whatsAppCache();
    final fresh = cache
        .where((r) => now.difference(r.checkedAt) < staleAfter)
        .map((r) => r.number)
        .toSet();

    final out = <String>{};
    for (final n in await _db.recentNumbers()) {
      out.add(PhoneNumber.digits(n));
    }
    for (final m in await _db.allMembers()) {
      out.add(PhoneNumber.digits(m.normalizedNumber));
    }
    out.removeWhere((n) => n.isEmpty || fresh.contains(n));
    return out.take(max).toList();
  }

  /// Probes [numbers] (or the auto-gathered candidates) and caches the results.
  /// Returns how many numbers were probed.
  Future<int> scan({
    List<String>? numbers,
    int max = 50,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final toScan = numbers ?? await candidates(max: max);
    if (toScan.isEmpty) return 0;

    final results = await _service.scanNumbers(toScan, timeout: timeout);
    final now = DateTime.now();
    for (final entry in results.entries) {
      await _db.upsertWhatsAppCache(
        WhatsappCacheEntriesCompanion.insert(
          number: PhoneNumber.digits(entry.key),
          hasWhatsApp: entry.value,
          checkedAt: now,
        ),
      );
    }
    return toScan.length;
  }
}
