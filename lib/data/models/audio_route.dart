import 'package:flutter/material.dart';

/// Android `CallAudioState.ROUTE_*` bit values.
class AudioRoutes {
  static const int earpiece = 1;
  static const int bluetooth = 2;
  static const int wiredHeadset = 4;
  static const int speaker = 8;

  static const ordered = [earpiece, wiredHeadset, bluetooth, speaker];

  static String label(int route) => switch (route) {
        speaker => 'Speaker',
        bluetooth => 'Bluetooth',
        wiredHeadset => 'Wired headset',
        _ => 'Earpiece',
      };

  static IconData icon(int route) => switch (route) {
        speaker => Icons.volume_up,
        bluetooth => Icons.bluetooth_audio,
        wiredHeadset => Icons.headset,
        _ => Icons.phone_in_talk,
      };
}

/// In-call audio routing snapshot from native ("aura/audio").
class AudioRouteState {
  const AudioRouteState({required this.route, required this.supportedMask, required this.muted});

  final int route;
  final int supportedMask;
  final bool muted;

  bool supports(int r) => (supportedMask & r) != 0;

  /// Supported routes in a stable display order.
  List<int> get supportedRoutes =>
      AudioRoutes.ordered.where((r) => supports(r)).toList();

  factory AudioRouteState.fromMap(Map<dynamic, dynamic> map) => AudioRouteState(
        route: map['route'] as int? ?? AudioRoutes.earpiece,
        supportedMask: map['supportedMask'] as int? ?? AudioRoutes.earpiece,
        muted: map['muted'] as bool? ?? false,
      );

  static const empty = AudioRouteState(
    route: AudioRoutes.earpiece,
    supportedMask: AudioRoutes.earpiece,
    muted: false,
  );
}
