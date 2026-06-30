import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/phone_number.dart';
import '../../core/providers.dart';
import '../../data/repositories/settings_repository.dart';

/// Small WhatsApp icon button that opens [number] in a WhatsApp chat.
///
/// Visibility:
///  - hidden if WhatsApp isn't installed or [number] is empty;
///  - in [WhatsAppMode.always], shown for any number;
///  - in [WhatsAppMode.contactsOnly], shown only if [number] loosely matches a
///    WhatsApp-synced contact (trailing-digits comparison).
class WhatsAppButton extends ConsumerWidget {
  const WhatsAppButton({required this.number, this.size = 20, super.key});

  static const Color whatsAppGreen = Color(0xFF25D366);

  final String number;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (number.trim().isEmpty) return const SizedBox.shrink();

    final installed = ref.watch(whatsAppInstalledProvider).valueOrNull ?? false;
    if (!installed) return const SizedBox.shrink();

    final mode = ref.watch(whatsAppModeProvider).valueOrNull ?? WhatsAppMode.always;
    if (mode == WhatsAppMode.contactsOnly) {
      // Detected = WhatsApp-synced contacts ∪ numbers confirmed by the opt-in probe cache.
      final synced = ref.watch(whatsAppNumbersProvider).valueOrNull ?? const <String>{};
      final cached = ref.watch(whatsAppCacheProvider).valueOrNull ?? const <String>{};
      final detected = {...synced, ...cached};
      final isWhatsApp = detected.any((n) => PhoneNumber.looseMatch(n, number));
      if (!isWhatsApp) return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: 'Open in WhatsApp',
      icon: const FaIcon(FontAwesomeIcons.whatsapp, color: whatsAppGreen),
      iconSize: size,
      onPressed: () => ref.read(whatsAppServiceProvider).openChat(number),
    );
  }
}
