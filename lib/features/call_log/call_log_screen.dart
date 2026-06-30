import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/phone_number.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/models/disconnect_kind.dart';
import '../../data/models/sim_account.dart';
import '../contacts/contact_detail_screen.dart';
import '../contacts/contacts_screen.dart';

/// Recent calls — sectioned by day, with a per-entry context menu and details.
class CallLogScreen extends ConsumerWidget {
  const CallLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(_recentCallsProvider);
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
              return _CallTile(call: item as CallEvent);
            },
          );
        },
      ),
    );
  }
}

final _recentCallsProvider = StreamProvider<List<CallEvent>>((ref) {
  return ref.watch(callLogRepositoryProvider).watchRecent();
});

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
  final CallEvent call;

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

Future<void> _placeCall(WidgetRef ref, String number) async {
  final settings = ref.read(settingsRepositoryProvider);
  final simId =
      (await settings.simMode()) == SimSelectionMode.fixed ? await settings.defaultSimId() : null;
  await ref.read(telecomServiceProvider).placeCall(number, phoneAccountId: simId);
}

void _showCallMenu(BuildContext context, WidgetRef ref, CallEvent call, String? name) {
  final number = call.number;
  final waInstalled = ref.read(whatsAppInstalledProvider).valueOrNull ?? false;
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
  final blocked = ref.read(blockedNumbersProvider).valueOrNull ?? const <String>{};
  final isBlocked = blocked.any((b) => PhoneNumber.suffix(b) == PhoneNumber.suffix(number));

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: CircleAvatar(child: Icon(disp.icon, color: disp.color)),
            title: Text(name ?? number, style: Theme.of(sheet).textTheme.titleMedium),
            // Call status + rang/talk shown here too, not only in Details.
            subtitle: Text(name != null ? '$number\n$status' : status),
            isThreeLine: name != null,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.call, color: Colors.green),
            title: const Text('Call'),
            onTap: () {
              Navigator.pop(sheet);
              _placeCall(ref, number);
            },
          ),
          ListTile(
            leading: const Icon(Icons.dialpad),
            title: const Text('Edit before call'),
            onTap: () {
              Navigator.pop(sheet);
              ref.read(dialerPrefillProvider.notifier).state = number;
              context.go(Routes.dialer);
            },
          ),
          if (waInstalled)
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.whatsapp, color: Color(0xFF25D366)),
              title: const Text('WhatsApp'),
              onTap: () {
                Navigator.pop(sheet);
                ref.read(whatsAppServiceProvider).openChat(number);
              },
            ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('View contact'),
            onTap: () {
              Navigator.pop(sheet);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ContactDetailScreen(number: number)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Details'),
            onTap: () {
              Navigator.pop(sheet);
              showDialog<void>(
                context: context,
                builder: (_) => _CallDetailsDialog(call: call, name: name),
              );
            },
          ),
          ListTile(
            leading: Icon(isBlocked ? Icons.check_circle_outline : Icons.block,
                color: isBlocked ? null : Colors.red),
            title: Text(isBlocked ? 'Unblock' : 'Block',
                style: TextStyle(color: isBlocked ? null : Colors.red)),
            onTap: () {
              Navigator.pop(sheet);
              final repo = ref.read(blocklistRepositoryProvider);
              isBlocked ? repo.unblock(number) : repo.block(number);
            },
          ),
        ],
      ),
    ),
  );
}

class _CallDetailsDialog extends StatelessWidget {
  const _CallDetailsDialog({required this.call, this.name});
  final CallEvent call;
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

    final rows = <(String, String)>[
      if (name != null) ('Name', name!),
      ('Number', call.number),
      ('Direction', call.direction == 'outgoing' ? 'Outgoing' : 'Incoming'),
      ('Result', disp.label),
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
