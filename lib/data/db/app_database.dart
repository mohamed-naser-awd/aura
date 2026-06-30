import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Contact groups (feature #2) and their per-group call rules.
class Groups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 64)();
  IntColumn get color => integer().withDefault(const Constant(0xFF5B6CFF))();

  /// Per-group default SIM (feature #7); null = use global default.
  TextColumn get defaultSimId => text().nullable()();

  /// Feature #3: silence incoming calls from this group.
  BoolColumn get muteEnabled => boolean().withDefault(const Constant(false))();

  /// Feature #5: ring even when the phone is silent.
  BoolColumn get ringOverridesSilent => boolean().withDefault(const Constant(false))();

  /// Feature #8: escalate to max volume/vibration on repeat calls.
  BoolColumn get intenseModeEnabled => boolean().withDefault(const Constant(false))();

  /// Feature #9: polite-decline auto-SMS.
  BoolColumn get politeDeclineEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get politeDeclineMessage => text().nullable()();

  /// Avatar: optional Material icon code point + optional image file path (else colored initial).
  IntColumn get iconCodePoint => integer().nullable()();
  TextColumn get imagePath => text().nullable()();

  /// Custom ringtone for this group (content:// URI or audio file path); null = default.
  TextColumn get ringtoneUri => text().nullable()();
}

/// Members of a group, matched against incoming numbers by normalized (E.164) form.
class GroupMembers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get groupId => integer().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get normalizedNumber => text()();
  TextColumn get contactLookupKey => text().nullable()();
}

/// Time-window rules (feature #4). `kind` is 'ringWindow' or 'mute'.
class Rules extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get groupId => integer().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  IntColumn get startMinuteOfDay => integer().withDefault(const Constant(0))();
  IntColumn get endMinuteOfDay => integer().withDefault(const Constant(1440))();

  /// Bitmask, bit 0 = Sunday .. bit 6 = Saturday. Default = all days.
  IntColumn get daysMask => integer().withDefault(const Constant(0x7F))();
}

/// Call history with who-ended disposition (feature #1) and intense-mode source data (#8).
class CallEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get number => text()();
  IntColumn get groupId => integer().nullable()();
  TextColumn get direction => text()(); // 'incoming' | 'outgoing'
  IntColumn get disconnectCode => integer().nullable()();
  DateTimeColumn get startTs => dateTime()();

  /// When the call connected (state became active); null if never answered.
  DateTimeColumn get connectedTs => dateTime().nullable()();
  DateTimeColumn get endTs => dateTime().nullable()();
  TextColumn get simId => text().nullable()();
}

/// Simple key/value app settings (default SIM mode, intense scope, etc.).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Cached result of the opt-in WhatsApp probe per (digit-normalized) number, so the UI
/// reads instantly and re-scans only happen in the background.
class WhatsappCacheEntries extends Table {
  TextColumn get number => text()(); // digit-normalized
  BoolColumn get hasWhatsApp => boolean()();
  DateTimeColumn get checkedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {number};
}

/// Blocked numbers (digit-normalized). Calls from these are rejected by the screening service.
class BlockedNumbers extends Table {
  TextColumn get number => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {number};
}

/// Per-contact (digit-normalized number) custom ringtone (content:// URI or file path).
class ContactRingtones extends Table {
  TextColumn get number => text()();
  TextColumn get ringtoneUri => text()();

  @override
  Set<Column> get primaryKey => {number};
}

@DriftDatabase(
  tables: [
    Groups,
    GroupMembers,
    Rules,
    CallEvents,
    Settings,
    WhatsappCacheEntries,
    BlockedNumbers,
    ContactRingtones,
  ],
)
class AuraDatabase extends _$AuraDatabase {
  AuraDatabase() : super(_open());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(whatsappCacheEntries);
          if (from < 3) await m.addColumn(callEvents, callEvents.connectedTs);
          if (from < 4) await m.createTable(blockedNumbers);
          if (from < 5) {
            await m.addColumn(groups, groups.iconCodePoint);
            await m.addColumn(groups, groups.imagePath);
            await m.addColumn(groups, groups.ringtoneUri);
            await m.createTable(contactRingtones);
          }
        },
      );

  // --- Contact ringtones ---
  Future<List<ContactRingtone>> contactRingtoneList() => select(contactRingtones).get();
  Stream<List<ContactRingtone>> watchContactRingtones() => select(contactRingtones).watch();
  Future<String?> contactRingtone(String number) async {
    final row = await (select(contactRingtones)..where((r) => r.number.equals(number)))
        .getSingleOrNull();
    return row?.ringtoneUri;
  }

  Future<void> setContactRingtone(String number, String uri) =>
      into(contactRingtones).insertOnConflictUpdate(
        ContactRingtonesCompanion.insert(number: number, ringtoneUri: uri),
      );

  Future<int> clearContactRingtone(String number) =>
      (delete(contactRingtones)..where((r) => r.number.equals(number))).go();

  // --- Blocklist ---
  Stream<List<BlockedNumber>> watchBlocked() => select(blockedNumbers).watch();
  Future<List<BlockedNumber>> blockedList() => select(blockedNumbers).get();
  Future<void> insertBlocked(String number, DateTime at) =>
      into(blockedNumbers).insertOnConflictUpdate(
        BlockedNumbersCompanion.insert(number: number, createdAt: at),
      );
  Future<int> deleteBlocked(String number) =>
      (delete(blockedNumbers)..where((b) => b.number.equals(number))).go();

  // --- Groups ---
  Future<List<Group>> allGroups() => select(groups).get();
  Stream<List<Group>> watchGroups() => select(groups).watch();
  Future<Group> groupById(int id) =>
      (select(groups)..where((g) => g.id.equals(id))).getSingle();
  Future<int> insertGroup(GroupsCompanion g) => into(groups).insert(g);
  Future<bool> updateGroup(Group g) => update(groups).replace(g);
  Future<int> deleteGroup(int id) => (delete(groups)..where((g) => g.id.equals(id))).go();

  // --- Members ---
  Future<List<GroupMember>> membersOf(int groupId) =>
      (select(groupMembers)..where((m) => m.groupId.equals(groupId))).get();
  Future<int> addMember(GroupMembersCompanion m) => into(groupMembers).insert(m);
  Future<int> removeMember(int id) =>
      (delete(groupMembers)..where((m) => m.id.equals(id))).go();
  Future<List<GroupMember>> allMembers() => select(groupMembers).get();

  // --- Rules ---
  Future<List<Rule>> rulesOf(int groupId) =>
      (select(rules)..where((r) => r.groupId.equals(groupId))).get();
  Future<int> addRule(RulesCompanion r) => into(rules).insert(r);
  Future<int> removeRule(int id) => (delete(rules)..where((r) => r.id.equals(id))).go();
  Future<List<Rule>> allRules() => select(rules).get();

  // --- Call events ---
  Stream<List<CallEvent>> watchRecentCalls({int limit = 200}) =>
      (select(callEvents)
            ..orderBy([(c) => OrderingTerm.desc(c.startTs)])
            ..limit(limit))
          .watch();
  Future<int> insertCallEvent(CallEventsCompanion c) => into(callEvents).insert(c);

  /// Distinct numbers seen in the call log (candidates for the WhatsApp probe).
  Future<List<String>> recentNumbers({int limit = 300}) async {
    final q = selectOnly(callEvents)
      ..addColumns([callEvents.number])
      ..groupBy([callEvents.number])
      ..limit(limit);
    final rows = await q.get();
    return rows.map((r) => r.read(callEvents.number)).whereType<String>().toList();
  }

  // --- WhatsApp cache ---
  Stream<List<WhatsappCacheEntry>> watchWhatsAppCache() => select(whatsappCacheEntries).watch();
  Future<List<WhatsappCacheEntry>> whatsAppCache() => select(whatsappCacheEntries).get();
  Future<void> upsertWhatsAppCache(WhatsappCacheEntriesCompanion entry) =>
      into(whatsappCacheEntries).insertOnConflictUpdate(entry);

  // --- Settings ---
  Future<String?> setting(String key) async {
    final row = await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> putSetting(String key, String value) => into(settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: key, value: value),
      );
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'aura.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
