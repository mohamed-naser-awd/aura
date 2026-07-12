import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phone_number.dart';
import '../contacts/contacts_screen.dart';

/// Avatar for a phone number: the system contact photo if available, else a deterministic
/// colored circle with the contact's (or number's) initial.
class ContactAvatar extends ConsumerWidget {
  const ContactAvatar({
    required this.number,
    this.name,
    this.radius = 20,
    this.photo,
    super.key,
  });

  final String number;
  final String? name;
  final double radius;

  /// Pre-resolved thumbnail bytes. When supplied (e.g. by a list that already watched
  /// [contactPhotosProvider] once), the avatar skips the per-row provider watch entirely.
  final Uint8List? photo;

  static const _palette = [
    Color(0xFF5B6CFF), Color(0xFFEF5350), Color(0xFF66BB6A), Color(0xFFFFA726),
    Color(0xFFAB47BC), Color(0xFF26C6DA), Color(0xFFEC407A), Color(0xFF8D6E63),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the caller-supplied bytes when present; otherwise fall back to the shared photo map.
    final bytes = photo ??
        (number.isEmpty ? null : ref.watch(contactPhotosProvider)[PhoneNumber.suffix(number)]);
    if (bytes != null) {
      // Decode the thumbnail down to the pixels actually shown (avatar diameter × DPR) so fast
      // scrolling doesn't decode full-size bitmaps on the UI thread.
      final px = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round();
      return CircleAvatar(
        radius: radius,
        backgroundImage: ResizeImage(MemoryImage(bytes), width: px, height: px),
      );
    }
    final label = (name != null && name!.trim().isNotEmpty) ? name!.trim() : number;
    final initial = label.isNotEmpty ? label.substring(0, 1).toUpperCase() : '?';
    final color = _palette[label.hashCode.abs() % _palette.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(initial, style: TextStyle(color: Colors.white, fontSize: radius * 0.8)),
    );
  }
}
