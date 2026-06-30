import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/incall/call_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: AuraApp(),
    ),
  );
}

/// Dedicated, lightweight entrypoint for the call window (CallActivity). Runs only the
/// call UI — no router, onboarding, drift, or plugins — so it starts fast.
@pragma('vm:entry-point')
void callUiMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: CallApp(),
    ),
  );
}
