import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide Group;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/phone_number.dart';
import '../../core/providers.dart';
import '../../data/db/app_database.dart';
import '../../data/models/disconnect_kind.dart';
import '../common/call_button.dart';
import '../common/contact_avatar.dart';
import '../common/ringtone_picker.dart';
import '../common/whatsapp_button.dart';
import 'contacts_screen.dart';

/// Detail page for a contact/number: an Info tab (avatar, numbers, ringtone, groups) and a
/// History tab (this number's calls). Opened from the contacts list and the recents menu.
class ContactDetailScreen extends ConsumerStatefulWidget {
  const ContactDetailScreen({required this.number, this.contactId, super.key});

  final String number;
  final String? contactId;

  @override
  ConsumerState<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends ConsumerState<ContactDetailScreen> {
  Contact? _contact;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Contact? c;
    if (widget.contactId != null) {
      c = await FlutterContacts.getContact(widget.contactId!,
          withProperties: true, withPhoto: true);
    } else {
      final all = ref.read(contactsProvider).valueOrNull ?? const <Contact>[];
      final target = PhoneNumber.suffix(widget.number);
      for (final x in all) {
        if (x.phones.any((p) => PhoneNumber.suffix(p.number) == target)) {
          c = x;
          break;
        }
      }
    }
    if (mounted) {
      setState(() {
        _contact = c;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _contact?.displayName.isNotEmpty == true ? _contact!.displayName : widget.number;
    final phones = (_contact?.phones.isNotEmpty == true)
        ? _contact!.phones.map((p) => p.number).toList()
        : [widget.number];
    final Uint8List? photo = _contact?.photo;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name),
          bottom: const TabBar(tabs: [Tab(text: 'Info'), Tab(text: 'History')]),
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _InfoTab(
                    name: name,
                    number: widget.number,
                    phones: phones,
                    photo: photo,
                  ),
                  _HistoryTab(number: widget.number),
                ],
              ),
      ),
    );
  }
}

class _InfoTab extends ConsumerWidget {
  const _InfoTab({
    required this.name,
    required this.number,
    required this.phones,
    required this.photo,
  });

  final String name;
  final String number;
  final List<String> phones;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ringtone = ref.watch(contactRingtoneProvider(number)).valueOrNull;
    final groups = ref.watch(groupsForNumberProvider(number)).valueOrNull ?? const <Group>[];

    return ListView(
      children: [
        const SizedBox(height: 16),
        Center(
          child: photo != null
              ? CircleAvatar(radius: 48, backgroundImage: MemoryImage(photo!))
              : ContactAvatar(number: number, name: name, radius: 48),
        ),
        const SizedBox(height: 12),
        Center(child: Text(name, style: Theme.of(context).textTheme.headlineSmall)),
        const SizedBox(height: 16),
        const Divider(),
        for (final n in phones)
          ListTile(
            leading: const Icon(Icons.phone),
            title: Text(n),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [WhatsAppButton(number: n), CallButton(number: n)],
            ),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.music_note),
          title: const Text('Ringtone'),
          subtitle: Text(ringtone == null ? 'Default' : 'Custom'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final sel = await pickRingtone(context, current: ringtone);
            if (sel == null) return;
            await ref.read(contactRingtonesRepositoryProvider).setRingtone(number, sel.uri);
            ref.invalidate(contactRingtoneProvider(number));
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.groups),
          title: const Text('Groups'),
          subtitle: Text(groups.isEmpty ? 'None' : groups.map((g) => g.name).join(', ')),
        ),
      ],
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.number});
  final String number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(recentCallsProvider);
    final target = PhoneNumber.suffix(number);
    return callsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (all) {
        final calls = all.where((c) => PhoneNumber.suffix(c.number) == target).toList();
        if (calls.isEmpty) return const Center(child: Text('No calls with this contact'));
        return ListView.builder(
          itemCount: calls.length,
          itemBuilder: (context, i) {
            final c = calls[i];
            final disp = dispositionFor(
              direction: c.direction,
              connected: c.connectedTs != null,
              disconnectCode: c.disconnectCode,
            );
            final timing = callTimingText(
              start: c.startTs,
              connected: c.connectedTs,
              end: c.endTs,
            );
            final when = DateFormat.yMMMd().add_jm().format(c.startTs);
            return ListTile(
              dense: true,
              leading: Icon(disp.icon, color: disp.color),
              title: Text(disp.label),
              subtitle: Text(timing.isEmpty ? when : '$when · $timing'),
            );
          },
        );
      },
    );
  }
}
