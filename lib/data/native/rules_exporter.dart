import 'dart:convert';

import 'package:flutter/services.dart';

import '../../services/rules_engine.dart';
import '../db/app_database.dart';
import 'telecom_service.dart';

/// Reads the current groups/members/rules from the DB, builds the snapshot via
/// [RulesEngine], and pushes it to native over the "aura/rules" channel. Call
/// [export] after any change to groups, members, or rules so the telephony services
/// (which may run without the Flutter UI) see the latest configuration.
class RulesExporter {
  RulesExporter(this._db, this._telecom);

  final AuraDatabase _db;
  // Reserved for future use (e.g. re-reading intense scope from settings).
  // ignore: unused_field
  final TelecomService _telecom;

  static const _channel = MethodChannel('aura/rules');
  static const _engine = RulesEngine();

  Future<void> export() async {
    // Fold any blocks captured natively (e.g. from the call screen, which has no DB) into the
    // drift blocklist first, so they persist and the snapshot below includes them.
    final pending =
        (await _channel.invokeMethod<List<dynamic>>('takePendingBlocks'))?.cast<String>() ?? const [];
    for (final n in pending) {
      if (n.isNotEmpty) await _db.insertBlocked(n, DateTime.now());
    }
    final intenseScope = await _db.setting('intenseScope') ?? 'group';
    final blocked = (await _db.blockedList()).map((b) => b.number).toList();
    final contactRingtones = {
      for (final r in await _db.contactRingtoneList()) r.number: r.ringtoneUri,
    };
    final snapshot = _engine.buildSnapshot(
      groups: await _db.allGroups(),
      members: await _db.allMembers(),
      rules: await _db.allRules(),
      blocked: blocked,
      contactRingtones: contactRingtones,
      intenseScope: intenseScope,
    );
    await _channel.invokeMethod<void>('exportSnapshot', {'json': jsonEncode(snapshot)});
  }
}
