import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phone_number.dart';
import '../contacts/contacts_screen.dart';

/// Avatar for a phone number: the system contact photo if available, else a deterministic
/// colored circle with the contact's (or number's) initial.
class ContactAvatar extends ConsumerWidget {
  const ContactAvatar({required this.number, this.name, this.radius = 20, super.key});

  final String number;
  final String? name;
  final double radius;

  static const _palette = [
    Color(0xFF5B6CFF), Color(0xFFEF5350), Color(0xFF66BB6A), Color(0xFFFFA726),
    Color(0xFFAB47BC), Color(0xFF26C6DA), Color(0xFFEC407A), Color(0xFF8D6E63),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = number.isEmpty
        ? null
        : ref.watch(contactPhotosProvider)[PhoneNumber.suffix(number)];
    if (photo != null) {
      return CircleAvatar(radius: radius, backgroundImage: MemoryImage(photo));
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
