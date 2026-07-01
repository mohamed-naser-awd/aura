import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/contacts/contacts_screen.dart';
import 'services/call_log_ingest.dart';
import 'services/whatsapp_scan_service.dart';

/// Root widget. Wires the router and theme; the actual screens live under
/// `lib/features/`. The initial route is decided by [AuraRouter] based on whether
/// Aura is already the default phone app (onboarding gate). The call window runs a
/// separate entrypoint ([callUiMain]), so this engine is always the main app.
class AuraApp extends ConsumerWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Keep call-log recording + the opt-in WhatsApp scan alive for the app lifetime.
    ref.watch(callLogIngestProvider);
    ref.watch(whatsAppScanServiceProvider);
    // Warm up the heavy per-tab data in the background at launch (read, don't watch, so this
    // widget doesn't rebuild) — by the time a tab is opened its data is already cached.
    ref.read(contactsProvider);
    ref.read(recentCallsProvider);
    ref.read(blockedNumbersProvider);
    ref.read(whatsAppInstalledProvider);
    return MaterialApp.router(
      title: 'Aura',
      debugShowCheckedModeBanner: false,
      theme: AuraTheme.light,
      darkTheme: AuraTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
