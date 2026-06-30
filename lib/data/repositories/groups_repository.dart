import 'package:drift/drift.dart';

import '../../core/phone_number.dart';
import '../db/app_database.dart';
import '../native/rules_exporter.dart';

/// CRUD for groups, members, and rules (features #2, #3, #4, #7, #8, #9). Every mutation
/// re-exports the native rules snapshot so the telephony services stay in sync.
class GroupsRepository {
  GroupsRepository(this._db, this._exporter);

  final AuraDatabase _db;
  final RulesExporter _exporter;

  Stream<List<Group>> watchGroups() => _db.watchGroups();
  Future<Group> group(int id) => _db.groupById(id);
  Future<List<GroupMember>> members(int groupId) => _db.membersOf(groupId);
  Future<List<Rule>> rules(int groupId) => _db.rulesOf(groupId);

  Future<int> createGroup(String name, {int? color}) async {
    final id = await _db.insertGroup(
      GroupsCompanion.insert(
        name: name,
        color: color == null ? const Value.absent() : Value(color),
      ),
    );
    await _exporter.export();
    return id;
  }

  /// Creates a group with its config and initial members in one shot (single snapshot export).
  Future<int> createGroupWith({
    required String name,
    int? color,
    bool mute = false,
    bool ringOverridesSilent = false,
    bool intense = false,
    bool politeDecline = false,
    String? politeMessage,
    List<String> memberNumbers = const [],
  }) async {
    final id = await _db.insertGroup(
      GroupsCompanion.insert(
        name: name,
        color: color == null ? const Value.absent() : Value(color),
        muteEnabled: Value(mute),
        ringOverridesSilent: Value(ringOverridesSilent),
        intenseModeEnabled: Value(intense),
        politeDeclineEnabled: Value(politeDecline),
        politeDeclineMessage: Value(politeMessage),
      ),
    );
    final unique = memberNumbers.map(PhoneNumber.normalize).where((n) => n.isNotEmpty).toSet();
    for (final n in unique) {
      await _db.addMember(GroupMembersCompanion.insert(groupId: id, normalizedNumber: n));
    }
    await _exporter.export();
    return id;
  }

  /// Replaces a group's membership with [numbers]: adds new ones, removes de-selected ones
  /// (single snapshot export). Used by the contact picker's "edit members" flow.
  Future<void> syncMembers(int groupId, List<String> numbers) async {
    final desired = numbers.map(PhoneNumber.normalize).where((n) => n.isNotEmpty).toSet();
    final existing = await _db.membersOf(groupId);
    final existingNumbers = {for (final m in existing) m.normalizedNumber};

    for (final m in existing) {
      if (!desired.contains(m.normalizedNumber)) await _db.removeMember(m.id);
    }
    for (final n in desired) {
      if (!existingNumbers.contains(n)) {
        await _db.addMember(GroupMembersCompanion.insert(groupId: groupId, normalizedNumber: n));
      }
    }
    await _exporter.export();
  }

  Future<void> updateGroup(Group group) async {
    await _db.updateGroup(group);
    await _exporter.export();
  }

  Future<void> deleteGroup(int id) async {
    await _db.deleteGroup(id);
    await _exporter.export();
  }

  Future<void> addMember(int groupId, String normalizedNumber, {String? lookupKey}) async {
    await _db.addMember(
      GroupMembersCompanion.insert(
        groupId: groupId,
        normalizedNumber: normalizedNumber,
        contactLookupKey: Value(lookupKey),
      ),
    );
    await _exporter.export();
  }

  Future<void> removeMember(int memberId) async {
    await _db.removeMember(memberId);
    await _exporter.export();
  }

  Future<void> addRule(
    int groupId, {
    required String kind, // 'ringWindow' | 'mute'
    required int startMinuteOfDay,
    required int endMinuteOfDay,
    int daysMask = 0x7F,
  }) async {
    await _db.addRule(
      RulesCompanion.insert(
        groupId: groupId,
        kind: kind,
        startMinuteOfDay: Value(startMinuteOfDay),
        endMinuteOfDay: Value(endMinuteOfDay),
        daysMask: Value(daysMask),
      ),
    );
    await _exporter.export();
  }

  Future<void> removeRule(int ruleId) async {
    await _db.removeRule(ruleId);
    await _exporter.export();
  }
}
