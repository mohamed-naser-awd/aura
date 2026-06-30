import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/models/call_event.dart';

/// Listens to the native call-event stream and persists completed calls (with their
/// who-ended disconnect code, feature #1) into the drift call log. Activate by watching
/// [callLogIngestProvider] from a long-lived widget (see `AuraApp`).
class CallLogIngest {
  CallLogIngest(this._ref) {
    _ref.listen(callEventStreamProvider, (_, next) {
      final e = next.valueOrNull;
      if (e != null) _onEvent(e);
    });
  }

  final Ref _ref;

  // In-flight calls: callId -> (start time, connected time, number, direction).
  final _starts = <String, DateTime>{};
  final _connected = <String, DateTime>{};
  final _numbers = <String, String?>{};
  final _directions = <String, String>{};

  void _onEvent(NativeCallEvent e) {
    switch (e.type) {
      case CallEventType.added:
        _starts[e.callId] = DateTime.now();
        _numbers[e.callId] = e.number;
        _directions[e.callId] =
            e.state == CallState.ringing ? 'incoming' : 'outgoing';
        if (e.state == CallState.active) _connected.putIfAbsent(e.callId, DateTime.now);
      case CallEventType.state:
      case CallEventType.details:
        _numbers[e.callId] = e.number ?? _numbers[e.callId];
        // Record the moment the call connected (for ring vs talk duration).
        if (e.state == CallState.active) _connected.putIfAbsent(e.callId, DateTime.now);
      case CallEventType.removed:
        _record(e);
    }
  }

  Future<void> _record(NativeCallEvent e) async {
    final number = e.number ?? _numbers[e.callId] ?? 'Unknown';
    await _ref.read(callLogRepositoryProvider).record(
          number: number,
          direction: _directions[e.callId] ?? 'incoming',
          disconnectCode: e.disconnectCode,
          startTs: _starts[e.callId] ?? DateTime.now(),
          connectedTs: _connected[e.callId],
          endTs: DateTime.now(),
        );
    _starts.remove(e.callId);
    _connected.remove(e.callId);
    _numbers.remove(e.callId);
    _directions.remove(e.callId);
  }
}

/// Long-lived ingestion service. Keep alive for the app's lifetime.
final callLogIngestProvider = Provider<CallLogIngest>((ref) => CallLogIngest(ref));
