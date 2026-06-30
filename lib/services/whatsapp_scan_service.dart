import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/repositories/settings_repository.dart';

/// Runs the WhatsApp probe in the background on app start when the user has opted in.
/// Best-effort and self-limiting: [WhatsAppRepository.candidates] only returns numbers
/// not checked within the staleness window, so repeated launches do little work.
/// Activate by watching [whatsAppScanServiceProvider] from a long-lived widget.
class WhatsAppScanService {
  WhatsAppScanService(this._ref) {
    _maybeScan();
  }

  final Ref _ref;

  Future<void> _maybeScan() async {
    final settings = _ref.read(settingsRepositoryProvider);
    if (!await settings.whatsAppAutoScan()) return;
    if (await settings.whatsAppMode() != WhatsAppMode.contactsOnly) return;
    if (!await _ref.read(whatsAppServiceProvider).isInstalled()) return;
    // Fire-and-forget; results land in the cache and refresh the UI via whatsAppCacheProvider.
    await _ref.read(whatsAppRepositoryProvider).scan();
  }
}

final whatsAppScanServiceProvider = Provider<WhatsAppScanService>((ref) {
  return WhatsAppScanService(ref);
});
