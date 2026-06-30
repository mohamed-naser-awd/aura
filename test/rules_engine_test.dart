// NOTE: requires code generation first:
//   dart run build_runner build --delete-conflicting-outputs
// because it constructs drift's generated row classes (Group/GroupMember/Rule).

import 'package:aura/data/db/app_database.dart';
import 'package:aura/services/rules_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = RulesEngine();

  Group group({
    int id = 1,
    bool mute = false,
    bool ringOverridesSilent = false,
    bool intense = false,
    bool politeDecline = false,
    String? message,
    String? defaultSimId,
  }) {
    return Group(
      id: id,
      name: 'G$id',
      color: 0xFF000000,
      defaultSimId: defaultSimId,
      muteEnabled: mute,
      ringOverridesSilent: ringOverridesSilent,
      intenseModeEnabled: intense,
      politeDeclineEnabled: politeDecline,
      politeDeclineMessage: message,
    );
  }

  test('snapshot maps members to group ids and flags', () {
    final snapshot = engine.buildSnapshot(
      groups: [group(id: 1, mute: true, intense: true)],
      members: [
        const GroupMember(id: 1, groupId: 1, normalizedNumber: '+15551234567', contactLookupKey: null),
      ],
      rules: [
        const Rule(id: 1, groupId: 1, kind: 'ringWindow', startMinuteOfDay: 480, endMinuteOfDay: 1320, daysMask: 0x7F),
      ],
    );

    expect(snapshot['version'], 1);
    expect((snapshot['members'] as Map)['+15551234567'], '1');

    final g = (snapshot['groups'] as Map)['1'] as Map;
    expect(g['muteEnabled'], true);
    expect(g['forceRing'], false);
    expect(g['intenseModeEnabled'], true);
    expect((g['rules'] as List).single['end'], 1320);
  });

  test('ringOverridesSilent maps to forceRing', () {
    final snapshot = engine.buildSnapshot(
      groups: [group(id: 2, ringOverridesSilent: true)],
      members: const [],
      rules: const [],
    );
    expect(((snapshot['groups'] as Map)['2'] as Map)['forceRing'], true);
  });
}
