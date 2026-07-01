import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/call_event.dart';

/// Bumped each time native (the ongoing-call notification's "change device" action via the
/// `aura/call_ui` channel) asks the in-call screen to open the audio-device picker.
final audioPickerSignalProvider = StateProvider<int>((ref) => 0);

/// Snapshot of one tracked call, assembled from the native event stream.
class ActiveCall {
  const ActiveCall({
    required this.callId,
    this.number,
    this.name,
    this.state,
    this.connectTimeMillis,
  });

  final String callId;
  final String? number;
  final String? name;
  final int? state;

  /// Epoch ms the call connected (0/null until connected).
  final int? connectTimeMillis;

  bool get isRinging => state == CallState.ringing;
  bool get isActive => state == CallState.active;

  /// True once the call is connected (active or on hold) and has a connect timestamp.
  bool get isConnected =>
      (connectTimeMillis ?? 0) > 0 &&
      (state == CallState.active || state == CallState.holding);

  /// Elapsed talk time since connect, or null if not connected yet.
  Duration? get elapsed => isConnected
      ? DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(connectTimeMillis!))
      : null;

  /// Best label for the caller: contact/CNAP name, else the number.
  String get displayLabel => (name != null && name!.isNotEmpty)
      ? name!
      : (number != null && number!.isNotEmpty ? number! : 'Unknown');

  ActiveCall copyWith({String? number, String? name, int? state, int? connectTimeMillis}) =>
      ActiveCall(
        callId: callId,
        number: number ?? this.number,
        name: name ?? this.name,
        state: state ?? this.state,
        connectTimeMillis: connectTimeMillis ?? this.connectTimeMillis,
      );
}

/// Tracks the set of active calls by listening to the native call-event stream.
/// Drives the incoming/in-call screens.
class ActiveCallsNotifier extends StateNotifier<Map<String, ActiveCall>> {
  ActiveCallsNotifier(this._ref) : super(const {}) {
    _ref.listen(callEventStreamProvider, (_, next) {
      final event = next.valueOrNull;
      if (event != null) _apply(event);
    });
  }

  final Ref _ref;

  void _apply(NativeCallEvent e) {
    final next = Map<String, ActiveCall>.from(state);
    switch (e.type) {
      case CallEventType.removed:
        next.remove(e.callId);
      case CallEventType.added:
      case CallEventType.state:
      case CallEventType.details:
        final existing = next[e.callId] ??
            ActiveCall(
              callId: e.callId,
              number: e.number,
              name: e.name,
              state: e.state,
              connectTimeMillis: e.connectTimeMillis,
            );
        next[e.callId] = existing.copyWith(
          number: e.number,
          name: e.name,
          state: e.state,
          connectTimeMillis: e.connectTimeMillis,
        );
    }
    state = next;
  }

  ActiveCall? get ringing =>
      state.values.where((c) => c.isRinging).firstOrNull;

  ActiveCall? get foreground =>
      state.values.where((c) => c.isActive).firstOrNull ?? state.values.firstOrNull;
}

final activeCallsProvider =
    StateNotifierProvider<ActiveCallsNotifier, Map<String, ActiveCall>>((ref) {
  return ActiveCallsNotifier(ref);
});
