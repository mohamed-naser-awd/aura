import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/models/audio_route.dart';
import '../data/models/call_event.dart';
import '../data/models/recent_call.dart';
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
///
/// The Android system call log is the source of truth for which calls exist (Android maintains
/// it even when Aura is closed, so it self-heals records missed while the app was down). On each
/// load we also drain the native who-ended queue into the drift sidecar and merge it in, so calls
/// Aura witnessed keep the who-ended disposition (feature #1). Calls Aura did not witness appear
/// without it rather than being dropped. Invalidated on Recents open / app resume ("sync on
/// launch").
final recentCallsProvider = FutureProvider<List<RecentCall>>((ref) async {
  final telecom = ref.watch(telecomServiceProvider);
  final repo = ref.watch(callLogRepositoryProvider);

  // 1. Drain the native who-ended queue into the sidecar. This queue is written from the
  //    InCallService on every witnessed call, in whatever engine is alive (even with the main
  //    Flutter engine dead), and cleared on read — so no double-recording across launches.
  for (final e in await telecom.takeDisconnectQueue()) {
    final cause = (e['cause'] as num?)?.toInt();
    final connectMs = (e['connectMillis'] as num?)?.toInt() ?? 0;
    final endMs = (e['endMillis'] as num?)?.toInt() ?? 0;
    await repo.record(
      number: (e['number'] as String?) ?? 'Unknown',
      direction: (e['direction'] as String?) ?? 'incoming',
      disconnectCode: cause == -1 ? null : cause,
      startTs: DateTime.fromMillisecondsSinceEpoch((e['startMillis'] as num?)?.toInt() ?? 0),
      connectedTs: connectMs > 0 ? DateTime.fromMillisecondsSinceEpoch(connectMs) : null,
      endTs: endMs > 0 ? DateTime.fromMillisecondsSinceEpoch(endMs) : null,
    );
  }

  // 2. System call log (base list) + sidecar (who-ended source), then merge.
  final systemRows = await telecom.getSystemCallLog(limit: 200);
  final sidecar = await repo.recent(limit: 400);
  return _mergeRecents(systemRows, sidecar);
});

/// Left-joins the system-log base rows with the who-ended sidecar. Each sidecar row is consumed
/// at most once (nearest start-time within tolerance, same direction, same trailing-digit suffix)
/// so back-to-back calls to the same number don't share one disconnect.
List<RecentCall> _mergeRecents(List<Map<dynamic, dynamic>> systemRows, List<CallEvent> sidecar) {
  const tolerance = Duration(seconds: 8);
  final pool = List<CallEvent>.from(sidecar);
  final out = <RecentCall>[];
  for (final row in systemRows) {
    final call = RecentCall.fromSystemLog(row);
    final suffix = PhoneNumber.suffix(call.number);
    var bestIdx = -1;
    var bestDelta = tolerance;
    if (suffix.isNotEmpty) {
      for (var i = 0; i < pool.length; i++) {
        final s = pool[i];
        if (s.direction != call.direction) continue;
        if (PhoneNumber.suffix(s.number) != suffix) continue;
        final delta = s.startTs.difference(call.startTs).abs();
        if (delta <= bestDelta) {
          bestDelta = delta;
          bestIdx = i;
        }
      }
    }
    if (bestIdx >= 0) {
      final s = pool.removeAt(bestIdx);
      out.add(call.withWhoEnded(
        connectedTs: s.connectedTs,
        endTs: s.endTs,
        disconnectCode: s.disconnectCode,
      ));
    } else {
      out.add(call);
    }
  }
  return out;
}

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

/// Trailing-digit suffixes of every number known to be on WhatsApp (synced ∪ probe cache),
/// precomputed once. Lets per-row WhatsApp checks be an O(1) set lookup instead of scanning
/// and re-merging the full number set on every list-row build (contacts-only mode).
final whatsAppDetectedSuffixesProvider = Provider<Set<String>>((ref) {
  final synced = ref.watch(whatsAppNumbersProvider).valueOrNull ?? const <String>{};
  final cached = ref.watch(whatsAppCacheProvider).valueOrNull ?? const <String>{};
  final out = <String>{};
  for (final n in synced.followedBy(cached)) {
    final s = PhoneNumber.suffix(n);
    if (s.isNotEmpty) out.add(s);
  }
  return out;
});
