import 'package:flutter/material.dart';

import '../../data/models/sim_account.dart';

/// Result of the long-press SIM popup (feature #5).
class SimPickResult {
  const SimPickResult({required this.simId, required this.alwaysAsk, required this.persist});

  /// Chosen SIM id, or null when "always ask" is selected.
  final String? simId;
  final bool alwaysAsk;

  /// true = change forever (save as default); false = this call only.
  final bool persist;
}

/// Shows the long-press SIM selector. Lets the user pick "Always ask" or a specific SIM,
/// with a checkbox to apply the choice forever vs. just for the next call.
Future<SimPickResult?> showSimPickerSheet(
  BuildContext context, {
  required List<SimAccount> sims,
  required String? currentSimId,
  required bool currentAlwaysAsk,
}) {
  return showModalBottomSheet<SimPickResult>(
    context: context,
    showDragHandle: true,
    builder: (context) => _SimPickerSheet(
      sims: sims,
      currentSimId: currentSimId,
      currentAlwaysAsk: currentAlwaysAsk,
    ),
  );
}

class _SimPickerSheet extends StatefulWidget {
  const _SimPickerSheet({
    required this.sims,
    required this.currentSimId,
    required this.currentAlwaysAsk,
  });

  final List<SimAccount> sims;
  final String? currentSimId;
  final bool currentAlwaysAsk;

  @override
  State<_SimPickerSheet> createState() => _SimPickerSheetState();
}

class _SimPickerSheetState extends State<_SimPickerSheet> {
  bool _persist = false;

  void _apply({String? simId, required bool alwaysAsk}) {
    Navigator.pop(
      context,
      SimPickResult(simId: simId, alwaysAsk: alwaysAsk, persist: _persist),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('SIM for calls', style: Theme.of(context).textTheme.titleLarge),
            // Set this first; tapping a SIM applies with this choice.
            CheckboxListTile(
              value: _persist,
              onChanged: (v) => setState(() => _persist = v ?? false),
              title: const Text('Remember'),
              subtitle: const Text('Save as default · otherwise just for the next call'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(),
            ListTile(
              leading: Icon(widget.currentAlwaysAsk ? Icons.check : Icons.help_outline),
              title: const Text('Always ask before calling'),
              onTap: () => _apply(simId: null, alwaysAsk: true),
            ),
            for (final sim in widget.sims)
              ListTile(
                leading: Icon(
                  !widget.currentAlwaysAsk && sim.id == widget.currentSimId
                      ? Icons.check
                      : Icons.sim_card,
                ),
                title: Text(sim.display),
                subtitle: sim.isDefault ? const Text('System default') : null,
                onTap: () => _apply(simId: sim.id, alwaysAsk: false),
              ),
          ],
        ),
      ),
    );
  }
}
