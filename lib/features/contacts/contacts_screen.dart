import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/phone_number.dart';
import '../common/call_button.dart';
import '../common/contact_avatar.dart';
import '../common/whatsapp_button.dart';
import 'contact_detail_screen.dart';

/// Read-only system contacts list. Used as the source when adding members to groups
/// and for placing calls.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _PermissionDenied(
          onGrant: () async {
            final granted = await FlutterContacts.requestPermission(readonly: true);
            if (granted) ref.invalidate(contactsProvider);
          },
        ),
        data: (contacts) => ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (context, i) {
            final c = contacts[i];
            final number = c.phones.isNotEmpty ? c.phones.first.number : '';
            return ListTile(
              leading: ContactAvatar(number: number, name: c.displayName),
              title: Text(c.displayName),
              subtitle: number.isEmpty ? null : Text(number),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WhatsAppButton(number: number),
                  CallButton(number: number),
                ],
              ),
              onTap: number.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ContactDetailScreen(number: number, contactId: c.id),
                        ),
                      ),
            );
          },
        ),
      ),
    );
  }
}

/// Shown when contacts permission is denied: explains and offers to grant / open settings.
class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.onGrant});

  final Future<void> Function() onGrant;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.contacts_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Aura needs contacts permission to show your contacts.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onGrant,
              icon: const Icon(Icons.lock_open),
              label: const Text('Grant contacts permission'),
            ),
            const SizedBox(height: 8),
            const TextButton(
              onPressed: openAppSettings,
              child: Text('Open app settings'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps a number's trailing digits → contact display name, for naming call entries.
final contactNamesProvider = Provider<Map<String, String>>((ref) {
  final contacts = ref.watch(contactsProvider).valueOrNull ?? const <Contact>[];
  final map = <String, String>{};
  for (final c in contacts) {
    if (c.displayName.isEmpty) continue;
    for (final p in c.phones) {
      final s = PhoneNumber.suffix(p.number);
      if (s.isNotEmpty) map.putIfAbsent(s, () => c.displayName);
    }
  }
  return map;
});

/// Maps a number's trailing digits → contact thumbnail bytes, for avatars in lists.
final contactPhotosProvider = Provider<Map<String, Uint8List>>((ref) {
  final contacts = ref.watch(contactsProvider).valueOrNull ?? const <Contact>[];
  final map = <String, Uint8List>{};
  for (final c in contacts) {
    final thumb = c.thumbnail;
    if (thumb == null || thumb.isEmpty) continue;
    for (final p in c.phones) {
      final s = PhoneNumber.suffix(p.number);
      if (s.isNotEmpty) map.putIfAbsent(s, () => thumb);
    }
  }
  return map;
});

/// Loads contacts (with phone numbers + thumbnails). Requests permission on first read.
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  if (!await FlutterContacts.requestPermission(readonly: true)) {
    throw 'Contacts permission denied';
  }
  return FlutterContacts.getContacts(withProperties: true, withThumbnail: true);
});
