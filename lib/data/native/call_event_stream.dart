import 'package:flutter/services.dart';

import '../models/call_event.dart';

/// Live native call-event stream ("aura/call_events"), backed by `CallEventChannel.kt`.
/// Emits a [NativeCallEvent] per call lifecycle change.
const EventChannel _events = EventChannel('aura/call_events');

Stream<NativeCallEvent> watchCallEvents() {
  return _events.receiveBroadcastStream().map(
        (e) => NativeCallEvent.fromMap(e as Map<dynamic, dynamic>),
      );
}
