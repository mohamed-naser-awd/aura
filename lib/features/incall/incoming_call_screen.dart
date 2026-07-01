import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'active_calls.dart';

/// Full-screen incoming-call UI. Presentational — lifecycle (which screen, when to close)
/// is owned by [CallHost].
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    // Repeating shake to draw attention to the Answer button (mimics a vibrating phone).
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(activeCallsProvider); // rebuild on call changes
    final call = ref.read(activeCallsProvider.notifier).ringing;
    final telecom = ref.read(telecomServiceProvider);
    final hasName = call?.name != null && call!.name!.isNotEmpty;
    final number = call?.number;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const Icon(Icons.person, size: 96),
            const SizedBox(height: 16),
            Text(
              call?.displayLabel ?? 'Incoming call',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (hasName && call.number != null) ...[
              const SizedBox(height: 4),
              Text(call.number!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            const Text('Incoming call'),
            const Spacer(),
            // Quick actions.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _QuickAction(
                  icon: Icons.block,
                  label: 'Block',
                  color: Colors.redAccent,
                  onTap: call == null || number == null
                      ? null
                      : () {
                          telecom.reject(call.callId);
                          telecom.blockNumber(number);
                        },
                ),
                const SizedBox(width: 32),
                _QuickAction(
                  icon: Icons.phone_callback,
                  label: 'Call back',
                  color: Theme.of(context).colorScheme.primary,
                  onTap: call == null || number == null
                      ? null
                      : () => telecom.callBack(call.callId, number),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Primary answer / decline — small, icon-only.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallIcon(
                  icon: Icons.call_end,
                  color: Colors.red,
                  tooltip: 'Decline',
                  onTap: call == null ? null : () => telecom.reject(call.callId),
                ),
                _AnimatedAnswer(
                  animation: _shake,
                  onTap: call == null ? null : () => telecom.answer(call.callId),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

/// A small, background-free call action icon.
class _CallIcon extends StatelessWidget {
  const _CallIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 44,
      color: color,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }
}

/// Green Answer icon that shakes to grab attention.
class _AnimatedAnswer extends StatelessWidget {
  const _AnimatedAnswer({required this.animation, required this.onTap});

  final Animation<double> animation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // Two quick wiggles then rest each cycle.
        final t = animation.value;
        final wiggle = t < 0.5 ? (0.5 - (t * 4 - 1).abs() * 0.5) : 0.0;
        final angle = wiggle * 0.5; // radians
        final scale = 1.0 + wiggle * 0.15;
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: _CallIcon(
        icon: Icons.call,
        color: Colors.green,
        tooltip: 'Answer',
        onTap: onTap,
      ),
    );
  }
}

/// A small labelled quick action (icon + caption, no background).
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: label,
          iconSize: 26,
          color: color,
          onPressed: onTap,
          icon: Icon(icon),
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
