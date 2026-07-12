import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide Group;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../core/phone_number.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/models/sim_account.dart';
import '../contacts/contact_detail_screen.dart';
import '../contacts/contacts_screen.dart';
import 'share_contact.dart';

/// Shared bottom-sheet action menu for a phone number. Used by the recents list, the dialer
/// results, and anywhere else that needs the per-number actions (call, WhatsApp, block, …).
///
/// The sheet is scrollable so a tall menu never clips its lower items (e.g. Block/Unblock).
/// [statusText]/[headerIcon] let the caller decorate the header (recents passes the call
/// disposition); [onDetails] adds a "Details" item only when the caller can show one.
Future<void> showContactMenu(
  BuildContext context,
  WidgetRef ref, {
  required String number,
  String? name,
  IconData headerIcon = Icons.person,
  Color? headerIconColor,
  String? statusText,
  VoidCallback? onDetails,
}) {
  final waInstalled = ref.read(whatsAppInstalledProvider).valueOrNull ?? false;
  final blocked = ref.read(blockedNumbersProvider).valueOrNull ?? const <String>{};
  final isBlocked = blocked.any((b) => PhoneNumber.suffix(b) == PhoneNumber.suffix(number));

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(child: Icon(headerIcon, color: headerIconColor)),
              title: Text(name ?? number, style: Theme.of(sheet).textTheme.titleMedium),
              subtitle: statusText == null
                  ? (name != null ? Text(number) : null)
                  : Text(
                      name != null ? '$number\n$statusText' : statusText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
              isThreeLine: name != null && statusText != null,
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
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => ContactDetailScreen(number: number)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share contact'),
              onTap: () {
                Navigator.pop(sheet);
                shareContact(context, ref, number: number, name: name);
              },
            ),
            if (name == null)
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Add to contacts'),
                onTap: () async {
                  Navigator.pop(sheet);
                  await FlutterContacts.openExternalInsert(Contact()..phones = [Phone(number)]);
                  ref.invalidate(contactsProvider);
                },
              ),
            if (onDetails != null)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Details'),
                onTap: () {
                  Navigator.pop(sheet);
                  onDetails();
                },
              ),
            ListTile(
              leading: Icon(isBlocked ? Icons.check_circle_outline : Icons.block,
                  color: isBlocked ? null : Colors.red),
              title: Text(isBlocked ? 'Unblock' : 'Block',
                  style: TextStyle(color: isBlocked ? null : Colors.red)),
              onTap: () {
                Navigator.pop(sheet);
                if (isBlocked) {
                  ref.read(blocklistRepositoryProvider).unblock(number);
                } else {
                  confirmAndBlock(context, ref, number: number, name: name);
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Confirm before adding a number to the blocklist. Blocking is silent and easy to do by mistake,
/// so gate it behind a dialog; unblocking stays immediate. No-op if the user cancels.
Future<void> confirmAndBlock(
  BuildContext context,
  WidgetRef ref, {
  required String number,
  String? name,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Block number?'),
      content: Text('Calls from ${name ?? number} will be rejected automatically. '
          'You can unblock any time.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(blocklistRepositoryProvider).block(number);
  }
}

Future<void> _placeCall(WidgetRef ref, String number) async {
  final settings = ref.read(settingsRepositoryProvider);
  final simId =
      (await settings.simMode()) == SimSelectionMode.fixed ? await settings.defaultSimId() : null;
  await ref.read(telecomServiceProvider).placeCall(number, phoneAccountId: simId);
}
