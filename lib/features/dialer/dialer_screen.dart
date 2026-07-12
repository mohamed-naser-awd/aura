import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/phone_number.dart';
import '../../core/providers.dart';
import '../../data/models/recent_call.dart';
import '../../data/models/sim_account.dart';
import '../common/contact_context_menu.dart';
import '../contacts/contact_search_delegate.dart';
import '../contacts/contacts_screen.dart';
import 'sim_picker_sheet.dart';

/// The dialpad. The effective SIM (carrier + slot) shows beside the call button; long-press
/// the call button (or tap the SIM label) to change it. A search button beside the number
/// opens contact search; typing also shows live matches.
class DialerScreen extends ConsumerStatefulWidget {
  const DialerScreen({super.key});

  @override
  ConsumerState<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends ConsumerState<DialerScreen> {
  final _controller = TextEditingController();
  String get _number => _controller.text;

  /// SIM chosen for the *next* call only (overrides the saved default).
  String? _oneShotSimId;
  bool _oneShotAlwaysAsk = false;

  /// Saved default SIM (loaded from settings) used to label the call button.
  SimSelectionMode? _simMode;
  String? _savedSimId;

  @override
  void initState() {
    super.initState();
    // Recompute the recents/matches area whenever the input changes.
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _loadSimDefaults();
    // Re-query SIMs now that the dialer is shown (permission may have been granted
    // after this provider was first read during onboarding, caching an empty list).
    Future.microtask(() => ref.invalidate(simAccountsProvider));
    // Pick up a number passed from elsewhere (e.g. long-pressing a recent call).
    final prefill = ref.read(dialerPrefillProvider);
    if (prefill != null && prefill.isNotEmpty) {
      _setNumber(prefill);
      Future.microtask(() => ref.read(dialerPrefillProvider.notifier).state = null);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Replace the whole number and move the cursor to the end.
  void _setNumber(String v) {
    _controller.value = TextEditingValue(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
  }

  /// Always fetch a fresh SIM list (reflects the current permission state).
  Future<List<SimAccount>> _freshSims() => ref.refresh(simAccountsProvider.future);

  Future<void> _loadSimDefaults() async {
    final settings = ref.read(settingsRepositoryProvider);
    final mode = await settings.simMode();
    final id = await settings.defaultSimId();
    if (mounted) {
      setState(() {
        _simMode = mode;
        _savedSimId = id;
      });
    }
  }

  /// The SIM that an outgoing call will use right now (null = ask/none resolved).
  SimAccount? _effectiveSim(List<SimAccount> sims) {
    if (sims.isEmpty || _oneShotAlwaysAsk) return null;
    var id = _oneShotSimId;
    if (id == null && _simMode == SimSelectionMode.fixed) id = _savedSimId;
    if (id != null) {
      final match = sims.firstWhereOrNull((s) => s.id == id);
      if (match != null) return match;
    }
    return sims.firstWhereOrNull((s) => s.isDefault) ?? sims.first;
  }

  Future<void> _openSearch(List<Contact> contacts) async {
    final picked = await showSearch<String?>(
      context: context,
      delegate: ContactSearchDelegate(contacts),
    );
    if (picked != null && picked.isNotEmpty) _setNumber(picked);
  }

  /// Insert at the cursor (so it composes with pasted text); fall back to append.
  void _tap(String d) {
    final text = _controller.text;
    final sel = _controller.selection;
    if (sel.start < 0 || sel.end < 0) {
      _setNumber(text + d);
      return;
    }
    final newText = text.replaceRange(sel.start, sel.end, d);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + d.length),
    );
  }

  void _backspace() {
    final text = _controller.text;
    if (text.isEmpty) return;
    final sel = _controller.selection;
    if (sel.start < 0) {
      _setNumber(text.substring(0, text.length - 1));
    } else if (sel.start != sel.end) {
      _controller.value = TextEditingValue(
        text: text.replaceRange(sel.start, sel.end, ''),
        selection: TextSelection.collapsed(offset: sel.start),
      );
    } else if (sel.start > 0) {
      _controller.value = TextEditingValue(
        text: text.replaceRange(sel.start - 1, sel.start, ''),
        selection: TextSelection.collapsed(offset: sel.start - 1),
      );
    }
  }

  void _clear() => _controller.clear();

  Future<void> _onSimLongPress() async {
    final settings = ref.read(settingsRepositoryProvider);
    final sims = await _freshSims();
    final currentSimId = _oneShotSimId ?? await settings.defaultSimId();
    if (!mounted) return;
    final result = await showSimPickerSheet(
      context,
      sims: sims,
      currentSimId: currentSimId,
      currentAlwaysAsk: _oneShotAlwaysAsk,
    );
    if (result == null) return;

    if (result.persist) {
      // Change forever: save the default SIM mode/value.
      await settings.setSimMode(
        result.alwaysAsk ? SimSelectionMode.alwaysAsk : SimSelectionMode.fixed,
      );
      if (result.simId != null) await settings.setDefaultSimId(result.simId!);
      setState(() {
        _oneShotSimId = null;
        _oneShotAlwaysAsk = false;
      });
      await _loadSimDefaults(); // refresh the label beside the call button
    } else {
      // This call only.
      setState(() {
        _oneShotSimId = result.simId;
        _oneShotAlwaysAsk = result.alwaysAsk;
      });
    }
  }

  Future<void> _call({String? number}) async {
    final target = number ?? _number;
    if (target.isEmpty) {
      // Empty field with recents showing: fill with the most recent number (don't call yet).
      final recents = ref.read(recentCallsProvider).valueOrNull;
      if (recents != null && recents.isNotEmpty) _setNumber(recents.first.number);
      return;
    }
    final telecom = ref.read(telecomServiceProvider);
    final settings = ref.read(settingsRepositoryProvider);

    String? simId = _oneShotSimId;
    var alwaysAsk = _oneShotAlwaysAsk;
    if (simId == null && !alwaysAsk) {
      final mode = await settings.simMode();
      alwaysAsk = mode == SimSelectionMode.alwaysAsk;
      simId = await settings.defaultSimId();
    }

    if (alwaysAsk) {
      final sims = await _freshSims();
      if (sims.length > 1) {
        if (!mounted) return;
        final result = await showSimPickerSheet(
          context,
          sims: sims,
          currentSimId: null,
          currentAlwaysAsk: true,
        );
        if (result == null) return;
        simId = result.simId;
      }
    }

    await telecom.placeCall(target, phoneAccountId: simId);
    setState(() {
      _oneShotSimId = null;
      _oneShotAlwaysAsk = false;
    });
  }

  /// Contacts whose any phone number contains the typed digits (capped).
  List<_Suggestion> _matches(List<Contact> contacts) {
    final typed = PhoneNumber.digits(_number);
    if (typed.isEmpty) return const [];
    final out = <_Suggestion>[];
    final seen = <String>{};
    for (final c in contacts) {
      for (final p in c.phones) {
        final digits = PhoneNumber.digits(p.number);
        if (digits.contains(typed) && seen.add(digits)) {
          out.add(_Suggestion(name: c.displayName, number: p.number));
          if (out.length >= 6) return out;
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // If a prefill arrives while the dialer is already mounted (tab switch), apply it.
    ref.listen(dialerPrefillProvider, (_, next) {
      if (next != null && next.isNotEmpty) {
        _setNumber(next);
        ref.read(dialerPrefillProvider.notifier).state = null;
      }
    });
    final simsAsync = ref.watch(simAccountsProvider);
    final sims = simsAsync.valueOrNull ?? const <SimAccount>[];
    final contacts = ref.watch(contactsProvider).valueOrNull ?? const <Contact>[];
    final matches = _matches(contacts);
    final eff = _effectiveSim(sims);
    final simLabel = _oneShotAlwaysAsk ? 'Ask each call' : (eff?.display ?? 'Default SIM');

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      // No soft keyboard (dialpad drives input) but stays focusable so
                      // the system copy/cut/paste toolbar is available.
                      keyboardType: TextInputType.none,
                      showCursor: true,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '+1 (123) 456-789',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search contacts',
                    onPressed: () => _openSearch(contacts),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Empty field → recents; once a digit is typed → live contact matches.
            // Both: tap = call, long-press = fill the field.
            Expanded(
              child: _number.isEmpty
                  ? _RecentsList(onCall: (n) => _call(number: n), onFill: _setNumber)
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final s = matches[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_outline),
                          title: Text(s.name.isEmpty ? s.number : s.name),
                          subtitle: s.name.isEmpty ? null : Text(s.number),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => showContactMenu(
                              context,
                              ref,
                              number: s.number,
                              name: s.name.isEmpty ? null : s.name,
                            ),
                          ),
                          onTap: () => _call(number: s.number),
                          onLongPress: () => _setNumber(s.number),
                        );
                      },
                    ),
            ),
            _Dialpad(onTap: _tap),
            const SizedBox(height: 12),
            // Wide call button: tap to call, long-press to change SIM. The chosen SIM
            // (carrier · slot) is shown inside the button.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onLongPress: _onSimLongPress,
                      child: SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => _call(),
                          icon: const Icon(Icons.call),
                          label: Text(
                            sims.isEmpty ? 'Call' : simLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_number.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      // Tap = delete one; long-press = clear all (InkResponse, no tooltip).
                      child: InkResponse(
                        onTap: _backspace,
                        onLongPress: _clear,
                        radius: 24,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.backspace_outlined),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Suggestion {
  const _Suggestion({required this.name, required this.number});
  final String name;
  final String number;
}

/// Recent calls shown in the dialer when the input is empty. Tap = call, long-press = fill.
class _RecentsList extends ConsumerWidget {
  const _RecentsList({required this.onCall, required this.onFill});

  final void Function(String number) onCall;
  final void Function(String number) onFill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentCallsProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (calls) {
        final seen = <String>{};
        final rows = <RecentCall>[];
        for (final c in calls) {
          if (seen.add(c.number)) {
            rows.add(c);
            if (rows.length >= 20) break;
          }
        }
        if (rows.isEmpty) return const Center(child: Text('No recent calls'));
        final names = ref.watch(contactNamesProvider);
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final c = rows[i];
            final outgoing = c.direction == 'outgoing';
            final name = names[PhoneNumber.suffix(c.number)];
            final timing = callTimingText(
              start: c.startTs,
              connected: c.connectedTs,
              end: c.endTs,
            );
            final durationText = timing.isEmpty ? '' : ' · $timing';
            return ListTile(
              dense: true,
              leading: Icon(
                outgoing ? Icons.call_made : Icons.call_received,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
              title: Text(name ?? c.number),
              subtitle: Text('${DateFormat.jm().add_MMMd().format(c.startTs)}$durationText'),
              trailing: IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => showContactMenu(context, ref, number: c.number, name: name),
              ),
              onTap: () => onCall(c.number),
              onLongPress: () => onFill(c.number),
            );
          },
        );
      },
    );
  }
}

class _Dialpad extends StatelessWidget {
  const _Dialpad({required this.onTap});
  final void Function(String) onTap;

  static const _keys = [
    ['1', ''], ['2', 'ABC'], ['3', 'DEF'],
    ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
    ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'],
    ['*', ''], ['0', '+'], ['#', ''],
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      childAspectRatio: 1.6,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        for (final k in _keys)
          InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: () => onTap(k[0]),
            onLongPress: k[0] == '0' ? () => onTap('+') : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(k[0], style: Theme.of(context).textTheme.headlineSmall),
                if (k[1].isNotEmpty)
                  Text(k[1], style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
      ],
    );
  }
}
