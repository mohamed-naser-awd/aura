import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'active_calls.dart';
import 'in_call_screen.dart';
import 'incoming_call_screen.dart';

/// Minimal app shown in the call window. No router/onboarding/drift — just the call UI,
/// driven entirely by the live [activeCallsProvider].
class CallApp extends StatelessWidget {
  const CallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AuraTheme.light,
      darkTheme: AuraTheme.dark,
      themeMode: ThemeMode.system,
      home: const CallHost(),
    );
  }
}

/// Renders the right screen for the current call. The engine is cached/reused across calls,
/// so this never closes the window itself — native ([AuraInCallService]) finishes the
/// CallActivity when the last call ends. While waiting for the first call event it shows a
/// brief spinner (not black).
class CallHost extends ConsumerStatefulWidget {
  const CallHost({super.key});

  @override
  ConsumerState<CallHost> createState() => _CallHostState();
}

class _CallHostState extends ConsumerState<CallHost> {
  static const _callUi = MethodChannel('aura/call_ui');

  @override
  void initState() {
    super.initState();
    // Native (notification "change device" action) asks the in-call screen to open the picker.
    _callUi.setMethodCallHandler((call) async {
      if (call.method == 'openAudioPicker') {
        ref.read(audioPickerSignalProvider.notifier).state++;
      }
      return null;
    });
  }

  @override
  void dispose() {
    _callUi.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calls = ref.watch(activeCallsProvider);
    if (calls.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final ringing = calls.values.firstWhereOrNull((c) => c.isRinging);
    return ringing != null ? const IncomingCallScreen() : const InCallScreen();
  }
}
