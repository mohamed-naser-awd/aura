import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Reads/writes Aura's own call history, which carries the who-ended disposition
/// (feature #1) that the system call log does not expose.
class CallLogRepository {
  CallLogRepository(this._db);

  final AuraDatabase _db;

  Stream<List<CallEvent>> watchRecent({int limit = 200}) =>
      _db.watchRecentCalls(limit: limit);

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
