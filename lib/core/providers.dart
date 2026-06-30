import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/models/audio_route.dart';
import '../data/models/call_event.dart';
import '../data/native/audio_state_stream.dart';
import '../data/native/call_event_stream.dart';
import '../data/native/rules_exporter.dart';
import '../data/native/telecom_service.dart';
import '../data/native/whatsapp_service.dart';
import '../data/repositories/blocklist_repository.dart';
import '../data/repositories/call_log_repository.dart';
import '../data/repositories/contact_ringtones_repository.dart';
import '../data/repositories/groups_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/whatsapp_repository.dart';
import 'phone_number.dart';

/// Central dependency wiring. Kept as plain Riverpod providers (no codegen) so the app
/// graph is readable in one place; feature providers live next to their screens.

/// Local SQLite database (drift). Single instance for the app lifetime.
final databaseProvider = Provider<AuraDatabase>((ref) {
  final db = AuraDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Native telecom command bridge ("aura/telecom").
final telecomServiceProvider = Provider<TelecomService>((ref) => TelecomService());

/// Exports the rules snapshot to native whenever groups/rules change.
final rulesExporterProvider = Provider<RulesExporter>((ref) {
  return RulesExporter(ref.watch(databaseProvider), ref.watch(telecomServiceProvider));
});

/// Repositories.
final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository(ref.watch(databaseProvider), ref.watch(rulesExporterProvider));
});

final callLogRepositoryProvider = Provider<CallLogRepository>((ref) {
  return CallLogRepository(ref.watch(databaseProvider));
});

final blocklistRepositoryProvider = Provider<BlocklistRepository>((ref) {
  return BlocklistRepository(ref.watch(databaseProvider), ref.watch(rulesExporterProvider));
});

final contactRingtonesRepositoryProvider = Provider<ContactRingtonesRepository>((ref) {
  return ContactRingtonesRepository(
    ref.watch(databaseProvider),
    ref.watch(rulesExporterProvider),
  );
});

/// The custom ringtone set for a specific number (null = default).
final contactRingtoneProvider = FutureProvider.family<String?, String>((ref, number) {
  return ref.watch(contactRingtonesRepositoryProvider).ringtoneFor(number);
});

/// Groups that a given number belongs to (suffix match).
final groupsForNumberProvider = FutureProvider.family<List<Group>, String>((ref, number) async {
  final db = ref.watch(databaseProvider);
  final target = PhoneNumber.suffix(number);
  if (target.isEmpty) return const [];
  final groupIds = (await db.allMembers())
      .where((m) => PhoneNumber.suffix(m.normalizedNumber) == target)
      .map((m) => m.groupId)
      .toSet();
  if (groupIds.isEmpty) return const [];
  return (await db.allGroups()).where((g) => groupIds.contains(g.id)).toList();
});

/// Digit-normalized blocked numbers (for showing Block vs Unblock).
final blockedNumbersProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(blocklistRepositoryProvider).watchBlocked();
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

/// Whether Aura currently holds the default-dialer role (onboarding gate).
final isDefaultDialerProvider = FutureProvider<bool>((ref) {
  return ref.watch(telecomServiceProvider).isDefaultDialer();
});

/// Live stream of call lifecycle events from native ("aura/call_events").
final callEventStreamProvider = StreamProvider<NativeCallEvent>((ref) {
  return watchCallEvents();
});

/// Live in-call audio routing (current route / supported routes / mute).
final audioStateProvider = StreamProvider<AudioRouteState>((ref) {
  return watchAudioState();
});

/// SIM accounts available on the device.
final simAccountsProvider = FutureProvider((ref) {
  return ref.watch(telecomServiceProvider).getSimAccounts();
});

/// A number to pre-fill into the dialer (e.g. long-pressing a recent call). The dialer
/// consumes and clears it.
final dialerPrefillProvider = StateProvider<String?>((ref) => null);

/// Recent calls (most-recent first) for the call log and the dialer's empty state.
final recentCallsProvider = StreamProvider((ref) {
  return ref.watch(callLogRepositoryProvider).watchRecent();
});

/// WhatsApp quick-action bridge ("aura/whatsapp").
final whatsAppServiceProvider = Provider<WhatsAppService>((ref) => WhatsAppService());

/// Whether WhatsApp is installed (gates the quick-action button entirely).
final whatsAppInstalledProvider = FutureProvider<bool>((ref) {
  return ref.watch(whatsAppServiceProvider).isInstalled();
});

/// Current WhatsApp button mode (always / contacts-only).
final whatsAppModeProvider = FutureProvider<WhatsAppMode>((ref) {
  return ref.watch(settingsRepositoryProvider).whatsAppMode();
});

/// Digit-normalized numbers of WhatsApp-synced contacts (only used in contacts-only mode).
final whatsAppNumbersProvider = FutureProvider<Set<String>>((ref) async {
  final mode = await ref.watch(whatsAppModeProvider.future);
  if (mode != WhatsAppMode.contactsOnly) return <String>{};
  return ref.watch(whatsAppServiceProvider).whatsAppNumbers();
});

/// Probe + cache repository for the opt-in WhatsApp scan.
final whatsAppRepositoryProvider = Provider<WhatsAppRepository>((ref) {
  return WhatsAppRepository(ref.watch(databaseProvider), ref.watch(whatsAppServiceProvider));
});

/// Digit-normalized numbers cached (by the probe) as being on WhatsApp.
final whatsAppCacheProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(whatsAppRepositoryProvider).watchDetected();
});
