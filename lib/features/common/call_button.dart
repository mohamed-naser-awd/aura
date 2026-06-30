import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models/sim_account.dart';

/// Unified call action used across the app (recents, contacts, group members):
///  - **tap** places the call immediately (on the saved default SIM, if any);
///  - **long-press** opens the dialer with the number pre-filled for editing.
///
/// Uses [InkResponse] (no `IconButton` tooltip) so the long-press isn't swallowed.
class CallButton extends ConsumerWidget {
  const CallButton({required this.number, this.size = 22, super.key});

  final String number;
  final double size;

  Future<void> _call(WidgetRef ref) async {
    final settings = ref.read(settingsRepositoryProvider);
    final simId = (await settings.simMode()) == SimSelectionMode.fixed
        ? await settings.defaultSimId()
        : null;
    await ref.read(telecomServiceProvider).placeCall(number, phoneAccountId: simId);
  }

  void _editInDialer(WidgetRef ref, BuildContext context) {
    ref.read(dialerPrefillProvider.notifier).state = number;
    context.go(Routes.dialer);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (number.trim().isEmpty) return const SizedBox.shrink();
    return InkResponse(
      onTap: () => _call(ref),
      onLongPress: () => _editInDialer(ref, context),
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.call, color: Colors.green, size: size),
      ),
    );
  }
}
