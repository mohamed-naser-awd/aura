import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phone_number.dart';
import 'contacts_screen.dart';

/// Full-screen multi-select contacts picker. Returns (via [Navigator.pop]) the final set of
/// normalized phone numbers — every number of each checked contact plus any checked
/// "raw number" rows. Existing members passed in [initialSelected] are pre-checked and can
/// be un-checked to remove them.
///
/// Usage:
/// ```dart
/// final numbers = await Navigator.of(context).push<List<String>>(
///   MaterialPageRoute(builder: (_) => ContactPickerScreen(initialSelected: current)),
/// );
/// ```
class ContactPickerScreen extends ConsumerStatefulWidget {
  const ContactPickerScreen({
    this.initialSelected = const {},
    this.title = 'Select contacts',
    super.key,
  });

  /// Normalized numbers already selected (e.g. current group members).
  final Set<String> initialSelected;
  final String title;

  @override
  ConsumerState<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends ConsumerState<ContactPickerScreen> {
  final Set<String> _checkedContactIds = {};
  final Set<String> _checkedRawNumbers = {};
  List<String> _rawNumbers = const [];
  List<Contact> _contacts = const [];
  bool _initialized = false;
  String _query = '';

  void _initSelection(List<Contact> contacts) {
    if (_initialized) return;
    _initialized = true;
    _contacts = contacts;

    final initial = widget.initialSelected;
    final covered = <String>{};
    for (final c in contacts) {
      final nums = c.phones
          .map((p) => PhoneNumber.normalize(p.number))
          .where((n) => n.isNotEmpty)
          .toSet();
      if (nums.any(initial.contains)) _checkedContactIds.add(c.id);
      covered.addAll(nums);
    }
    // Members not matched to any contact: show as raw rows so they aren't silently dropped.
    _rawNumbers = initial.where((n) => !covered.contains(n)).toList();
    _checkedRawNumbers.addAll(_rawNumbers);
  }

  List<String> _result() {
    final out = <String>{};
    for (final c in _contacts) {
      if (!_checkedContactIds.contains(c.id)) continue;
      for (final p in c.phones) {
        final n = PhoneNumber.normalize(p.number);
        if (n.isNotEmpty) out.add(n);
      }
    }
    out.addAll(_checkedRawNumbers);
    return out.toList();
  }

  int get _selectedCount => _checkedContactIds.length + _checkedRawNumbers.length;

  bool _matches(Contact c) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if (c.displayName.toLowerCase().contains(q)) return true;
    final qd = PhoneNumber.digits(_query);
    return qd.isNotEmpty && c.phones.any((p) => PhoneNumber.digits(p.number).contains(qd));
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_result()),
            child: Text('Done${_selectedCount > 0 ? ' ($_selectedCount)' : ''}'),
          ),
        ],
      ),
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load contacts: $e')),
        data: (contacts) {
          _initSelection(contacts);
          final filtered = contacts.where(_matches).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search name or number',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    // Members not matched to a contact (still removable).
                    for (final n in _rawNumbers)
                      CheckboxListTile(
                        value: _checkedRawNumbers.contains(n),
                        title: Text(n),
                        subtitle: const Text('Not in contacts'),
                        secondary: const Icon(Icons.dialpad),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _checkedRawNumbers.add(n);
                          } else {
                            _checkedRawNumbers.remove(n);
                          }
                        }),
                      ),
                    for (final c in filtered)
                      CheckboxListTile(
                        value: _checkedContactIds.contains(c.id),
                        title: Text(c.displayName.isEmpty ? '(no name)' : c.displayName),
                        subtitle: c.phones.isEmpty
                            ? null
                            : Text(c.phones.map((p) => p.number).join(', ')),
                        secondary: CircleAvatar(
                          child: Text(c.displayName.isEmpty ? '?' : c.displayName[0]),
                        ),
                        onChanged: c.phones.isEmpty
                            ? null
                            : (v) => setState(() {
                                  if (v == true) {
                                    _checkedContactIds.add(c.id);
                                  } else {
                                    _checkedContactIds.remove(c.id);
                                  }
                                }),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
