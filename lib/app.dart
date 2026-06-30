import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';
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
