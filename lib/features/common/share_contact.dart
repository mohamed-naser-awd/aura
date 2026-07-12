import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' hide Group;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/phone_number.dart';
import '../contacts/contacts_screen.dart';

/// Shares a contact as a vCard (`.vcf`) through the system share sheet.
///
/// When [contact] isn't supplied the saved system contact is resolved by number (suffix match);
/// for a bare number with no saved contact a minimal vCard is built from [name]/[number]. Falls
/// back to sharing the vCard as plain text if writing/sharing the file fails.
Future<void> shareContact(
  BuildContext context,
  WidgetRef ref, {
  required String number,
  String? name,
  Contact? contact,
}) async {
  var c = contact ?? _findByNumber(ref, number);
  // List contacts carry only thumbnails/basics; refetch full properties for a complete vCard.
  if (c != null) {
    c = await FlutterContacts.getContact(c.id, withProperties: true, withPhoto: true) ?? c;
  }

  final effectiveName = (name != null && name.isNotEmpty)
      ? name
      : (c?.displayName.isNotEmpty == true ? c!.displayName : null);
  final vcard = c?.toVCard() ?? _minimalVCard(effectiveName, number);
  final display = effectiveName ?? number;

  try {
    final dir = await getTemporaryDirectory();
    final safe = display.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final file = File('${dir.path}/${safe.isEmpty ? 'contact' : safe}.vcf');
    await file.writeAsString(vcard);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/x-vcard')], subject: display);
  } catch (_) {
    await Share.share(vcard, subject: display);
  }
}

Contact? _findByNumber(WidgetRef ref, String number) {
  final all = ref.read(contactsProvider).valueOrNull ?? const <Contact>[];
  final target = PhoneNumber.suffix(number);
  for (final x in all) {
    if (x.phones.any((p) => PhoneNumber.suffix(p.number) == target)) return x;
  }
  return null;
}

String _minimalVCard(String? name, String number) {
  final fn = (name == null || name.isEmpty) ? number : name;
  return 'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:$fn\r\nTEL:$number\r\nEND:VCARD\r\n';
}
