import 'disconnect_kind.dart';

/// One lifecycle event from the native call-event stream ("aura/call_events").
enum CallEventType { added, state, details, removed }

/// Android `Call.STATE_*` values used by the in-call UI.
class CallState {
  static const int newCall = 0;
  static const int ringing = 2;
  static const int dialing = 3;
  static const int active = 4;
  static const int holding = 5;
  static const int disconnected = 7;
  static const int connecting = 9;
  static const int disconnecting = 10;
  static const int selectingPhoneAccount = 8;
}

/// A live event from the native call stream. Named with the `Native` prefix to avoid
/// colliding with drift's generated `CallEvent` row class (from the `CallEvents` table).
class NativeCallEvent {
  const NativeCallEvent({
    required this.type,
    required this.callId,
    this.number,
    this.name,
    this.state,
    this.connectTimeMillis,
    this.disconnectCode,
    this.disconnectLabel,
  });

  final CallEventType type;
  final String callId;
  final String? number;
  final String? name;
  final int? state;

  /// Epoch ms the call connected (0/null until connected); drives the live in-call timer.
  final int? connectTimeMillis;
  final int? disconnectCode;
  final String? disconnectLabel;

  DisconnectKind get disconnectKind => DisconnectKind.fromAndroidCode(disconnectCode);

  factory NativeCallEvent.fromMap(Map<dynamic, dynamic> map) {
    return NativeCallEvent(
      type: switch (map['type'] as String?) {
        'added' => CallEventType.added,
        'state' => CallEventType.state,
        'details' => CallEventType.details,
        'removed' => CallEventType.removed,
        _ => CallEventType.state,
      },
      callId: map['callId'] as String,
      number: map['number'] as String?,
      name: map['name'] as String?,
      state: map['state'] as int?,
      connectTimeMillis: map['connectTimeMillis'] as int?,
      disconnectCode: map['disconnectCode'] as int?,
      disconnectLabel: map['disconnectLabel'] as String?,
    );
  }
}
