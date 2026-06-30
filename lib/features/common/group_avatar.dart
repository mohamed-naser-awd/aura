import 'dart:io';

import 'package:flutter/material.dart';

/// Group avatar: image (if set) → icon on the group color → colored initial.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    required this.color,
    this.iconCodePoint,
    this.imagePath,
    this.name,
    this.radius = 20,
    super.key,
  });

  final int color;
  final int? iconCodePoint;
  final String? imagePath;
  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (imagePath != null && imagePath!.isNotEmpty && File(imagePath!).existsSync()) {
      return CircleAvatar(radius: radius, backgroundImage: FileImage(File(imagePath!)));
    }
    final c = Color(color);
    if (iconCodePoint != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: c,
        child: Icon(
          IconData(iconCodePoint!, fontFamily: 'MaterialIcons'),
          color: Colors.white,
          size: radius,
        ),
      );
    }
    final initial = (name != null && name!.trim().isNotEmpty) ? name!.trim()[0].toUpperCase() : '#';
    return CircleAvatar(
      radius: radius,
      backgroundColor: c,
      child: Text(initial, style: TextStyle(color: Colors.white, fontSize: radius * 0.8)),
    );
  }
}

/// Preset icons offered when choosing a group avatar icon.
const groupIconChoices = <IconData>[
  Icons.group, Icons.family_restroom, Icons.work, Icons.favorite, Icons.star,
  Icons.home, Icons.school, Icons.business, Icons.sports_esports, Icons.fitness_center,
  Icons.medical_services, Icons.flight,
];
