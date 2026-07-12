import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/phone_number.dart';
import '../../core/providers.dart';
import '../../data/models/disconnect_kind.dart';
import '../../data/models/recent_call.dart';
import '../common/contact_context_menu.dart';
import '../contacts/contacts_screen.dart';

/// Recent calls — sectioned by day, with a per-entry context menu and details. Reads the system
/// call log (source of truth) merged with the who-ended sidecar via [recentCallsProvider], and
/// re-syncs on open + app resume so records missed while the app was closed self-heal.
class CallLogScreen extends ConsumerStatefulWidget {
  const CallLogScreen({super.key});

  @override
  ConsumerState<CallLogScreen> createState() => _CallLogScreenState();
}

class _CallLogScreenState extends ConsumerState<CallLogScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sync on open (the widget is built with warm cached data; force a fresh pull).
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.invalidate(recentCallsProvider));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(recentCallsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final callsAsync = ref.watch(recentCallsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recents')),
      body: callsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (calls) {
          if (calls.isEmpty) return const Center(child: Text('No calls yet'));
          // Build a flat list of day headers (String) interleaved with calls.
          final items = <Object>[];
          String? section;
          for (final c in calls) {
            final s = _sectionLabel(c.startTs);
            if (s != section) {
              items.add(s);
              section = s;
            }
            items.add(c);
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item is String) return _SectionHeader(item);
              return _CallTile(call: item as RecentCall);
            },
          );
        },
      ),
    );
  }
}

String _sectionLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat.yMMMd().format(d);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _CallTile extends ConsumerWidget {
  const _CallTile({required this.call});
  final RecentCall call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(contactNamesProvider)[PhoneNumber.suffix(call.number)];
    final disp = dispositionFor(
      direction: call.direction,
      connected: call.connectedTs != null,
      disconnectCode: call.disconnectCode,
    );
    final time = DateFormat.jm().format(call.startTs);
    final timing = callTimingText(
      start: call.startTs,
      connected: call.connectedTs,
      end: call.endTs,
    );

    return ListTile(
      leading: Tooltip(
        message: disp.label, // disposition lives on the icon; tap the icon to see it
        triggerMode: TooltipTriggerMode.tap,
        child: CircleAvatar(child: Icon(disp.icon, color: disp.color)),
      ),
      title: Text(name ?? call.number),
      subtitle: Text(timing.isEmpty ? time : '$time · $timing'),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showCallMenu(context, ref, call, name),
      ),
      onTap: () => _showCallMenu(context, ref, call, name),
      onLongPress: () => _showCallMenu(context, ref, call, name),
    );
  }
}

void _showCallMenu(BuildContext context, WidgetRef ref, RecentCall call, String? name) {
  final number = call.number;
  final disp = dispositionFor(
    direction: call.direction,
    connected: call.connectedTs != null,
    disconnectCode: call.disconnectCode,
  );
  final timing = callTimingText(
    start: call.startTs,
    connected: call.connectedTs,
    end: call.endTs,
  );
  final status = timing.isEmpty ? disp.label : '${disp.label} · $timing';

  showContactMenu(
    context,
    ref,
    number: number,
    name: name,
    headerIcon: disp.icon,
    headerIconColor: disp.color,
    statusText: status,
    onDetails: () => showDialog<void>(
      context: context,
      builder: (_) => _CallDetailsDialog(call: call, name: name),
    ),
  );
}

class _CallDetailsDialog extends StatelessWidget {
  const _CallDetailsDialog({required this.call, this.name});
  final RecentCall call;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final disp = dispositionFor(
      direction: call.direction,
      connected: call.connectedTs != null,
      disconnectCode: call.disconnectCode,
    );
    final ring = call.connectedTs != null
        ? call.connectedTs!.difference(call.startTs)
        : call.endTs?.difference(call.startTs);
    final talk = (call.connectedTs != null && call.endTs != null)
        ? call.endTs!.difference(call.connectedTs!)
        : null;

    // Who hung up (only meaningful for a connected call): local = You, remote = They.
    final endedBy = switch (DisconnectKind.fromAndroidCode(call.disconnectCode)) {
      DisconnectKind.local => 'You',
      DisconnectKind.remote => 'They',
      _ => null,
    };

    final rows = <(String, String)>[
      if (name != null) ('Name', name!),
      ('Number', call.number),
      ('Direction', call.direction == 'outgoing' ? 'Outgoing' : 'Incoming'),
      ('Result', disp.label),
      if (endedBy != null) ('Ended by', endedBy),
      ('When', DateFormat.yMMMd().add_jm().format(call.startTs)),
      ('Rang', ring != null ? formatCallDuration(ring) : '—'),
      ('Talk', talk != null ? formatCallDuration(talk) : '—'),
    ];

    return AlertDialog(
      title: const Text('Call details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: Text(value)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
