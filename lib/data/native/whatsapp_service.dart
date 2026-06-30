import 'package:flutter/services.dart';

/// Dart wrapper over the native "aura/whatsapp" channel (see `WhatsAppChannel.kt`).
/// Launches WhatsApp chats and, for "contacts only" mode, reports which saved contacts
/// are on WhatsApp.
class WhatsAppService {
  static const _channel = MethodChannel('aura/whatsapp');

  /// Whether com.whatsapp (or the business variant) is installed.
  Future<bool> isInstalled() async =>
      await _channel.invokeMethod<bool>('isInstalled') ?? false;

  /// Opens a WhatsApp chat for [number] (a wa.me deep link).
  Future<void> openChat(String number) =>
      _channel.invokeMethod<void>('openChat', {'number': number});

  /// Digit-normalized numbers of contacts WhatsApp has synced. Only meaningful for
  /// "contacts only" mode; needs READ_CONTACTS.
  Future<Set<String>> whatsAppNumbers() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('whatsAppNumbers') ?? [];
    return raw.cast<String>().toSet();
  }

  /// Opt-in probe: temporarily adds each number as a local-only contact, waits up to
  /// [timeout] for WhatsApp to sync, and returns number -> hasWhatsApp. Best-effort
  /// (sync timing is not guaranteed). Needs WRITE_CONTACTS.
  Future<Map<String, bool>> scanNumbers(
    List<String> numbers, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('scanNumbers', {
      'numbers': numbers,
      'timeoutMs': timeout.inMilliseconds,
    });
    return (raw ?? {}).map((k, v) => MapEntry(k as String, v as bool));
  }

  /// Removes any leftover probe contacts (safety net after an interrupted scan).
  Future<void> cleanupProbes() => _channel.invokeMethod<void>('cleanupProbes');
}
