import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../data/models/audio_route.dart';
import '../../data/models/call_event.dart';
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
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh once a second so the live call duration ticks.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _statusText(int? state) => switch (state) {
        CallState.dialing || CallState.connecting => 'Calling…',
        CallState.holding => 'On hold',
        CallState.ringing => 'Incoming',
        _ => 'On call',
      };

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
    final notifier = ref.read(activeCallsProvider.notifier);
    final active = notifier.activeCall;
    final held = notifier.heldCall;
    final waiting = notifier.waitingCall;
    final call = active ?? held ?? notifier.foreground; // the primary call shown
    final telecom = ref.read(telecomServiceProvider);
    final audio = ref.watch(audioStateProvider).valueOrNull ?? AudioRouteState.empty;
    // The ongoing-call notification's "change device" action signals us to open the picker.
    ref.listen(audioPickerSignalProvider, (_, __) {
      final current = ref.read(audioStateProvider).valueOrNull ?? AudioRouteState.empty;
      _pickAudioDevice(current);
    });
    final muted = audio.muted;
    final hasName = call?.name != null && call!.name!.isNotEmpty;
    final elapsed = call?.elapsed;
    final status = call == null
        ? ''
        : (call.isHolding
            ? 'On hold'
            : (elapsed != null ? formatCallClock(elapsed) : _statusText(call.state)));
    final onHold = active == null && held != null; // single call, parked on hold
    final endTarget = active ?? call;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Call-waiting: a second incoming call over the ongoing one.
                if (waiting != null)
                  _WaitingBanner(
                    label: waiting.displayLabel,
                    onAnswer: () => telecom.answer(waiting.callId),
                    onDecline: () => telecom.reject(waiting.callId),
                  ),
                // The other party parked on hold — tap / Swap to switch.
                if (held != null && active != null)
                  _HeldStrip(
                    label: held.displayLabel,
                    onSwap: () => telecom.unhold(held.callId),
                  ),
                Expanded(
                  child: _CallInfo(
                    label: call?.displayLabel ?? 'Unknown',
                    number: hasName ? call.number : null,
                    status: status,
                  ),
                ),
                // Dialpad slides in just above the controls (caller info stays at top).
                if (_showKeypad)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DtmfPad(
                      digits: _dtmf,
                      onKey: (d) => _sendDtmf(active?.callId ?? call?.callId, d),
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
                      icon: onHold ? Icons.play_arrow : Icons.pause,
                      label: 'Hold',
                      active: onHold,
                      onTap: () {
                        if (active != null) {
                          telecom.hold(active.callId);
                        } else if (held != null) {
                          telecom.unhold(held.callId);
                        }
                      },
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
                FractionallySizedBox(
                  widthFactor: 0.8,
                  child: _SlideToEnd(
                    onEnd: endTarget == null ? null : () => telecom.end(endTarget.callId),
                  ),
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
  const _CallInfo({required this.label, required this.status, this.number});
  final String label;
  final String status;
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
          Text(status, style: Theme.of(context).textTheme.titleMedium),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: Text(digits, style: Theme.of(context).textTheme.headlineSmall),
        ),
        GridView.count(
          crossAxisCount: 3,
          childAspectRatio: 2.2,
          shrinkWrap: true,
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

/// A call parked on hold, shown above the active call. Tap or "Swap" to switch to it.
class _HeldStrip extends StatelessWidget {
  const _HeldStrip({required this.label, required this.onSwap});
  final String label;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: const Icon(Icons.pause_circle_outline),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: const Text('On hold'),
          trailing: TextButton.icon(
            onPressed: onSwap,
            icon: const Icon(Icons.swap_calls),
            label: const Text('Swap'),
          ),
          onTap: onSwap,
        ),
      ),
    );
  }
}

/// Call-waiting banner: a second incoming call over the ongoing one (Answer / Decline).
class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner({required this.label, required this.onAnswer, required this.onDecline});
  final String label;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium),
                  const Text('Incoming call'),
                ],
              ),
            ),
            IconButton(
              onPressed: onDecline,
              tooltip: 'Decline',
              icon: const Icon(Icons.call_end, color: Colors.red),
            ),
            IconButton(
              onPressed: onAnswer,
              tooltip: 'Answer',
              icon: const Icon(Icons.call, color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slide-to-end control for the active call: drag the red handle across to hang up.
class _SlideToEnd extends StatefulWidget {
  const _SlideToEnd({required this.onEnd});

  /// Called when the user slides past the end threshold. Null disables the control.
  final VoidCallback? onEnd;

  @override
  State<_SlideToEnd> createState() => _SlideToEndState();
}

class _SlideToEndState extends State<_SlideToEnd> {
  static const double _height = 64;
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onEnd != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDx = constraints.maxWidth - _height;
        final progress = maxDx > 0 ? (_dx / maxDx).clamp(0.0, 1.0) : 0.0;
        return Container(
          height: _height,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - progress).clamp(0.0, 1.0),
                child: const Text('Slide to end call'),
              ),
              Positioned(
                left: _dx,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  onHorizontalDragUpdate: !enabled
                      ? null
                      : (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, maxDx)),
                  onHorizontalDragEnd: !enabled
                      ? null
                      : (_) {
                          if (_dx >= maxDx * 0.75) {
                            widget.onEnd!.call();
                          }
                          setState(() => _dx = 0);
                        },
                  child: Container(
                    width: _height,
                    height: _height,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
