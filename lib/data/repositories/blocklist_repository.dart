import '../../core/phone_number.dart';
import '../db/app_database.dart';
import '../native/rules_exporter.dart';

/// Blocked numbers. Calls from these are rejected by the native screening service via the
/// exported rules snapshot. Numbers are stored digit-normalized for robust matching.
class BlocklistRepository {
  BlocklistRepository(this._db, this._exporter);

  final AuraDatabase _db;
  final RulesExporter _exporter;

  Stream<Set<String>> watchBlocked() =>
      _db.watchBlocked().map((rows) => rows.map((r) => r.number).toSet());

  Future<void> block(String number) async {
    final n = PhoneNumber.digits(number);
    if (n.isEmpty) return;
    await _db.insertBlocked(n, DateTime.now());
    await _exporter.export();
  }

  Future<void> unblock(String number) async {
    await _db.deleteBlocked(PhoneNumber.digits(number));
    await _exporter.export();
  }
}
