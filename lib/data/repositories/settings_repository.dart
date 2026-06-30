import '../db/app_database.dart';
import '../models/sim_account.dart';

/// How the WhatsApp quick-action button decides when to show.
enum WhatsAppMode {
  /// Show for every number (gated only by WhatsApp being installed).
  always,

  /// Show only for numbers detected as WhatsApp-synced contacts.
  contactsOnly,
}

/// App-wide settings: default SIM selection mode/value (feature #5/#6), intense scope (#8),
/// and the WhatsApp button mode.
class SettingsRepository {
  SettingsRepository(this._db);

  final AuraDatabase _db;

  static const _kSimMode = 'simMode';
  static const _kSimId = 'simId';
  static const _kIntenseScope = 'intenseScope';
  static const _kWhatsAppMode = 'whatsappMode';
  static const _kWhatsAppAutoScan = 'whatsappAutoScan';

  Future<SimSelectionMode> simMode() async {
    final v = await _db.setting(_kSimMode);
    return v == 'fixed' ? SimSelectionMode.fixed : SimSelectionMode.alwaysAsk;
  }

  Future<void> setSimMode(SimSelectionMode mode) =>
      _db.putSetting(_kSimMode, mode == SimSelectionMode.fixed ? 'fixed' : 'alwaysAsk');

  Future<String?> defaultSimId() => _db.setting(_kSimId);
  Future<void> setDefaultSimId(String id) => _db.putSetting(_kSimId, id);

  /// 'group' = intense applies per-group config; 'all' = applies to every caller.
  Future<String> intenseScope() async => await _db.setting(_kIntenseScope) ?? 'group';
  Future<void> setIntenseScope(String scope) => _db.putSetting(_kIntenseScope, scope);

  Future<WhatsAppMode> whatsAppMode() async {
    final v = await _db.setting(_kWhatsAppMode);
    return v == 'contactsOnly' ? WhatsAppMode.contactsOnly : WhatsAppMode.always;
  }

  Future<void> setWhatsAppMode(WhatsAppMode mode) => _db.putSetting(
        _kWhatsAppMode,
        mode == WhatsAppMode.contactsOnly ? 'contactsOnly' : 'always',
      );

  /// Whether the user opted into the WhatsApp probe (enables background re-scans).
  Future<bool> whatsAppAutoScan() async =>
      (await _db.setting(_kWhatsAppAutoScan)) == 'true';
  Future<void> setWhatsAppAutoScan(bool enabled) =>
      _db.putSetting(_kWhatsAppAutoScan, enabled ? 'true' : 'false');
}
