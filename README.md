# Aura

A smart Android phone (dialer) app built with Flutter + native Kotlin telephony.
Aura replaces the system dialer to give you deep control over your calls:

- **Who ended the call** — remote / you / busy / canceled / missed, shown in the call log.
- **Contact groups** with per-group rules.
- **Mute incoming calls** from a group.
- **Force-ring even when the phone is silent** for important groups.
- **Time-window rules** (e.g. ring until 10 PM, then mute).
- **Long-press SIM selector** — always-ask / this-call-only / change-forever.
- **Per-group default SIM.**
- **Intense mode** — if the same number/group calls twice within 5 minutes, ring at max
  volume with strong vibration.
- **Polite-decline auto-SMS** (optional) — reject and send a custom message.
- **WhatsApp quick-action** — a WhatsApp icon next to numbers to open a chat directly
  (configurable: always show, or only for saved WhatsApp contacts).

> Aura must be set as the **default Phone app** for most features to work — this is an
> Android platform requirement (only the default dialer can read disconnect causes and
> own ringtone playback). See `docs` / the in-app onboarding.

## Why a full default-dialer app?

Android only exposes the needed capabilities to the default Phone app:

| Capability | Android API | Requires default dialer? |
|---|---|---|
| Who ended the call | `InCallService` + `DisconnectCause` | **Yes** |
| Force-ring when silent / intense mode | own ringtone playback | **Yes** |
| Mute group / time rule / polite-decline | `CallScreeningService` | covered by dialer role |
| SIM selection | `TelecomManager.placeCall(PhoneAccountHandle)` | best as dialer |

## Architecture

```
Flutter (Dart, UI + app logic)  <-- MethodChannel/EventChannel -->  Native (Kotlin, telephony)
        |                                                                    |
   drift (SQLite) --writes rules snapshot (JSON)--> native reads it (no Flutter engine needed)
        ^                                                                    |
        +------------------ native writes call events --> Flutter ingests <--+
```

The native telephony services run **even when the Flutter UI is closed** (the OS starts
them for incoming calls). So all group/rule decisions are evaluated in native Kotlin
against a **denormalized rules snapshot** that Flutter re-exports whenever groups or
rules change. The Flutter engine is only launched to show call UI.

- `lib/` — Flutter app (Riverpod state, drift DB, screens, platform-channel wrappers).
- `android/app/src/main/kotlin/ca/aepg/aura/` — native telephony layer.

See [the plan](../../.claude/plans/this-is-going-to-scalable-castle.md) for the full design.

## Prerequisites

- **Flutter SDK** >= 3.22 (`flutter --version`). Not currently installed on this machine —
  install from <https://docs.flutter.dev/get-started/install>.
- **Android SDK** with min API 29 (Android 10), target API 34+.
- A **physical Android device** for testing (emulators can't fully test SIM/telephony).
- Two devices (or a second phone/SIM) for end-to-end "who ended the call" tests.

## First-time setup

This repo contains the hand-written source. Generate the Flutter build harness +
code-gen the first time:

```bash
cd aura

# 1) Generate the gradle wrapper / ephemeral build files (keeps existing source).
flutter create . --org ca.aepg --project-name aura --platforms=android

# 2) Fetch packages.
flutter pub get

# 3) Run code generation (drift + riverpod).
dart run build_runner build --delete-conflicting-outputs

# 4) Run on a connected device.
flutter run
```

> `flutter create .` fills in only *missing* files (gradle wrapper, launcher icons under
> `android/app/src/main/res/mipmap-*`, etc.) and leaves the hand-written source here in
> place. After running it, sanity-check three things in case your Flutter version
> regenerated them:
> - `android/app/build.gradle` still sets `minSdk = 29` and `namespace = "ca.aepg.aura"`,
> - `android/app/src/main/AndroidManifest.xml` still declares the `InCallService` /
>   `CallScreeningService` and the dialer intent-filters,
> - `MainActivity.kt` still registers the Aura channels.

## Set Aura as the default Phone app

On first launch, complete onboarding — it requests runtime permissions and the
`ROLE_DIALER` role. You can also set it via **Settings → Apps → Default apps → Phone app**.

## Code generation

Drift and Riverpod use code generation. After changing a `*.drift`-related table, a
`@riverpod` provider, or a model, re-run:

```bash
dart run build_runner build --delete-conflicting-outputs
# or, while developing:
dart run build_runner watch --delete-conflicting-outputs
```

## Project status

This is the initial **scaffold**: architecture, native services, data layer, and all
feature screens are stubbed and wired. Implementation proceeds in the build order
documented in the plan. Search for `TODO(aura)` markers for the next implementation points.

## Release note

Default-dialer role + `READ_CALL_LOG` + `SEND_SMS` are Google Play *restricted*
permissions — shipping requires a Permissions Declaration Form justifying core
functionality.
