import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../core/phone_number.dart';

/// Searchable contacts list. Returns the chosen phone number (or null) via [close].
/// Constructed with the already-loaded contacts so it needs no async/permission work.
class ContactSearchDelegate extends SearchDelegate<String?> {
  ContactSearchDelegate(this.contacts) : super(searchFieldLabel: 'Search contacts');

  final List<Contact> contacts;
  static const _cap = 60;

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final q = query.trim().toLowerCase();
    final qd = PhoneNumber.digits(query);
    final rows = <_Row>[];

    for (final c in contacts) {
      final nameMatch = q.isNotEmpty && c.displayName.toLowerCase().contains(q);
      for (final p in c.phones) {
        final numMatch = qd.isNotEmpty && PhoneNumber.digits(p.number).contains(qd);
        if (q.isEmpty || nameMatch || numMatch) {
          rows.add(_Row(name: c.displayName, number: p.number));
          if (rows.length >= _cap) break;
        }
      }
      if (rows.length >= _cap) break;
    }

    if (rows.isEmpty) {
      return const Center(child: Text('No matching contacts'));
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        return ListTile(
          leading: CircleAvatar(child: Text(r.name.isEmpty ? '?' : r.name[0])),
          title: Text(r.name.isEmpty ? r.number : r.name),
          subtitle: r.name.isEmpty ? null : Text(r.number),
          onTap: () => close(context, r.number),
        );
      },
    );
  }
}

class _Row {
  const _Row({required this.name, required this.number});
  final String name;
  final String number;
}
