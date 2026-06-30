import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of [pickRingtone]. `uri == null` means "use the default ringtone" (clear).
class RingtoneSelection {
  const RingtoneSelection(this.uri);
  final String? uri;
}

const _pickers = MethodChannel('aura/pickers');

/// Lets the user choose a ringtone: a system ringtone, any audio file, or the default.
/// Returns null if cancelled; otherwise a [RingtoneSelection] (uri null = default).
Future<RingtoneSelection?> pickRingtone(BuildContext context, {String? current}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('System ringtone'),
            onTap: () => Navigator.pop(sheet, 'system'),
          ),
          ListTile(
            leading: const Icon(Icons.audiotrack),
            title: const Text('Audio file'),
            onTap: () => Navigator.pop(sheet, 'audio'),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Use default'),
            onTap: () => Navigator.pop(sheet, 'default'),
          ),
        ],
      ),
    ),
  );

  switch (choice) {
    case 'system':
      final r = await _pickers.invokeMethod<String?>('pickSystemRingtone', {'current': current});
      if (r == null) return null; // cancelled
      if (r == '__default__') return const RingtoneSelection(null);
      return RingtoneSelection(r);
    case 'audio':
      final path = await _pickAudioFile();
      return path == null ? null : RingtoneSelection(path);
    case 'default':
      return const RingtoneSelection(null);
    default:
      return null;
  }
}

/// Picks an audio file and copies it into app storage so the path stays valid.
Future<String?> _pickAudioFile() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.audio);
  final src = result?.files.single.path;
  if (src == null) return null;
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'ringtones'));
  await dir.create(recursive: true);
  final dest = File(p.join(dir.path, p.basename(src)));
  await File(src).copy(dest.path);
  return dest.path;
}
