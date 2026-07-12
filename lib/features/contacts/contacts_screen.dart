import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/phone_number.dart';
import '../../core/providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../common/call_button.dart';
import '../common/contact_avatar.dart';
import '../common/whatsapp_button.dart';
import 'contact_detail_screen.dart';

/// Read-only system contacts list with search. Used as the source when adding members to
/// groups and for placing calls.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Filter contacts by display name or by phone-number digits.
  List<Contact> _filter(List<Contact> contacts) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return contacts;
    final digits = PhoneNumber.digits(_query);
    return contacts.where((c) {
      if (c.displayName.toLowerCase().contains(q)) return true;
      return digits.isNotEmpty &&
          c.phones.any((p) => PhoneNumber.digits(p.number).contains(digits));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);
    // Watched once here (not per row) so each list row spins up zero provider subscriptions
    // while scrolling.
    final photos = ref.watch(contactPhotosProvider);
    final waInstalled = ref.watch(whatsAppInstalledProvider).valueOrNull ?? false;
    final waMode = ref.watch(whatsAppModeProvider).valueOrNull ?? WhatsAppMode.always;
    final waSuffixes = ref.watch(whatsAppDetectedSuffixesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name or number',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add contact',
        onPressed: () async {
          await FlutterContacts.openExternalInsert();
          ref.invalidate(contactsProvider);
        },
        child: const Icon(Icons.person_add),
      ),
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _PermissionDenied(
          onGrant: () async {
            final granted = await FlutterContacts.requestPermission(readonly: true);
            if (granted) ref.invalidate(contactsProvider);
          },
        ),
        data: (contacts) {
          final filtered = _filter(contacts);
          if (filtered.isEmpty) {
            return const Center(child: Text('No matching contacts'));
          }
          return ListView.builder(
            itemCount: filtered.length,
            // Fixed row extent → the list skips per-row height measurement while scrolling.
            prototypeItem: const ListTile(
              leading: CircleAvatar(radius: 20),
              title: Text('Contact'),
              subtitle: Text('number'),
            ),
            itemBuilder: (context, i) {
              final c = filtered[i];
              // Contacts are pre-filtered to those with a phone, so first is always present.
              final number = c.phones.first.number;
              final suffix = PhoneNumber.suffix(number);
              final showWhatsApp = waInstalled &&
                  (waMode == WhatsAppMode.always || waSuffixes.contains(suffix));
              return RepaintBoundary(
                child: ListTile(
                  leading: ContactAvatar(
                    number: number,
                    name: c.displayName,
                    photo: photos[suffix],
                  ),
                  title: Text(c.displayName),
                  subtitle: Text(number),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showWhatsApp)
                        IconButton(
                          tooltip: 'Open in WhatsApp',
                          icon: const FaIcon(FontAwesomeIcons.whatsapp,
                              color: WhatsAppButton.whatsAppGreen),
                          iconSize: 20,
                          onPressed: () => ref.read(whatsAppServiceProvider).openChat(number),
                        ),
                      CallButton(number: number),
                    ],
                  ),
                  onTap: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => ContactDetailScreen(number: number, contactId: c.id),
                    ),
                  ),
                ),
              );
            },
          );
        },
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
  final all = await FlutterContacts.getContacts(withProperties: true, withThumbnail: true);
  // Drop contacts with no phone number: they render as blank, non-tappable "?" rows and are
  // useless here (nothing to call). Every consumer keys off phone suffixes, so this is safe.
  return all.where((c) => c.phones.isNotEmpty).toList();
});
