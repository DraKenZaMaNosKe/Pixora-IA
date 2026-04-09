---
name: pixora-device-test
description: "Use after ANY significant change to Pixora Flutter code, before claiming work is complete. Runs the full verify loop: flutter analyze → build debug APK → install on Samsung (handling signature conflict) → launch → read logcat for crashes → report PASS/FAIL. Trigger on 'probar en el cel', 'test on device', 'verify it works', after completing a feature/fix, or before committing a non-trivial change."
---

# Pixora Device Test

End-to-end device verification for Pixora changes. This skill exists because forgetting to test on device is the #1 way crashes ship to production (we learned this when `MainActivity extends FlutterActivity` crashed at startup — see CLAUDE.md §Pitfalls B).

## When to trigger

**Always**, before saying work is done, when any of these happened:
- Dart code edited in `lib/`
- Android native code edited in `android/app/src/main/kotlin/`
- `pubspec.yaml` dependencies changed
- `AndroidManifest.xml` modified
- Plugin added/updated

**Skip** for: doc-only edits, `CHANGELOG.md` updates, pure git ops.

## Devices

Primary: Samsung `RF8X903KZ3K`. Secondary: `G2R4C17516000149`. Read `adb devices` first; if neither is attached, stop and report.

## The flow (execute in order, stop on first real failure)

### Step 1 — Analyzer
```bash
flutter analyze lib/<scope>
```
If touched broadly, use `flutter analyze lib/`. If only one feature, scope it for speed.
**Stop if**: any error. Report the error and propose a fix; do not proceed to build.
**Continue if**: 0 errors (infos and warnings are ok to pass through but note them in the report).

### Step 2 — Debug build
```bash
flutter build apk --debug
```
Expected artifact: `build/app/outputs/flutter-apk/app-debug.apk`.
**Stop if**: build fails. Report the last 30 lines of output; do not retry blindly.

### Step 3 — Device detection
```bash
adb devices
```
Pick the first attached device from the known list (`RF8X903KZ3K` preferred). Store the serial as `$DEV`.
**Stop if**: no device attached. Ask the user to connect one.

### Step 4 — Install (handle signature conflict)
```bash
adb -s $DEV install -r build/app/outputs/flutter-apk/app-debug.apk
```
**If output contains `INSTALL_FAILED_UPDATE_INCOMPATIBLE`**, this means a release-signed version of Pixora is already installed. Recover:
```bash
adb -s $DEV uninstall com.orbix.pixora
adb -s $DEV install build/app/outputs/flutter-apk/app-debug.apk
```
**Stop if**: install still fails after the recovery. Report.

### Step 5 — Clear logcat + launch
```bash
adb -s $DEV logcat -c
adb -s $DEV shell am start -n com.orbix.pixora/.MainActivity
```

### Step 6 — Wait for first frame, then read logs
Give it **5 seconds** to boot (cold start on debug is slow), then:
```bash
adb -s $DEV logcat -d | grep -E "flutter|Pixora|AndroidRuntime|FATAL" | tail -80
```

### Step 7 — Classify the result
- **PASS**: no `AndroidRuntime`, no `FATAL`, no Flutter `Uncaught error`, and logcat shows `Fully drawn com.orbix.pixora`.
- **SOFT FAIL**: Flutter error printed but app didn't crash (e.g. a provider threw but UI recovered). Report the error and note it as a regression risk.
- **HARD FAIL**: any `FATAL` or `AndroidRuntime: Process: com.orbix.pixora` line. Report the stack trace.

## Reporting

Emit a compact block the user can scan in 5 seconds:

```
🧪 Device Test — Pixora on <device>
  Analyzer: ✅ 0 issues
  Build:    ✅ app-debug.apk (Ns)
  Install:  ✅ (or ♻️  recovered from signature conflict)
  Launch:   ✅ Fully drawn +5s113ms
  Logcat:   ✅ clean / ⚠️  <N> flutter warnings / ❌ CRASH
  Verdict:  PASS | SOFT FAIL | HARD FAIL
```

If HARD FAIL, include the stack trace and stop — do not try to fix blindly. If SOFT FAIL, include the warning and ask the user if they want to investigate.

## What NOT to do

- Don't re-run a failed step without changing something — diagnose first.
- Don't skip the logcat read and declare success just because `install` succeeded.
- Don't test on an emulator when a real Samsung is attached — Samsung OneUI behaves differently and is the ground truth.
- Don't claim PASS if you only ran analyze + build — install and logcat are mandatory.
