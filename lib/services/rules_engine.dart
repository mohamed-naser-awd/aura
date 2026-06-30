import '../data/db/app_database.dart';

/// Builds the denormalized rules snapshot consumed by the native telephony services
/// (see `RulesSnapshot.kt`). Pure function so it is trivially unit-testable.
///
/// Keep the output shape in sync with `RulesSnapshot.kt`.
class RulesEngine {
  const RulesEngine();

  Map<String, dynamic> buildSnapshot({
    required List<Group> groups,
    required List<GroupMember> members,
    required List<Rule> rules,
    List<String> blocked = const [],
    Map<String, String> contactRingtones = const {},
    String intenseScope = 'group',
  }) {
    final rulesByGroup = <int, List<Rule>>{};
    for (final r in rules) {
      rulesByGroup.putIfAbsent(r.groupId, () => []).add(r);
    }

    final membersJson = <String, String>{};
    for (final m in members) {
      membersJson[m.normalizedNumber] = m.groupId.toString();
    }

    final groupsJson = <String, dynamic>{};
    for (final g in groups) {
      groupsJson[g.id.toString()] = {
        'muteEnabled': g.muteEnabled,
        'forceRing': g.ringOverridesSilent,
        'intenseModeEnabled': g.intenseModeEnabled,
        'politeDeclineEnabled': g.politeDeclineEnabled,
        'politeDeclineMessage': g.politeDeclineMessage,
        'ringtone': g.ringtoneUri,
        'rules': [
          for (final r in rulesByGroup[g.id] ?? const <Rule>[])
            {
              'kind': r.kind,
              'start': r.startMinuteOfDay,
              'end': r.endMinuteOfDay,
              'days': r.daysMask,
            },
        ],
      };
    }

    return {
      'version': 1,
      'intenseScope': intenseScope,
      'members': membersJson,
      'groups': groupsJson,
      'blocked': blocked,
      'ringtones': contactRingtones,
    };
  }
}
