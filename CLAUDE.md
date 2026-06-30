# Aura — project guide

Aura is a full **default-dialer** Android app: Flutter UI + native Kotlin telephony. Most
features (who-ended-the-call, force-ring, screening, custom ringtones) only work because Aura is
the device's default Phone app — keep that in mind before assuming a feature can work without the
role.

## Toolchain
- Flutter is **not on PATH**. Use the absolute paths:
  - `C:\tools\flutter\bin\flutter.bat`
  - `C:\tools\flutter\bin\dart.bat`
- min SDK **29** (Android 10); Kotlin namespace `ca.aepg.aura`.
- Test device: Realme **RMX3630** (usually wireless ADB; see deploy below).
- Shell is PowerShell; a Bash tool is also available.

## Build / deploy / codegen (the commands that matter)
```
# analyze (must be clean before installing)
C:\tools\flutter\bin\flutter.bat analyze

# regenerate drift/Riverpod code after ANY DB or codegen change
C:\tools\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs

# build
C:\tools\flutter\bin\flutter.bat build apk --debug

# install — ALWAYS `adb install -r`, NEVER `flutter install`
#   `flutter install` UNINSTALLS first → wipes runtime permissions AND the default-dialer role.
#   `adb install -r` reinstalls in place and preserves both.
```
- **Wireless install:** use [`wl.ps1`](wl.ps1):
  `powershell -ExecutionPolicy Bypass -File wl.ps1 -Endpoint <host>:<connectPort> [-PairPort <p> -Code <c>]`.
  It connects (retries), `adb install -r`s the debug APK, and relaunches. The **connect port ≠ the
  pairing port** — if only pairing once, pass `-PairPort`/`-Code`; thereafter just `-Endpoint`.
  mDNS is broken on this PC, so always pass the explicit `host:port`. Device host has been `192.168.50.64`.
- **USB fallback:** `adb -d install -r build\app\outputs\flutter-apk\app-debug.apk`.
- Invoke `/deploy` to run the whole build+install flow.
- Release builds need `--no-tree-shake-icons` (group icon avatars use non-const `IconData`).

## Architecture
- **Flutter:** Riverpod (plain providers, no provider codegen) + go_router + drift (SQLite,
  codegen) + flutter_contacts + permission_handler.
- **Native telephony (Kotlin)** under `android/app/src/main/kotlin/ca/aepg/aura/`:
  `telecom/AuraInCallService`, `telecom/AuraCallScreeningService`, `telecom/SimManager`,
  `telecom/CallManager`, `ring/RingController`, `bridge/*`, `sms/PoliteDecline`.
- **Decoupled rules snapshot:** the native services run with **no Flutter engine** for incoming
  calls. Flutter denormalizes groups/rules/blocklist/ringtones into JSON via
  [rules_engine.dart](lib/services/rules_engine.dart) → [rules_exporter.dart](lib/data/native/rules_exporter.dart)
  → SharedPreferences (`aura_rules`); native reads it in
  [RulesSnapshot.kt](android/app/src/main/kotlin/ca/aepg/aura/bridge/RulesSnapshot.kt).
  **Re-export after every change to groups/members/rules/blocklist/ringtones** (repositories already
  call `_exporter.export()` — do the same in new ones).
- **Two Flutter engines:**
  - Main app: `main()` → `AuraApp`, hosted by `MainActivity`.
  - **Pre-warmed cached call engine:** `AuraApplication` spawns the `callUiMain` entrypoint
    ([main.dart](lib/main.dart) → [call_app.dart](lib/features/incall/call_app.dart): `CallApp`/`CallHost`),
    caches it (`FlutterEngineCache` id `aura_call_engine`); `CallActivity` attaches instantly.
    **Native controls the call-window lifecycle** — `AuraInCallService.onCallRemoved` calls
    `CallActivity.instance?.finish()` (no Flutter `SystemNavigator.pop`).
- **Platform channels:** `aura/telecom` (method), `aura/call_events` (event, **multi-sink** —
  both engines subscribe), `aura/rules` (method), `aura/whatsapp` (method), `aura/audio` (method+event),
  `aura/pickers` (method — system ringtone picker via `MainActivity.onActivityResult`).

## Conventions & gotchas
- **Number matching is by digit suffix (last 9)** via [phone_number.dart](lib/core/phone_number.dart)
  (`PhoneNumber.suffix` / `.digits`), so locally-saved `01001234567` matches incoming `+201001234567`.
  Use it everywhere numbers are compared (groups, blocklist, WhatsApp, ringtones).
- **drift schema** is at **v5**. When changing tables: bump `schemaVersion`, add an
  `if (from < N)` block in the `MigrationStrategy`, then run build_runner. See
  [app_database.dart](lib/data/db/app_database.dart).
- **Reuse the shared widgets/helpers** instead of re-rolling:
  - [call_button.dart](lib/features/common/call_button.dart) (tap=call, long-press=edit-in-dialer),
    [whatsapp_button.dart](lib/features/common/whatsapp_button.dart),
    [contact_avatar.dart](lib/features/common/contact_avatar.dart) (photo or colored initial),
    [group_avatar.dart](lib/features/common/group_avatar.dart) (image→icon→initial),
    [ringtone_picker.dart](lib/features/common/ringtone_picker.dart) (system/audio/default).
  - [format.dart](lib/core/format.dart) (`formatCallDuration`, `callTimingText`),
    [disconnect_kind.dart](lib/data/models/disconnect_kind.dart) (`dispositionFor`).
- Providers live in [providers.dart](lib/core/providers.dart). Contact data:
  `contactsProvider` (loads thumbnails), `contactNamesProvider`, `contactPhotosProvider` (in
  [contacts_screen.dart](lib/features/contacts/contacts_screen.dart)).
- Call UI screens are presentational and must pull in **no router/drift/heavy plugins** (keeps the
  call engine light) — lifecycle is owned by `CallHost`.

## Feature state (implemented)
Dialer (editable input, recents, live search, SIM-by-button + long-press picker), recents/call-log
(who-ended disposition, sections, context menu, block), contacts (+ permission button, tap → detail),
groups (create wizard, contact multi-select members, per-group rules/SIM, avatar, ringtone), in-call
(answer/reject/end/hold/DTMF/audio-route picker), incoming (name + close-on-end), WhatsApp
quick-action + opt-in synced-contacts scan, screening (mute / time-window / polite-decline-SMS /
blocklist), force-ring-when-silent (+ DND override), intense mode, **per-contact & per-group custom
ringtones (system or audio file), group avatars (color+icon or image), contact photos, contact
detail page with Info + History tabs**, **ongoing-call notification** (foreground-service; tap to
reopen the call screen; quick actions End / Mute / change-device → opens the in-app picker via the
`aura/call_ui` channel), **in-call camera button** (top-right of the in-call screen → in-app
`camera` capture, saved to the device gallery via `gal`).

> Call recording is intentionally **not** implemented: a sideloaded app can't capture the remote
> party's audio on Android 10+ (only privileged preinstalled dialers can). Don't re-attempt without
> a privileged/system build.

> The pre-warmed call engine **now registers Flutter plugins** (`GeneratedPluginRegistrant` in
> `AuraApplication.prewarmCallEngine` + `CallActivity` fallback) so the in-call camera works — the
> Dart call UI is still kept light (no router/drift widgets).

## References
- Full evolving plan: `C:\Users\dell\.claude\plans\this-is-going-to-scalable-castle.md`.
- Deploy recipe also saved in auto-memory `deploy-workflow.md`.
