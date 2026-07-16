# Rate App Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ask the user to rate Pixora on the Play Store after they have successfully applied 3 wallpapers, only on an apply that showed no ad, and never more than 3 times in the app's lifetime.

**Architecture:** A `RateService` singleton owns all the rules and the Hive-backed counters, and presents the sheet itself through the global `pixoraNavigatorKey` — so no page has to know it exists. That key moves out of `main.dart` into `core/navigation/` first, to keep the import graph acyclic. `ContentManager` gets one line at its existing success point. `AdService` gains an explicit `lastActionShowedAd` flag so the service can tell whether the apply that just happened carried an interstitial.

**Tech Stack:** Flutter, Hive (`pixora_settings` box), `url_launcher`, `LocaleHelper.fromCms` (Text CMS), `showModalBottomSheet`.

**Spec:** `docs/superpowers/specs/2026-07-15-rate-app-modal-design.md`

## Global Constraints

- **No automated test suite exists in this repo.** Validation is `flutter analyze` plus manual device testing. Every task's "test" step is one of those two. Do not scaffold a test framework.
- **Devices:** Samsung `RF8X903KZ3K` (primary), Huawei `G2R4C17516000149` (1080x1920, the short screen that catches RenderFlex overflows).
- **Policy — do not violate:** the 5 stars are decorative and MUST NOT be tappable. No reward for rating. No sentiment routing. See the spec's "Policy constraints" section.
- **Colours come from `context.hud`** (`lib/core/design/hud_tokens.dart`). Available fields: `bg`, `surface`, `surfaceHi`, `text`, `textDim`, `divider`, `accent`, `accent2`. There is NO `hud.gold` field despite what the comment on `hud_tokens.dart:202` says — use `h.accent`.
- **Hive access pattern:** always `try/catch` and degrade silently. A Hive hiccup must never block a user flow. See `onboarding_page.dart:30-44`.
- **Package name:** `com.orbix.pixora`
- **Tunables (spec-mandated):** `_minApplies = 3`, `_minAge = 2 days`, `_snooze = 14 days`, `_maxPrompts = 3`.
- **Language:** code, comments and commit messages in English (repo convention). User-facing strings are ES/EN via `LocaleHelper`.

---

### Task 1: `AdService.lastActionShowedAd`

Gives `RateService` an honest answer to "did the apply that just happened show an ad?". Must be a real field, not parity arithmetic — see the spec for why.

**Files:**
- Modify: `lib/core/services/ad_service.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `bool AdService.instance.lastActionShowedAd`

- [ ] **Step 1: Add the field and getter**

In `lib/core/services/ad_service.dart`, directly below `int _actionCount = 0;` (~line 133):

```dart
  /// Whether the most recent [showInterstitialAd] call actually put an ad on
  /// screen. Every early return sets this false, so a caller that runs after
  /// the flow (e.g. RateService, deciding whether the moment is clean enough
  /// to ask for a review) can tell an ad-free apply from one that just
  /// interrupted the user.
  bool _lastActionShowedAd = false;
  bool get lastActionShowedAd => _lastActionShowedAd;
```

- [ ] **Step 2: Set it false in every early return**

In `showInterstitialAd`, add `_lastActionShowedAd = false;` as the FIRST statement inside each of these five blocks, immediately before their `_logAd(` call:

1. the subscription gate — `if (SubscriptionService.instance.hasAccess) {`
2. the Free Hour gate — `if (FreeHourService.instance.isActive) {`
3. the welcome grace pass — `if (GracePassService.instance.hasGrace) {`
4. the debug bypass — `if (_debugDisableAds) {`
5. the alternating skip — `if (!shouldShow) {`

Then also add it to the ad-not-preloaded block — `if (_interstitialAd == null || !_isAdLoaded) {`.

- [ ] **Step 3: Set it true where an ad is actually shown**

Immediately after the ad-not-preloaded early return (so control only reaches it when an ad is really going to be displayed), before `_interstitialAd!.show()` is set up:

```dart
    _lastActionShowedAd = true;
```

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/core/services/ad_service.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/ad_service.dart
git commit -m "feat(ads): expose lastActionShowedAd

RateService needs to know whether the apply that just finished carried an
interstitial, so it can avoid stacking the review ask on top of an ad. A
real field rather than reading isNextActionFree backwards -- that getter
was inverted for two months precisely because parity was doing a job
plain state should do."
```

---

### Task 2: Move `pixoraNavigatorKey` out of `main.dart`

`RateService` needs the global navigator to present the sheet. Importing
`main.dart` from a service would be the only such import in the repo (verified:
zero matches for `import.*main.dart` under `lib/`) and would make the import
graph circular, since `main.dart` will import `RateService` in Task 3.

The key itself is currently dead — `main.dart:41` says "kept around in case a
future flow needs it", and its only reference is the `navigatorKey:` argument
on `MaterialApp`. This feature is its first real consumer, which makes now the
moment to give it a home a service can import.

**Files:**
- Create: `lib/core/navigation/app_navigator.dart`
- Modify: `lib/main.dart:42-43` (remove the declaration, add the import)

**Interfaces:**
- Consumes: nothing
- Produces: `pixoraNavigatorKey` importable from `core/navigation/app_navigator.dart`

- [ ] **Step 1: Create the new home**

Create `lib/core/navigation/app_navigator.dart`:

```dart
import 'package:flutter/material.dart';

/// The app's navigator, handed to `MaterialApp.navigatorKey` in main.dart.
///
/// Lives here rather than in main.dart so services can reach it without
/// importing the entry point (which would make the import graph circular:
/// main -> service -> main). Anything that has to put UI on screen from
/// outside the widget tree goes through this.
final GlobalKey<NavigatorState> pixoraNavigatorKey =
    GlobalKey<NavigatorState>();
```

- [ ] **Step 2: Remove the declaration from `main.dart`**

Delete these lines from `lib/main.dart` (~line 41-43):

```dart
/// Global navigator key kept around in case a future flow needs it.
/// The ad-overlay path no longer uses it — see [adShowingNotifier] below.
final GlobalKey<NavigatorState> pixoraNavigatorKey =
    GlobalKey<NavigatorState>();
```

Add to the imports at the top of `lib/main.dart`:

```dart
import 'core/navigation/app_navigator.dart';
```

`main.dart:275` (`navigatorKey: pixoraNavigatorKey`) keeps working unchanged.

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/main.dart lib/core/navigation/app_navigator.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/core/navigation/app_navigator.dart lib/main.dart
git commit -m "refactor(core): move pixoraNavigatorKey out of main.dart

Services that need to present UI from outside the widget tree can now
import the key without importing the entry point, which would make the
graph circular. No behaviour change -- MaterialApp still gets the same
key. RateService is the first real consumer; until now it was dead."
```

---

### Task 3: `RateService`

All the rules live here. The service presents the sheet itself, so callers only report facts.

**Files:**
- Create: `lib/core/services/rate_service.dart`
- Modify: `lib/main.dart` (init)

**Interfaces:**
- Consumes: `AdService.instance.lastActionShowedAd` (Task 1); `pixoraNavigatorKey` from `core/navigation/app_navigator.dart` (Task 2); `RateAppSheet.show(BuildContext)` (Task 4)
- Produces: `RateService.instance.init()`, `RateService.instance.recordApplied()`, `RateService.instance.debugForceShow()`, `RateService.instance.debugReset()`, `RateService.instance.markRated()`, `RateService.instance.markDismissed()`

- [ ] **Step 1: Create the service**

Create `lib/core/services/rate_service.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/rate/presentation/rate_app_sheet.dart';
import '../navigation/app_navigator.dart';
import 'ad_service.dart';

/// Decides when to ask the user for a Play Store review, and asks.
///
/// The rules exist to keep the ask from being the reason someone leaves one
/// star: it only fires after the user has applied a few wallpapers (so they
/// have an opinion worth giving), never on an apply that just showed an ad
/// (two interruptions back to back read as one rude app), and it gives up
/// permanently after three refusals.
///
/// Policy: the sheet must never reward a review or route users by sentiment.
/// See docs/superpowers/specs/2026-07-15-rate-app-modal-design.md.
class RateService {
  RateService._();
  static final RateService instance = RateService._();

  static const _boxName = 'pixora_settings'; // shared with onboarding
  static const _kApplied = 'rate_applied_count';
  static const _kFirstSeen = 'rate_first_seen_at';
  static const _kPrompts = 'rate_prompt_count';
  static const _kSnooze = 'rate_snooze_until';
  static const _kDone = 'rate_done';

  static const _minApplies = 3;
  static const _minAge = Duration(days: 2);
  static const _snooze = Duration(days: 14);
  static const _maxPrompts = 3;

  static const _marketUrl = 'market://details?id=com.orbix.pixora';
  static const _webUrl =
      'https://play.google.com/store/apps/details?id=com.orbix.pixora';

  Box? _box;

  /// Opens the box and stamps the install date on first ever run. The stamp
  /// is what the "app is at least 2 days old" rule measures against, so it
  /// has to be written before the first apply can happen.
  Future<void> init() async {
    try {
      _box = await Hive.openBox(_boxName);
      if (_box!.get(_kFirstSeen) == null) {
        await _box!.put(_kFirstSeen, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {
      _box = null; // stay silent; the app must launch regardless
    }
  }

  /// Call after a wallpaper is successfully applied. Counts it, then asks if
  /// this is a good moment.
  Future<void> recordApplied() async {
    final box = _box;
    if (box == null) return;
    try {
      if (box.get(_kDone, defaultValue: false) as bool) return;
      final n = (box.get(_kApplied, defaultValue: 0) as int) + 1;
      await box.put(_kApplied, n);
      if (_isEligible()) await _present();
    } catch (_) {}
  }

  bool _isEligible() {
    final box = _box;
    if (box == null) return false;
    if (box.get(_kDone, defaultValue: false) as bool) return false;

    final applied = box.get(_kApplied, defaultValue: 0) as int;
    if (applied < _minApplies) return false;

    final now = DateTime.now().millisecondsSinceEpoch;

    final firstSeen = box.get(_kFirstSeen, defaultValue: now) as int;
    if (now - firstSeen < _minAge.inMilliseconds) return false;

    final snoozeUntil = box.get(_kSnooze, defaultValue: 0) as int;
    if (now < snoozeUntil) return false;

    // The apply that just happened carried an ad. Asking now would make the
    // review prompt feel like a second interstitial. Wait for a clean one;
    // the alternating cadence means that is usually the next apply.
    if (AdService.instance.lastActionShowedAd) return false;

    return true;
  }

  /// Shows the sheet if there is a context to show it in and nothing else is
  /// already on top. Counters are left untouched when we bail, so the next
  /// qualifying apply simply tries again.
  Future<void> _present() async {
    final ctx = pixoraNavigatorKey.currentContext;
    if (ctx == null) return;
    final route = ModalRoute.of(ctx);
    if (route != null && !route.isCurrent) return;

    final box = _box;
    if (box == null) return;
    // Burn the budget on SHOW, not on answer: a sheet the user ignores has
    // still been spent, and counting only answers would let us show it more
    // than _maxPrompts times.
    final shown = (box.get(_kPrompts, defaultValue: 0) as int) + 1;
    await box.put(_kPrompts, shown);

    await RateAppSheet.show(ctx);

    if (shown >= _maxPrompts) {
      await box.put(_kDone, true);
    }
  }

  /// User tapped "¡Calificar!". Opens the Store and never asks again.
  ///
  /// We cannot tell whether they actually left a review — neither market://
  /// nor the In-App Review API reports it — so tapping the button is treated
  /// as done. Pestering someone who did us the favour is worse than missing
  /// a second chance with someone who didn't.
  Future<void> markRated() async {
    final ok = await _openStore();
    if (!ok) return; // couldn't open anything; leave the door open
    try {
      await _box?.put(_kDone, true);
    } catch (_) {}
  }

  /// User tapped "Ahora no", or swiped the sheet away. Same handling: someone
  /// who flicks a sheet off mid-scroll is busy, not offended.
  Future<void> markDismissed() async {
    try {
      await _box?.put(
        _kSnooze,
        DateTime.now().add(_snooze).millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<bool> _openStore() async {
    try {
      final ok = await launchUrl(
        Uri.parse(_marketUrl),
        mode: LaunchMode.externalApplication,
      );
      if (ok) return true;
    } catch (_) {}
    // No Play Store app (or a debug build sideloaded over adb) — the web
    // listing works everywhere and is what makes this testable.
    try {
      return await launchUrl(
        Uri.parse(_webUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// Device-testing hook: shows the sheet ignoring every gate. Does not touch
  /// the prompt budget, so it can be fired repeatedly.
  Future<void> debugForceShow() async {
    final ctx = pixoraNavigatorKey.currentContext;
    if (ctx == null) return;
    await RateAppSheet.show(ctx);
  }

  /// Device-testing hook: wipes all rate state so the real trigger path can
  /// be exercised from scratch.
  Future<void> debugReset() async {
    try {
      await _box?.delete(_kApplied);
      await _box?.delete(_kPrompts);
      await _box?.delete(_kSnooze);
      await _box?.delete(_kDone);
      await _box?.put(_kFirstSeen, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
```

- [ ] **Step 2: Init it at startup**

In `lib/main.dart`, next to the other service inits (~line 120-150), after `await GracePassService.instance.init();`:

```dart
    await RateService.instance.init();
```

Add the import at the top of `lib/main.dart`:

```dart
import 'core/services/rate_service.dart';
```

Use `await`, not `unawaited`: `init()` stamps `rate_first_seen_at`, and an apply racing an unfinished init would measure the app's age against a missing stamp.

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/core/services/rate_service.dart lib/main.dart`
Expected: `No issues found!`

(Task 4 creates `rate_app_sheet.dart`. If it does not exist yet, this analyze fails on the import — that is expected; do Task 3 then re-run.)

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/rate_service.dart lib/main.dart
git commit -m "feat(rate): RateService — trigger rules + Hive state

Owns when to ask for a Play Store review: 3 applies, app at least 2 days
old, never on an apply that showed an ad, max 3 asks ever. Presents via
pixoraNavigatorKey so no page has to know it exists."
```

---

### Task 4: `RateAppSheet`

The variant-5 bottom sheet. Follows `sleep_timer_sheet.dart` for structure.

**Files:**
- Create: `lib/features/rate/presentation/rate_app_sheet.dart`

**Interfaces:**
- Consumes: `RateService.instance.markRated()`, `RateService.instance.markDismissed()` (Task 3)
- Produces: `static Future<void> RateAppSheet.show(BuildContext context)`

- [ ] **Step 1: Create the sheet**

Create `lib/features/rate/presentation/rate_app_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/design/hud_tokens.dart';
import '../../../core/services/rate_service.dart';
import '../../../core/utils/locale_helper.dart';

/// "¿Nos echas la mano?" — the review ask.
///
/// The five stars are DECORATIVE and must stay that way. Making them tappable
/// and routing by rating (4-5 to the Store, 1-3 to a form) is review gating,
/// which Google Play prohibits. The copy is deliberately sentiment-neutral:
/// it asks for a favour, never for an opinion.
class RateAppSheet extends StatelessWidget {
  const RateAppSheet._();

  static Future<void> show(BuildContext context) async {
    final h = context.hud;
    // isScrollControlled + the scroll view below: the Huawei VNS-L53 is
    // 1080x1920 and has produced RenderFlex overflows on sheets before.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: h.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const RateAppSheet._(),
    );
    // Reached on tap-outside and swipe-down as well as the buttons. The
    // buttons pop first and record their own outcome; this is the catch-all
    // for "went away without choosing", which we treat as a soft no.
    await RateService.instance.markDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            20 + MediaQuery.of(context).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: h.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text('🥹', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                LocaleHelper.fromCms(
                  'rate.title',
                  fallbackEs: '¿Nos echas la mano?',
                  fallbackEn: 'Lend us a hand?',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: h.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (_) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(Icons.star, color: h.accent, size: 26),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                LocaleHelper.fromCms(
                  'rate.body',
                  fallbackEs:
                      'Una reseña tuya vale oro para un estudio chiquito '
                      'como el nuestro.',
                  fallbackEn:
                      'A review from you is worth its weight in gold to a '
                      'studio as small as ours.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: h.textDim, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  // "Ahora no" gets equal layout weight. It is a real option,
                  // not a decoy.
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: h.text,
                        side: BorderSide(color: h.divider),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        LocaleHelper.fromCms(
                          'rate.cta_no',
                          fallbackEs: 'Ahora no',
                          fallbackEn: 'Not now',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        RateService.instance.markRated();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: h.accent,
                        foregroundColor: h.bg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        LocaleHelper.fromCms(
                          'rate.cta_yes',
                          fallbackEs: '¡Calificar!',
                          fallbackEn: 'Rate us!',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify the "¡Calificar!" / dismiss interaction**

`show()` calls `markDismissed()` after the sheet closes, which also runs when the user tapped "¡Calificar!" — that would snooze a user who just rated. `markRated()` sets `rate_done = true` and `_isEligible()` checks `_kDone` first, so the stale snooze can never surface a sheet. Leave the code as written; this step exists so the interaction is verified, not assumed.

Confirm by reading `RateService._isEligible()`: `_kDone` is checked before `_kSnooze`. If a future edit reorders those checks, this breaks.

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/rate/ lib/core/services/rate_service.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/rate/presentation/rate_app_sheet.dart
git commit -m "feat(rate): RateAppSheet — variant 5 bottom sheet

Decorative stars (tappable stars + sentiment routing is review gating,
which Play prohibits). isScrollControlled for the Huawei's short screen."
```

---

### Task 5: Hook it to a successful apply

**Files:**
- Modify: `lib/core/content/content_manager.dart:137`

**Interfaces:**
- Consumes: `RateService.instance.recordApplied()` (Task 3)
- Produces: nothing

- [ ] **Step 1: Add the call**

In `lib/core/content/content_manager.dart`, inside `if (success) {` (~line 137), right after the existing `WallpaperStatsService.instance.trackInstall(item.id);`:

```dart
      // Ask for a review if this was a good moment. unawaited: the install
      // flow must not wait on a prompt, and RateService decides internally
      // whether anything is shown at all.
      unawaited(RateService.instance.recordApplied());
```

Add the imports at the top of the file if not already present:

```dart
import 'dart:async'; // unawaited
import '../services/rate_service.dart';
```

Check first — `unawaited` may already be imported. Do not duplicate.

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/core/content/content_manager.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/content/content_manager.dart
git commit -m "feat(rate): count a successful apply

Single hook, at the existing success point next to trackInstall. Does not
cover ARCANO, Explore frames or REALM shaders, which apply outside
ContentManager -- accepted, see the spec's coverage gap section."
```

---

### Task 6: Seed the CMS strings

The sheet renders from hardcoded fallbacks until these rows exist. Adding them is what makes the copy editable from pixora-admin without an AAB.

**Files:**
- None in the repo — this is a Supabase data change.

**Interfaces:**
- Consumes: nothing
- Produces: the four `rate.*` keys in the `app_strings` table

- [ ] **Step 1: Insert the rows**

The admin server must be running (`python tools/wallpapers/wp_admin_server.py`, port 5758). Use the TEXTOS tab, or insert directly:

```sql
insert into app_strings (key, es, en) values
  ('rate.title',  '¿Nos echas la mano?', 'Lend us a hand?'),
  ('rate.body',   'Una reseña tuya vale oro para un estudio chiquito como el nuestro.', 'A review from you is worth its weight in gold to a studio as small as ours.'),
  ('rate.cta_yes','¡Calificar!', 'Rate us!'),
  ('rate.cta_no', 'Ahora no', 'Not now')
on conflict (key) do update set es = excluded.es, en = excluded.en;
```

- [ ] **Step 2: Verify the client can read them**

```bash
curl -s "https://vzuwvsmlyigjtsearxym.supabase.co/rest/v1/app_strings?select=key,es,en&key=like.rate.*" \
  -H "apikey: <anon key from lib/core/constants/supabase_config.dart>"
```

Expected: four rows, accents intact (`reseña`, `¿`, `¡`).

- [ ] **Step 3: Push the CMS invalidation**

```bash
cd tools/wallpapers && python -c "from _fcm_push import send_catalog_invalidate as f; print(f('text_cms_update'))"
```

Expected: `True`. Without this, devices keep their cached strings for up to 5 minutes.

---

### Task 7: Device validation

No automated tests exist; this task is the real gate. Do not skip it.

**Files:**
- None

**Interfaces:**
- Consumes: everything above
- Produces: a verified build

- [ ] **Step 1: Build and install on both devices**

```bash
flutter build apk --debug
adb -s RF8X903KZ3K install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s G2R4C17516000149 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Expected: `Success` on both. Verify `✓ Built` appeared in the build output — a backgrounded Flutter build can report exit 0 while Gradle failed.

- [ ] **Step 2: Verify the sheet renders on the short screen**

Trigger `debugForceShow()` and inspect on the **Huawei** first (1080x1920):

```bash
adb -s G2R4C17516000149 logcat -c
# fire debugForceShow via whatever debug affordance is wired
adb -s G2R4C17516000149 logcat -d | grep -iE "RenderFlex|overflow"
```

Expected: no `RenderFlex overflowed` lines. Yellow-and-black stripes on screen mean the same thing — check logcat before blaming assets.

- [ ] **Step 3: Verify "¡Calificar!" opens the listing**

Tap it on a debug build. `market://` will not resolve (sideloaded over adb), so the https fallback must open the Play listing in a browser. Then confirm `rate_done`:

```bash
adb -s RF8X903KZ3K exec-out run-as com.orbix.pixora cat app_flutter/pixora_settings.hive | strings | grep -i rate
```

Expected: `rate_done` present.

- [ ] **Step 4: Verify the ad rule**

Temporarily lower `_minApplies` to 1 and `_minAge` to `Duration.zero`, rebuild, then apply wallpapers repeatedly. The sheet must appear only on an apply where no interstitial showed. Cross-check against the alternating cadence in logcat:

```bash
adb -s RF8X903KZ3K logcat -d | grep -iE "alternating_skip|interstitial"
```

Restore the real tunables before committing. **Do not ship the lowered values.**

- [ ] **Step 5: Verify the 3-prompt cap**

With `debugReset()` and the lowered tunables, dismiss the sheet three times. After the third, `rate_done` must be true and no further apply should surface it. Note that `debugForceShow()` bypasses the gates by design, so verify via the Hive values, not by the sheet failing to appear.

- [ ] **Step 6: Restore tunables, rebuild, commit**

```bash
git diff lib/core/services/rate_service.dart   # confirm tunables are back to 3 / 2 days / 14 days / 3
flutter analyze lib/
git add -A && git commit -m "test(rate): device validation pass — both devices, no overflow"
```

---

## Notes for the implementer

- **The stars.** If anyone asks to make them tappable "so users can pick their rating first", that is review gating and Google prohibits it. Push back and point at the spec.
- **`isNextActionFree` is not the same question** as `lastActionShowedAd`. The former is about the NEXT action and was inverted until 2026-07-15. Use `lastActionShowedAd`.
- **Coverage gap is intentional.** ARCANO, Explore frames and REALM shaders do not count toward the trigger. Do not "fix" this without asking — it is a recorded decision, not an oversight.
