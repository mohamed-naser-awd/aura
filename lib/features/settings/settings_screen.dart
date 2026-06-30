import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers.dart';
import '../../data/models/sim_account.dart';
import '../../data/repositories/settings_repository.dart';

/// Global settings: default-dialer status, default SIM behavior (#5/#6), intense scope (#8).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDefault = ref.watch(isDefaultDialerProvider).valueOrNull ?? false;
    final settingsAsync = ref.watch(_settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(isDefault ? Icons.check_circle : Icons.error_outline,
                color: isDefault ? Colors.green : Colors.orange),
            title: const Text('Default phone app'),
            subtitle: Text(isDefault ? 'Aura is the default' : 'Not set — tap to fix'),
            onTap: isDefault
                ? null
                : () async {
                    await ref.read(telecomServiceProvider).requestDefaultDialerRole();
                    ref.invalidate(isDefaultDialerProvider);
                  },
          ),
          const Divider(),
          settingsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ListTile(title: Text('Error: $e')),
            data: (s) => _SettingsBody(settings: s),
          ),
        ],
      ),
    );
  }
}

class _SettingsState {
  const _SettingsState({
    required this.simMode,
    required this.intenseScope,
    required this.whatsAppMode,
  });
  final SimSelectionMode simMode;
  final String intenseScope;
  final WhatsAppMode whatsAppMode;
}

final _settingsProvider = FutureProvider<_SettingsState>((ref) async {
  final repo = ref.watch(settingsRepositoryProvider);
  return _SettingsState(
    simMode: await repo.simMode(),
    intenseScope: await repo.intenseScope(),
    whatsAppMode: await repo.whatsAppMode(),
  );
});

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.settings});
  final _SettingsState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(settingsRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('SIM selection', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        RadioGroup<SimSelectionMode>(
          groupValue: settings.simMode,
          onChanged: (v) async {
            if (v == null) return;
            await repo.setSimMode(v);
            ref.invalidate(_settingsProvider);
          },
          child: const Column(
            children: [
              RadioListTile<SimSelectionMode>(
                value: SimSelectionMode.alwaysAsk,
                title: Text('Always ask which SIM'),
              ),
              RadioListTile<SimSelectionMode>(
                value: SimSelectionMode.fixed,
                title: Text('Use a fixed default SIM'),
              ),
            ],
          ),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Intense mode', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        RadioGroup<String>(
          groupValue: settings.intenseScope,
          onChanged: (v) async {
            if (v == null) return;
            await repo.setIntenseScope(v);
            ref.invalidate(_settingsProvider);
          },
          child: const Column(
            children: [
              RadioListTile<String>(
                value: 'group',
                title: Text('Only configured groups'),
              ),
              RadioListTile<String>(
                value: 'all',
                title: Text('All callers'),
                subtitle: Text('Ramp up for anyone who calls twice in 5 minutes'),
              ),
            ],
          ),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('WhatsApp button', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        RadioGroup<WhatsAppMode>(
          groupValue: settings.whatsAppMode,
          onChanged: (v) async {
            if (v == null) return;
            await repo.setWhatsAppMode(v);
            ref.invalidate(_settingsProvider);
            ref.invalidate(whatsAppModeProvider);
            ref.invalidate(whatsAppNumbersProvider);
          },
          child: const Column(
            children: [
              RadioListTile<WhatsAppMode>(
                value: WhatsAppMode.always,
                title: Text('Always show'),
                subtitle: Text('Show for every number'),
              ),
              RadioListTile<WhatsAppMode>(
                value: WhatsAppMode.contactsOnly,
                title: Text('Contacts only'),
                subtitle: Text('Show only for saved WhatsApp contacts'),
              ),
            ],
          ),
        ),
        if (settings.whatsAppMode == WhatsAppMode.contactsOnly) const _WhatsAppScanTile(),
      ],
    );
  }
}

/// Opt-in probe: temporarily adds unknown recent/group numbers as local-only contacts,
/// waits for WhatsApp to sync, caches which are on WhatsApp, then deletes them. Enabling it
/// also turns on background re-scans on future launches.
class _WhatsAppScanTile extends ConsumerStatefulWidget {
  const _WhatsAppScanTile();

  @override
  ConsumerState<_WhatsAppScanTile> createState() => _WhatsAppScanTileState();
}

class _WhatsAppScanTileState extends ConsumerState<_WhatsAppScanTile> {
  bool _scanning = false;

  Future<void> _scan() async {
    if (!await Permission.contacts.request().isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contacts permission is needed to scan')),
        );
      }
      return;
    }
    setState(() => _scanning = true);
    await ref.read(settingsRepositoryProvider).setWhatsAppAutoScan(true);
    final count = await ref.read(whatsAppRepositoryProvider).scan();
    if (!mounted) return;
    setState(() => _scanning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(count == 0 ? 'Nothing new to scan' : 'Checked $count numbers')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detected = ref.watch(whatsAppCacheProvider).valueOrNull ?? const <String>{};
    return ListTile(
      leading: const Icon(Icons.travel_explore),
      title: const Text('Scan recents for WhatsApp'),
      subtitle: Text(
        _scanning
            ? 'Scanning… (adds temporary local contacts, then removes them)'
            : '${detected.length} numbers detected · auto-scans in the background',
      ),
      trailing: _scanning
          ? const SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : FilledButton(onPressed: _scan, child: const Text('Scan')),
    );
  }
}
