import 'disconnect_kind.dart';

/// A row in Recents. The **base** facts (number, direction, start, talk duration, outcome)
/// come from the Android system call log (`content://call_log`) — the single source of truth
/// for which calls exist. The optional who-ended fields ([connectedTs] ring split,
/// [disconnectCode]) are enriched from Aura's drift sidecar for calls Aura witnessed; calls it
/// did not witness simply appear without them (feature #1 is best-effort, not gating).
class RecentCall {
  const RecentCall({
    required this.number,
    required this.direction,
    required this.startTs,
    this.connectedTs,
    this.endTs,
    this.disconnectCode,
    this.systemType = 0,
  });

  final String number;
  final String direction; // 'incoming' | 'outgoing'
  final DateTime startTs;

  /// When the call connected (null = never answered). For a connected system-log row this is a
  /// placeholder equal to [startTs] (ring unknown) until enriched from the sidecar.
  final DateTime? connectedTs;
  final DateTime? endTs;

  /// android.telecom.DisconnectCause code (feature #1), or a synthetic marker like
  /// [kBlockedDisconnectCode]. Null when unknown.
  final int? disconnectCode;

  /// Raw CallLog.Calls.TYPE, kept for reference.
  final int systemType;

  bool get connected => connectedTs != null;

  /// Builds the base row from one `getSystemCallLog` map (see [TelecomService.getSystemCallLog]).
  factory RecentCall.fromSystemLog(Map<dynamic, dynamic> row) {
    final type = (row['type'] as num?)?.toInt() ?? _typeIncoming;
    final start = DateTime.fromMillisecondsSinceEpoch((row['date'] as num?)?.toInt() ?? 0);
    final durationSecs = (row['duration'] as num?)?.toInt() ?? 0;

    final incoming = type != _typeOutgoing;
    // Which system types represent a call that actually connected/talked.
    final connectedType =
        type == _typeIncoming || type == _typeOutgoing || type == _typeAnsweredExternally;
    final connected = connectedType && durationSecs > 0;

    return RecentCall(
      number: (row['number'] as String?) ?? '',
      direction: incoming ? 'incoming' : 'outgoing',
      startTs: start,
      // Placeholder connect = start so talk shows and ring reads 0 (suppressed) until enriched.
      connectedTs: connected ? start : null,
      endTs: connected ? start.add(Duration(seconds: durationSecs)) : null,
      disconnectCode: _codeForType(type),
      systemType: type,
    );
  }

  /// Returns a copy enriched with who-ended data from a matched sidecar row. Real values win;
  /// a null sidecar field falls back to the base so we never lose the base connected state.
  RecentCall withWhoEnded({DateTime? connectedTs, DateTime? endTs, int? disconnectCode}) {
    return RecentCall(
      number: number,
      direction: direction,
      startTs: startTs,
      connectedTs: connectedTs ?? this.connectedTs,
      endTs: endTs ?? this.endTs,
      disconnectCode: disconnectCode ?? this.disconnectCode,
      systemType: systemType,
    );
  }

  // CallLog.Calls.TYPE constants.
  static const _typeIncoming = 1;
  static const _typeOutgoing = 2;
  static const _typeMissed = 3;
  static const _typeVoicemail = 4;
  static const _typeRejected = 5;
  static const _typeBlocked = 6;
  static const _typeAnsweredExternally = 7;

  /// Maps a system TYPE to a disconnect code the disposition helper understands. Returns null
  /// for plain incoming/outgoing/voicemail (outcome comes from `connected`).
  static int? _codeForType(int type) {
    switch (type) {
      case _typeMissed:
        return 5; // DisconnectCause.MISSED
      case _typeRejected:
        return 6; // DisconnectCause.REJECTED -> "Declined"
      case _typeBlocked:
        return kBlockedDisconnectCode;
      case _typeAnsweredExternally:
        return 11; // DisconnectCause.ANSWERED_ELSEWHERE
      case _typeIncoming:
      case _typeOutgoing:
      case _typeVoicemail:
      default:
        return null;
    }
  }
}
