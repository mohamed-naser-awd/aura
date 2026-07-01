import 'package:flutter/services.dart';

import '../models/sim_account.dart';

/// Dart wrapper over the native "aura/telecom" command channel. Backed by
/// `TelecomChannel.kt`. All telephony actions go through here.
class TelecomService {
  static const _channel = MethodChannel('aura/telecom');

  Future<bool> isDefaultDialer() async =>
      await _channel.invokeMethod<bool>('isDefaultDialer') ?? false;

  /// Launches the system role dialog to make Aura the default phone app.
  Future<void> requestDefaultDialerRole() =>
      _channel.invokeMethod<void>('requestDefaultDialerRole');

  Future<List<SimAccount>> getSimAccounts() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('getSimAccounts') ?? [];
    return raw
        .cast<Map<dynamic, dynamic>>()
        .map(SimAccount.fromMap)
        .toList(growable: false);
  }

  /// Places an outgoing call, optionally on a specific SIM (feature #5/#6/#7).
  Future<void> placeCall(String number, {String? phoneAccountId}) =>
      _channel.invokeMethod<void>('placeCall', {
        'number': number,
        'phoneAccountId': phoneAccountId,
      });

  Future<void> answer(String callId) =>
      _channel.invokeMethod<void>('answer', {'callId': callId});

  Future<void> reject(String callId, {String? message}) =>
      _channel.invokeMethod<void>('reject', {'callId': callId, 'message': message});

  Future<void> end(String callId) =>
      _channel.invokeMethod<void>('end', {'callId': callId});

  Future<void> hold(String callId) =>
      _channel.invokeMethod<void>('hold', {'callId': callId});

  Future<void> unhold(String callId) =>
      _channel.invokeMethod<void>('unhold', {'callId': callId});

  Future<void> dtmf(String callId, String digit) =>
      _channel.invokeMethod<void>('dtmf', {'callId': callId, 'digit': digit});

  Future<void> setMuted(bool muted) =>
      _channel.invokeMethod<void>('setMuted', {'muted': muted});

  Future<void> setAudioRoute(int route) =>
      _channel.invokeMethod<void>('setAudioRoute', {'route': route});

  /// Block a number straight from the call screen (persisted natively; the main app folds it
  /// into the drift blocklist on the next export).
  Future<void> blockNumber(String number) =>
      _channel.invokeMethod<void>('blockNumber', {'number': number});

  /// Whether Aura has Do-Not-Disturb (notification policy) access, needed for force-ring to
  /// break through DND.
  Future<bool> hasDndAccess() async =>
      await _channel.invokeMethod<bool>('hasDndAccess') ?? false;

  /// Opens the system screen to grant Do-Not-Disturb access.
  Future<void> openDndAccessSettings() =>
      _channel.invokeMethod<void>('openDndAccessSettings');
}
