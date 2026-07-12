import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Aura's "who-ended" sidecar. The system call log is the source of truth for which calls
/// exist; this table only carries the who-ended disposition (feature #1) that the system log
/// does not expose, and is merged into the system rows at display time.
class CallLogRepository {
  CallLogRepository(this._db);

  final AuraDatabase _db;

  /// One-shot read of the sidecar, most-recent first (for the Recents merge).
  Future<List<CallEvent>> recent({int limit = 200}) => _db.recentCalls(limit: limit);

  Future<void> record({
    required String number,
    required String direction, // 'incoming' | 'outgoing'
    int? groupId,
    int? disconnectCode,
    required DateTime startTs,
    DateTime? connectedTs,
    DateTime? endTs,
    String? simId,
  }) {
    return _db.insertCallEvent(
      CallEventsCompanion.insert(
        number: number,
        direction: direction,
        groupId: Value(groupId),
        disconnectCode: Value(disconnectCode),
        startTs: startTs,
        connectedTs: Value(connectedTs),
        endTs: Value(endTs),
        simId: Value(simId),
      ),
    );
  }
}
