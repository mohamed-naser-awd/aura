---
name: deploy
description: Build the Aura debug APK and install it to the test phone (wireless via wl.ps1, USB fallback), then relaunch. Use when the user says "deploy", "install on my phone", "push to device", or after finishing a change.
---

# Deploy Aura to the phone

Install the Aura debug build onto the Realme RMX3630 test device.

## Critical rule
**Always install with `adb install -r` — NEVER `flutter install`.**
`flutter install` uninstalls first, which wipes runtime permissions **and** the default-dialer
role, breaking the app until the user re-onboards. `adb install -r` reinstalls in place and keeps
both.

## Steps
1. **Pre-flight** (skip the codegen step if no drift/Riverpod change since last build):
   ```
   C:\tools\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs   # only if DB/codegen changed
   C:\tools\flutter\bin\flutter.bat analyze
   ```
   Analyze must be clean before installing.

2. **Build:**
   ```
   C:\tools\flutter\bin\flutter.bat build apk --debug
   ```
   Output: `build\app\outputs\flutter-apk\app-debug.apk`.

3. **Install — wireless (preferred):** use `wl.ps1` at the repo root. It connects (with retries),
   runs `adb install -r`, and relaunches.
   ```
   powershell -ExecutionPolicy Bypass -File wl.ps1 -Endpoint <host>:<connectPort>
   ```
   - Device host has been `192.168.50.64`. The **connect port changes** each time wireless
     debugging restarts — if `adb devices` shows nothing connected, **ask the user for the current
     connect port** (Developer options → Wireless debugging → "IP address & Port").
   - First-time pairing only: also pass `-PairPort <pairPort> -Code <code>` (the pairing port and
     6-digit code are different from the connect port). After pairing once, just use `-Endpoint`.
   - mDNS is broken on this PC — always pass the explicit `host:port`, don't rely on discovery.

4. **Install — USB fallback** (device on USB, `adb -d devices` shows it):
   ```
   adb -d install -r build\app\outputs\flutter-apk\app-debug.apk
   adb -d shell monkey -p ca.aepg.aura -c android.intent.category.LAUNCHER 1
   ```

## Verify
- `adb devices` (or `adb -d devices`) lists the device before installing.
- After install, the app launches; if a telephony feature is being tested, confirm Aura is still the
  default Phone app (the `-r` install should have preserved it).
