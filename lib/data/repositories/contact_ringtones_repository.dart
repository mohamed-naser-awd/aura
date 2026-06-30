import '../../core/phone_number.dart';
import '../db/app_database.dart';
import '../native/rules_exporter.dart';

/// Per-contact (number) custom ringtone. Stored digit-normalized and exported to the native
/// rules snapshot so `RingController` can pick it at ring time.
class ContactRingtonesRepository {
  ContactRingtonesRepository(this._db, this._exporter);

  final AuraDatabase _db;
  final RulesExporter _exporter;

  Future<String?> ringtoneFor(String number) => _db.contactRingtone(PhoneNumber.digits(number));

  /// Set ([uri] non-null) or clear ([uri] null → default) the ringtone for [number].
  Future<void> setRingtone(String number, String? uri) async {
    final n = PhoneNumber.digits(number);
    if (n.isEmpty) return;
    if (uri == null) {
      await _db.clearContactRingtone(n);
    } else {
      await _db.setContactRingtone(n, uri);
    }
    await _exporter.export();
  }
}
