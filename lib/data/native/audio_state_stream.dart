import 'package:flutter/services.dart';

import '../models/audio_route.dart';

/// Live in-call audio routing state from native ("aura/audio").
const EventChannel _audio = EventChannel('aura/audio');

Stream<AudioRouteState> watchAudioState() {
  return _audio
      .receiveBroadcastStream()
      .map((e) => AudioRouteState.fromMap(e as Map<dynamic, dynamic>));
}
