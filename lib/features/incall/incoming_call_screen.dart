import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'active_calls.dart';

/// Full-screen incoming-call UI. Presentational — lifecycle (which screen, when to close)
/// is owned by [CallHost].
class IncomingCallScreen extends ConsumerWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(activeCallsProvider); // rebuild on call changes
    final call = ref.read(activeCallsProvider.notifier).ringing;
    final telecom = ref.read(telecomServiceProvider);
    final hasName = call?.name != null && call!.name!.isNotEmpty;

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundAction(
                  color: Colors.red,
                  icon: Icons.call_end,
                  label: 'Decline',
                  onTap: call == null ? null : () => telecom.reject(call.callId),
                ),
                _RoundAction(
                  color: Colors.green,
                  icon: Icons.call,
                  label: 'Answer',
                  onTap: call == null ? null : () => telecom.answer(call.callId),
                ),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FloatingActionButton.large(
          heroTag: label,
          backgroundColor: color,
          onPressed: onTap,
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}
