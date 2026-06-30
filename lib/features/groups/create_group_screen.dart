import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../contacts/contact_picker_screen.dart';

/// Two-step create-group wizard: Configure (name + color + rule toggles) → Members.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  static const _palette = [
    0xFF5B6CFF, 0xFFEF5350, 0xFF66BB6A, 0xFFFFA726,
    0xFFAB47BC, 0xFF26C6DA, 0xFFEC407A, 0xFF8D6E63,
  ];

  final _nameController = TextEditingController();
  final _messageController = TextEditingController();

  int _step = 0;
  int _color = _palette.first;
  bool _mute = false;
  bool _ringOverridesSilent = false;
  bool _intense = false;
  bool _politeDecline = false;
  List<String> _members = const [];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  bool get _canContinue => _nameController.text.trim().isNotEmpty;

  Future<void> _pickMembers() async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ContactPickerScreen(initialSelected: _members.toSet()),
      ),
    );
    if (result != null) setState(() => _members = result);
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    await ref.read(groupsRepositoryProvider).createGroupWith(
          name: _nameController.text.trim(),
          color: _color,
          mute: _mute,
          ringOverridesSilent: _ringOverridesSilent,
          intense: _intense,
          politeDecline: _politeDecline,
          politeMessage: _politeDecline ? _messageController.text.trim() : null,
          memberNumbers: _members,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: Stepper(
        currentStep: _step,
        onStepContinue: () {
          if (_step == 0) {
            if (_canContinue) setState(() => _step = 1);
          } else if (!_saving) {
            _confirm();
          }
        },
        onStepCancel: _step == 0 ? null : () => setState(() => _step = 0),
        controlsBuilder: (context, details) {
          final isLast = _step == 1;
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                FilledButton(
                  onPressed: _saving
                      ? null
                      : (_step == 0 && !_canContinue ? null : details.onStepContinue),
                  child: Text(isLast ? 'Confirm' : 'Next'),
                ),
                const SizedBox(width: 12),
                if (_step == 1)
                  TextButton(onPressed: details.onStepCancel, child: const Text('Back')),
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('Configure'),
            isActive: _step >= 0,
            content: _ConfigStep(
              nameController: _nameController,
              messageController: _messageController,
              palette: _palette,
              color: _color,
              onColor: (c) => setState(() => _color = c),
              mute: _mute,
              onMute: (v) => setState(() => _mute = v),
              ringOverridesSilent: _ringOverridesSilent,
              onRing: (v) => setState(() => _ringOverridesSilent = v),
              intense: _intense,
              onIntense: (v) => setState(() => _intense = v),
              politeDecline: _politeDecline,
              onPolite: (v) => setState(() => _politeDecline = v),
              onNameChanged: () => setState(() {}),
            ),
          ),
          Step(
            title: const Text('Members'),
            isActive: _step >= 1,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickMembers,
                  icon: const Icon(Icons.contacts),
                  label: const Text('Select from contacts'),
                ),
                const SizedBox(height: 12),
                if (_members.isEmpty)
                  const Text('No members yet')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final n in _members)
                        Chip(
                          label: Text(n),
                          onDeleted: () =>
                              setState(() => _members = _members.where((m) => m != n).toList()),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigStep extends StatelessWidget {
  const _ConfigStep({
    required this.nameController,
    required this.messageController,
    required this.palette,
    required this.color,
    required this.onColor,
    required this.mute,
    required this.onMute,
    required this.ringOverridesSilent,
    required this.onRing,
    required this.intense,
    required this.onIntense,
    required this.politeDecline,
    required this.onPolite,
    required this.onNameChanged,
  });

  final TextEditingController nameController;
  final TextEditingController messageController;
  final List<int> palette;
  final int color;
  final ValueChanged<int> onColor;
  final bool mute;
  final ValueChanged<bool> onMute;
  final bool ringOverridesSilent;
  final ValueChanged<bool> onRing;
  final bool intense;
  final ValueChanged<bool> onIntense;
  final bool politeDecline;
  final ValueChanged<bool> onPolite;
  final VoidCallback onNameChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Group name'),
          onChanged: (_) => onNameChanged(),
        ),
        const SizedBox(height: 16),
        const Text('Color'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final c in palette)
              GestureDetector(
                onTap: () => onColor(c),
                child: CircleAvatar(
                  backgroundColor: Color(c),
                  child: c == color ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mute incoming calls'),
          value: mute,
          onChanged: onMute,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ring even when silent'),
          value: ringOverridesSilent,
          onChanged: onRing,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Intense mode'),
          subtitle: const Text('Max volume + vibration on repeat calls'),
          value: intense,
          onChanged: onIntense,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Polite decline (auto-SMS)'),
          value: politeDecline,
          onChanged: onPolite,
        ),
        if (politeDecline)
          TextField(
            controller: messageController,
            decoration: const InputDecoration(labelText: 'Decline message'),
            maxLines: 2,
          ),
      ],
    );
  }
}
