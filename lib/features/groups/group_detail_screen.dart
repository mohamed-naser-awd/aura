import 'dart:io';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../data/db/app_database.dart';
import '../../data/models/sim_account.dart';
import '../common/call_button.dart';
import '../common/group_avatar.dart';
import '../common/ringtone_picker.dart';
import '../common/whatsapp_button.dart';
import '../contacts/contact_picker_screen.dart';

/// Configures a single group's rules:
///  - #3 mute, #5 ring-when-silent, #8 intense, #9 polite-decline (+ message)
///  - #7 default SIM
///  - members (numbers matched against incoming calls)
///  - #4 time-window rules
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({required this.groupId, super.key});

  final int groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_groupDetailProvider(groupId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await ref.read(groupsRepositoryProvider).deleteGroup(groupId);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) => _Body(data: data),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final _GroupDetail data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(groupsRepositoryProvider);
    final g = data.group;
    final sims = ref.watch(simAccountsProvider).valueOrNull ?? const <SimAccount>[];

    Future<void> save(Group updated) async {
      await repo.updateGroup(updated);
      ref.invalidate(_groupDetailProvider(g.id));
    }

    return ListView(
      children: [
        ListTile(
          leading: GroupAvatar(
            color: g.color,
            iconCodePoint: g.iconCodePoint,
            imagePath: g.imagePath,
            name: g.name,
            radius: 24,
          ),
          title: Text(g.name),
          subtitle: const Text('Tap to change avatar'),
          trailing: const Icon(Icons.edit),
          onTap: () => _editAppearance(context, g, save),
        ),
        ListTile(
          leading: const Icon(Icons.music_note),
          title: const Text('Ringtone'),
          subtitle: Text(g.ringtoneUri == null ? 'Default' : 'Custom'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final sel = await pickRingtone(context, current: g.ringtoneUri);
            if (sel != null) save(g.copyWith(ringtoneUri: Value(sel.uri)));
          },
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Mute incoming calls'),
          subtitle: const Text('Silence calls from this group (#3)'),
          value: g.muteEnabled,
          onChanged: (v) => save(g.copyWith(muteEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Ring even when silent'),
          subtitle: const Text('Override silent/vibrate for this group (#5)'),
          value: g.ringOverridesSilent,
          onChanged: (v) => save(g.copyWith(ringOverridesSilent: v)),
        ),
        SwitchListTile(
          title: const Text('Intense mode'),
          subtitle: const Text('Max volume + vibration if they call twice in 5 min (#8)'),
          value: g.intenseModeEnabled,
          onChanged: (v) => save(g.copyWith(intenseModeEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Polite decline (auto-SMS)'),
          subtitle: const Text('Reject and text back a message (#9)'),
          value: g.politeDeclineEnabled,
          onChanged: (v) => save(g.copyWith(politeDeclineEnabled: v)),
        ),
        if (g.politeDeclineEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              initialValue: g.politeDeclineMessage ?? '',
              decoration: const InputDecoration(labelText: 'Decline message'),
              maxLines: 2,
              onFieldSubmitted: (v) =>
                  save(g.copyWith(politeDeclineMessage: Value(v))),
            ),
          ),
        const Divider(),
        ListTile(
          title: const Text('Default SIM'),
          subtitle: Text(_simLabel(sims, g.defaultSimId)),
          trailing: const Icon(Icons.sim_card),
          onTap: () async {
            final chosen = await _pickSim(context, sims, g.defaultSimId);
            if (chosen != null) {
              save(g.copyWith(defaultSimId: Value(chosen.isEmpty ? null : chosen)));
            }
          },
        ),
        const Divider(),
        _MembersSection(data: data),
        const Divider(),
        _RulesSection(data: data),
      ],
    );
  }

  String _simLabel(List<SimAccount> sims, String? id) {
    if (id == null) return 'Use global default';
    return sims.where((s) => s.id == id).map((s) => s.label).firstOrNull ?? id;
  }

  Future<String?> _pickSim(BuildContext context, List<SimAccount> sims, String? current) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Use global default'),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final s in sims)
              ListTile(title: Text(s.label), onTap: () => Navigator.pop(context, s.id)),
          ],
        ),
      ),
    );
  }
}

const _groupColors = [
  0xFF5B6CFF, 0xFFEF5350, 0xFF66BB6A, 0xFFFFA726,
  0xFFAB47BC, 0xFF26C6DA, 0xFFEC407A, 0xFF8D6E63,
];

Future<String?> _pickGroupImage() async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512);
  if (x == null) return null;
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'group_avatars'));
  await dir.create(recursive: true);
  final dest = File(p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_${p.basename(x.path)}'));
  await File(x.path).copy(dest.path);
  return dest.path;
}

/// Bottom sheet to edit a group's avatar (color + icon + image). Applies once on "Done".
Future<void> _editAppearance(
  BuildContext context,
  Group g,
  Future<void> Function(Group) save,
) async {
  var color = g.color;
  int? icon = g.iconCodePoint;
  String? image = g.imagePath;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: GroupAvatar(
                  color: color, iconCodePoint: icon, imagePath: image, name: g.name, radius: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _groupColors)
                    GestureDetector(
                      onTap: () => setSheet(() => color = c),
                      child: CircleAvatar(
                        backgroundColor: Color(c),
                        child: c == color ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Icon'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('None'),
                    selected: icon == null,
                    onSelected: (_) => setSheet(() => icon = null),
                  ),
                  for (final ic in groupIconChoices)
                    InkWell(
                      onTap: () => setSheet(() => icon = ic.codePoint),
                      child: CircleAvatar(
                        backgroundColor: icon == ic.codePoint ? Color(color) : Colors.grey.shade300,
                        child: Icon(ic, color: icon == ic.codePoint ? Colors.white : Colors.black54, size: 20),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final path = await _pickGroupImage();
                      if (path != null) setSheet(() => image = path);
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('Pick image'),
                  ),
                  const SizedBox(width: 8),
                  if (image != null)
                    TextButton(
                      onPressed: () => setSheet(() => image = null),
                      child: const Text('Remove image'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    save(g.copyWith(
                      color: color,
                      iconCodePoint: Value(icon),
                      imagePath: Value(image),
                    ));
                    Navigator.pop(sheet);
                  },
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MembersSection extends ConsumerWidget {
  const _MembersSection({required this.data});
  final _GroupDetail data;

  Future<void> _editMembers(BuildContext context, WidgetRef ref) async {
    final current = data.members.map((m) => m.normalizedNumber).toSet();
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ContactPickerScreen(
          initialSelected: current,
          title: 'Edit members',
        ),
      ),
    );
    if (result == null) return; // cancelled — leave membership unchanged
    await ref.read(groupsRepositoryProvider).syncMembers(data.group.id, result);
    ref.invalidate(_groupDetailProvider(data.group.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('Members'),
          trailing: IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: 'Edit members',
            onPressed: () => _editMembers(context, ref),
          ),
        ),
        for (final m in data.members)
          ListTile(
            dense: true,
            leading: const Icon(Icons.person),
            title: Text(m.normalizedNumber),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WhatsAppButton(number: m.normalizedNumber, size: 18),
                CallButton(number: m.normalizedNumber, size: 20),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    await ref.read(groupsRepositoryProvider).removeMember(m.id);
                    ref.invalidate(_groupDetailProvider(data.group.id));
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RulesSection extends ConsumerWidget {
  const _RulesSection({required this.data});
  final _GroupDetail data;

  Future<void> _addRingWindow(BuildContext context, WidgetRef ref) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Ring from',
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 22, minute: 0),
      helpText: 'Ring until (then mute)',
    );
    if (end == null) return;
    await ref.read(groupsRepositoryProvider).addRule(
          data.group.id,
          kind: 'ringWindow',
          startMinuteOfDay: start.hour * 60 + start.minute,
          endMinuteOfDay: end.hour * 60 + end.minute,
        );
    ref.invalidate(_groupDetailProvider(data.group.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('Time rules'),
          subtitle: const Text('e.g. ring until 10 PM, then mute (#4)'),
          trailing: IconButton(
            icon: const Icon(Icons.add_alarm),
            onPressed: () => _addRingWindow(context, ref),
          ),
        ),
        for (final r in data.rules)
          ListTile(
            dense: true,
            leading: Icon(r.kind == 'ringWindow' ? Icons.notifications_active : Icons.notifications_off),
            title: Text(
              '${r.kind == 'ringWindow' ? 'Ring' : 'Mute'} '
              '${_fmt(r.startMinuteOfDay)}–${_fmt(r.endMinuteOfDay)}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () async {
                await ref.read(groupsRepositoryProvider).removeRule(r.id);
                ref.invalidate(_groupDetailProvider(data.group.id));
              },
            ),
          ),
      ],
    );
  }

  String _fmt(int minuteOfDay) {
    final h = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
    final m = (minuteOfDay % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _GroupDetail {
  const _GroupDetail({required this.group, required this.members, required this.rules});
  final Group group;
  final List<GroupMember> members;
  final List<Rule> rules;
}

final _groupDetailProvider = FutureProvider.family<_GroupDetail, int>((ref, id) async {
  final repo = ref.watch(groupsRepositoryProvider);
  return _GroupDetail(
    group: await repo.group(id),
    members: await repo.members(id),
    rules: await repo.rules(id),
  );
});
