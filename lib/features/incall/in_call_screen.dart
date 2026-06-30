import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/audio_route.dart';
import '../camera/camera_capture_screen.dart';
import 'active_calls.dart';

/// Full-screen in-call UI (mute / audio device / keypad / hang up).
class InCallScreen extends ConsumerStatefulWidget {
  const InCallScreen({super.key});

  @override
  ConsumerState<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends ConsumerState<InCallScreen> {
  bool _showKeypad = false;
  String _dtmf = '';

  void _sendDtmf(String? callId, String digit) {
    if (callId != null) ref.read(telecomServiceProvider).dtmf(callId, digit);
    setState(() => _dtmf += digit);
  }

  /// 2 devices → toggle straight to the other; 3+ → show the picker.
  void _onAudioTap(AudioRouteState audio) {
    final routes = audio.supportedRoutes;
    if (routes.length <= 1) return;
    if (routes.length == 2) {
      final next = routes.firstWhere((r) => r != audio.route, orElse: () => routes.first);
      ref.read(telecomServiceProvider).setAudioRoute(next);
    } else {
      _pickAudioDevice(audio);
    }
  }

  Future<void> _pickAudioDevice(AudioRouteState audio) async {
    final telecom = ref.read(telecomServiceProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final route in audio.supportedRoutes)
              ListTile(
                leading: Icon(AudioRoutes.icon(route)),
                title: Text(AudioRoutes.label(route)),
                trailing: route == audio.route ? const Icon(Icons.check) : null,
                onTap: () {
                  telecom.setAudioRoute(route);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(activeCallsProvider);
    final call = ref.read(activeCallsProvider.notifier).foreground;
    final telecom = ref.read(telecomServiceProvider);
    final audio = ref.watch(audioStateProvider).valueOrNull ?? AudioRouteState.empty;
    // The ongoing-call notification's "change device" action signals us to open the picker.
    ref.listen(audioPickerSignalProvider, (_, __) {
      final current = ref.read(audioStateProvider).valueOrNull ?? AudioRouteState.empty;
      _pickAudioDevice(current);
    });
    final muted = audio.muted;
    final hasName = call?.name != null && call!.name!.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _showKeypad
                      ? _DtmfPad(
                          digits: _dtmf,
                          onKey: (d) => _sendDtmf(call?.callId, d),
                        )
                      : _CallInfo(
                          label: call?.displayLabel ?? 'Unknown',
                          number: hasName ? call.number : null,
                        ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Toggle(
                      icon: muted ? Icons.mic_off : Icons.mic,
                      label: 'Mute',
                      active: muted,
                      onTap: () => telecom.setMuted(!muted),
                    ),
                    _Toggle(
                      icon: _showKeypad ? Icons.dialpad_outlined : Icons.dialpad,
                      label: 'Keypad',
                      active: _showKeypad,
                      onTap: () => setState(() => _showKeypad = !_showKeypad),
                    ),
                    _Toggle(
                      icon: AudioRoutes.icon(audio.route),
                      label: AudioRoutes.label(audio.route),
                      active: audio.route != AudioRoutes.earpiece,
                      onTap: () => _onAudioTap(audio),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FloatingActionButton.large(
                  heroTag: 'hangup',
                  backgroundColor: Colors.red,
                  onPressed: call == null ? null : () => telecom.end(call.callId),
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
                const SizedBox(height: 32),
              ],
            ),
            // Separate camera button, top-right corner.
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.photo_camera),
                tooltip: 'Camera',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallInfo extends StatelessWidget {
  const _CallInfo({required this.label, this.number});
  final String label;
  final String? number;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person, size: 96),
          const SizedBox(height: 16),
          Text(label, style: Theme.of(context).textTheme.headlineSmall),
          if (number != null) ...[
            const SizedBox(height: 4),
            Text(number!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          const Text('On call'),
        ],
      ),
    );
  }
}

/// In-call DTMF dialpad (sends tones to the active call).
class _DtmfPad extends StatelessWidget {
  const _DtmfPad({required this.digits, required this.onKey});
  final String digits;
  final void Function(String) onKey;

  static const _keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: Text(digits, style: Theme.of(context).textTheme.headlineSmall),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            childAspectRatio: 1.8,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 40),
            children: [
              for (final k in _keys)
                InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: () => onKey(k),
                  child: Center(
                    child: Text(k, style: Theme.of(context).textTheme.headlineMedium),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        IconButton.filled(
          isSelected: active,
          style: IconButton.styleFrom(
            backgroundColor: active ? scheme.primary : scheme.surfaceContainerHighest,
            foregroundColor: active ? scheme.onPrimary : scheme.onSurface,
          ),
          onPressed: onTap,
          icon: Icon(icon),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}
