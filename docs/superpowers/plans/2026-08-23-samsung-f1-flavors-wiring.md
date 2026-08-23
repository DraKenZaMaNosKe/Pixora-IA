# Samsung F1 — Flavors & Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce `play`/`samsung` product flavors and select the purchase gateway per flavor, so the `samsung` build compiles and runs with purchases disabled — without touching the working Play build.

**Architecture:** Gradle product flavors (same package, no suffix). A tiny `store_flavor.dart` maps Flutter's `appFlavor` constant to a `Store` and builds the right gateway: `play` → the existing `PlayPurchaseGateway` (F0), `samsung` → a new `DisabledPurchaseGateway` (kill switch OFF — no billing until F3). `SubscriptionService` stops hard-coding `PlayPurchaseGateway()` and calls the factory. A boot analytics event tags the store for per-flavor metrics.

**Tech Stack:** Flutter (`appFlavor` from `package:flutter/services.dart`), Gradle product flavors, existing `AnalyticsService` (Supabase-backed).

**Spec:** `docs/superpowers/specs/2026-08-23-samsung-galaxy-store-design.md` (Sections 1 & 4)

## Global Constraints

- Same package `com.orbix.pixora` on BOTH flavors — NO `applicationIdSuffix`.
- Both flavors share the existing `signingConfigs.release` (key.properties) and all defaultConfig values (minSdk 24, NDK 28.2.13676358, target = flutter.targetSdkVersion).
- F1 is CODE ONLY. Out of scope (manual/parallel, NOT in this plan): creating Samsung ad units in AdMob console, registering the app/items in Samsung Seller Portal, the real `SamsungPurchaseGateway` (that is F3).
- **After flavors exist, every flutter command needs `--flavor`** (`flutter run --flavor play`, `flutter build apk --debug --flavor play|samsung`). A no-flavor build will fail. Default to `--flavor play` for day-to-day Play work.
- iOS/debug: `appFlavor` is null → must default to `Store.play` so `flutter run` (no flavor) and iOS builds don't break.
- Pixora has NO automated test suite: per-task verification is `flutter analyze` + `flutter build apk --debug --flavor <f>`; functional verification is on-device (Samsung RF8X903KZ3K) via `orbix-dev-guardian`.
- Ad units per flavor are DEFERRED (YAGNI): samsung reuses Play's existing ad unit IDs for now (same AdMob app, same package). No AdService change in F1 — per-flavor ad unit IDs land when the real Samsung units are created in AdMob console.
- The samsung gateway being disabled means the pitch/perfil price falls back to the hardcoded string and the buy button is a no-op on samsung. Acceptable in F1 (samsung is not published yet). Hiding the CTA on samsung is an F3 refinement, not F1.

---

## File Structure

- **Modify** `android/app/build.gradle` — add `flavorDimensions "store"` + `productFlavors { play; samsung }` (no suffix).
- **Create** `lib/core/services/billing/store_flavor.dart` — `currentStore` (appFlavor→Store) + `createPurchaseGateway()` factory.
- **Create** `lib/core/services/billing/disabled_purchase_gateway.dart` — `DisabledPurchaseGateway implements PurchaseGateway` (all no-ops, isAvailable()=false).
- **Modify** `lib/core/services/subscription_service.dart` — replace `PlayPurchaseGateway()` with `createPurchaseGateway()`; drop the now-unneeded direct `play_purchase_gateway.dart` import.
- **Modify** `lib/main.dart` — after `AnalyticsService.instance.init()`, emit a boot event tagging the store.

---

## Task 1: Product flavors in build.gradle

**Files:**
- Modify: `android/app/build.gradle` (inside the `android { }` block)

**Interfaces:**
- Produces: two build flavors `play` and `samsung`, both applicationId `com.orbix.pixora`. Makes `appFlavor` resolve to `"play"` or `"samsung"` at runtime.

- [ ] **Step 1: Add flavorDimensions + productFlavors**

In `android/app/build.gradle`, inside `android { ... }` (e.g. right after the `buildTypes { ... }` block), add:

```gradle
    flavorDimensions "store"
    productFlavors {
        play {
            dimension "store"
            // same applicationId as defaultConfig (com.orbix.pixora) — no suffix
        }
        samsung {
            dimension "store"
            // same applicationId — the Galaxy Store binary shares the package
        }
    }
```

- [ ] **Step 2: Verify the play flavor builds**

Run: `flutter build apk --debug --flavor play`
Expected: `✓ Built build/app/outputs/flutter-apk/app-play-debug.apk`

- [ ] **Step 3: Verify the samsung flavor builds**

Run: `flutter build apk --debug --flavor samsung`
Expected: `✓ Built build/app/outputs/flutter-apk/app-samsung-debug.apk`

- [ ] **Step 4: Commit**

```bash
git add android/app/build.gradle
git commit -m "build(android): add play/samsung product flavors (same package, no suffix)"
```

---

## Task 2: Store flavor helper + gateway factory

**Files:**
- Create: `lib/core/services/billing/store_flavor.dart`

**Interfaces:**
- Consumes: `Store`, `PurchaseGateway` (purchase_gateway.dart, F0); `PlayPurchaseGateway` (play_purchase_gateway.dart, F0); `DisabledPurchaseGateway` (Task 3).
- Produces: `Store get currentStore`; `PurchaseGateway createPurchaseGateway()`.

- [ ] **Step 1: Create the helper**

```dart
// lib/core/services/billing/store_flavor.dart
//
// Maps the compiled Gradle flavor (Flutter's `appFlavor`) to a Store and
// builds the matching purchase gateway. `appFlavor` is null on iOS and on a
// no-flavor debug run — default to Store.play so those paths never break.
import 'package:flutter/services.dart' show appFlavor;

import 'disabled_purchase_gateway.dart';
import 'play_purchase_gateway.dart';
import 'purchase_gateway.dart';

Store get currentStore =>
    switch (appFlavor) { 'samsung' => Store.samsung, _ => Store.play };

/// Builds the purchase gateway for the current flavor. Play uses the real
/// Google Play gateway; Samsung uses a disabled gateway (purchases OFF) until
/// the real SamsungPurchaseGateway lands in F3.
PurchaseGateway createPurchaseGateway() =>
    switch (currentStore) {
      Store.play => PlayPurchaseGateway(),
      Store.samsung => DisabledPurchaseGateway(),
    };
```

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/core/services/billing/store_flavor.dart`
Expected: `No issues found!` (Task 3 creates DisabledPurchaseGateway; if run before Task 3, expect an unresolved-import error — do Task 3 first or together)

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/billing/store_flavor.dart
git commit -m "feat(billing): add store_flavor helper + per-flavor gateway factory"
```

---

## Task 3: DisabledPurchaseGateway

**Files:**
- Create: `lib/core/services/billing/disabled_purchase_gateway.dart`

**Interfaces:**
- Consumes: `PurchaseGateway`, `StoreProduct`, `StorePurchase`, `Store` (purchase_gateway.dart, F0).
- Produces: `DisabledPurchaseGateway implements PurchaseGateway` with a default constructor. `isAvailable()` → `false`; `queryProducts()` → `[]`; `buy()` → `false`; `restore()`/`finish()` → no-op; `purchases` → an open (empty) broadcast stream; `manageSubscriptionUri()` → `null`.

- [ ] **Step 1: Create the gateway**

```dart
// lib/core/services/billing/disabled_purchase_gateway.dart
import 'dart:async';

import 'purchase_gateway.dart';

/// A no-op gateway for a flavor whose store billing isn't wired yet. Used by
/// the `samsung` flavor until F3 ships the real SamsungPurchaseGateway. It is
/// "purchases OFF": the store is never available, no products load, buy()
/// reports the sheet was not launched, and nothing is ever emitted.
class DisabledPurchaseGateway implements PurchaseGateway {
  DisabledPurchaseGateway();

  @override
  Store get store => Store.samsung;

  final _controller = StreamController<StorePurchase>.broadcast();

  @override
  Stream<StorePurchase> get purchases => _controller.stream;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> logicalIds) async =>
      const <StoreProduct>[];

  @override
  Future<bool> buy(StoreProduct product) async => false;

  @override
  Future<void> finish(StorePurchase purchase, {required bool consume}) async {}

  @override
  Future<void> restore() async {}

  @override
  Uri? manageSubscriptionUri(String logicalId) => null;

  @override
  void dispose() {
    _controller.close();
  }
}
```

- [ ] **Step 2: Verify billing/ analyzes clean**

Run: `flutter analyze lib/core/services/billing/`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/billing/disabled_purchase_gateway.dart
git commit -m "feat(billing): add DisabledPurchaseGateway (samsung purchases OFF until F3)"
```

---

## Task 4: SubscriptionService picks gateway by flavor

**Files:**
- Modify: `lib/core/services/subscription_service.dart`

**Interfaces:**
- Consumes: `createPurchaseGateway()` (store_flavor.dart, Task 2).
- Produces: unchanged public API. The `_gateway` field is now flavor-selected.

- [ ] **Step 1: Swap the gateway construction**

In `subscription_service.dart`, change the import block: remove the direct
`import 'billing/play_purchase_gateway.dart';` (no longer referenced here —
the factory owns it) and add `import 'billing/store_flavor.dart';`. Keep
`import 'billing/purchase_gateway.dart';` and `import 'billing/product_catalog.dart';`.

Then change the field:
```dart
// FROM: final PurchaseGateway _gateway = PlayPurchaseGateway();
final PurchaseGateway _gateway = createPurchaseGateway();
```

- [ ] **Step 2: Verify analyze clean + no direct PlayPurchaseGateway ref**

Run: `flutter analyze lib/core/services/subscription_service.dart lib/core/services/billing/`
Expected: `No issues found!`
Run: `grep -n "PlayPurchaseGateway" lib/core/services/subscription_service.dart`
Expected: EMPTY (the concrete Play type is no longer referenced here; only the factory)

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/subscription_service.dart
git commit -m "refactor(billing): select purchase gateway by flavor (play/samsung)"
```

---

## Task 5: Boot analytics tags the store

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `currentStore` (store_flavor.dart, Task 2); `AnalyticsService.instance.track` (analytics_service.dart, existing).
- Produces: an `app_boot` event carrying `{'store': 'play'|'samsung'}` so metrics segment by flavor (same AdMob app, so this is how we separate).

- [ ] **Step 1: Emit the boot event**

In `lib/main.dart`, add `import 'core/services/billing/store_flavor.dart';`
near the other core imports. Right after the existing
`unawaited(SubscriptionService.instance.init());` line (around line 203) — or
immediately after `AnalyticsService.instance.init()` is invoked, whichever
comes later in the startup sequence — add:
```dart
    AnalyticsService.instance.track('app_boot', {'store': currentStore.name});
```
(`AnalyticsService` is already imported in main.dart. `Store.name` is the enum
value name: `'play'` or `'samsung'`.)

- [ ] **Step 2: Verify analyze clean**

Run: `flutter analyze lib/main.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(analytics): tag app_boot with store flavor for per-flavor metrics"
```

---

## Task 6: Device validation — both flavors

**Files:** none (verification only)

Dispatch `orbix-dev-guardian` to validate both flavors on the Samsung. Note: both flavors share the package `com.orbix.pixora`, so installing one replaces the other on the device — validate play first, then samsung.

- [ ] **Step 1: Analyze + build both flavors**

Run: `flutter analyze lib`
Expected: same 12 pre-existing issues, zero new.
Run: `flutter build apk --debug --flavor play` then `flutter build apk --debug --flavor samsung`
Expected: both `✓ Built ...app-play-debug.apk` / `...app-samsung-debug.apk`.

- [ ] **Step 2: Validate the PLAY flavor on Samsung via orbix-dev-guardian**

Dispatch scope:
- Install `app-play-debug.apk` on `RF8X903KZ3K` (uninstall com.orbix.pixora first if signature conflict).
- Launch, logcat `flutter|Pixora|Subs|PlayGW|AndroidRuntime|FATAL` — no crash.
- Confirm the monthly price still renders in Perfil (`$199.00`, real Play price) — proves the flavor factory still yields the working PlayPurchaseGateway.
- ⚠️ SECURITY: read-only screencap BEFORE any input; never tap blind (banking-incident rule); enter via `am start`, use `uiautomator dump` for bounds.

- [ ] **Step 3: Validate the SAMSUNG flavor on Samsung via orbix-dev-guardian**

Dispatch scope:
- Install `app-samsung-debug.apk` (replaces the play build — same package).
- Launch, logcat — no crash. Confirm logcat shows the store billing NOT available (e.g. `[Subs] store billing not available on this device`) and NO `[PlayGW]` activity (the DisabledPurchaseGateway is inert).
- Open Perfil: confirm it does NOT crash; the price shows the hardcoded fallback (`$199 MXN`) since queryProducts returns empty on samsung — expected in F1.
- ⚠️ Same screencap-first safety rule.

- [ ] **Step 4: Commit any fixes surfaced**

If validation finds an issue, fix it, re-run analyze + the affected flavor build, and commit with a `fix(...)` message. Re-dispatch until both flavors PASS.

---

## Release note (out of code scope)

After F1 passes on device, the app-signing/release path for the samsung flavor (build `--flavor samsung` release AAB/APK, upload to Galaxy Store) is a release action for later — it also depends on Samsung Seller Portal commercial approval (pending) and is handled outside this plan.

---

## Self-Review

**Spec coverage (Sections 1 & 4):** ✅ Flavors without suffix (Task 1); `appFlavor`→Store selecting the gateway (Tasks 2-4); samsung compiles + runs with purchases OFF via DisabledPurchaseGateway (Tasks 3-4, validated Task 6); per-flavor metrics via `store` tag (Task 5). Same-package + shared signing honored (Task 1). Deferred with explicit rationale: per-flavor ad units (YAGNI — samsung reuses Play IDs), real Samsung IAP (F3), Seller Portal registration (manual/parallel).

**Placeholder scan:** No TBD/TODO. The samsung flavor block has an explanatory comment but no missing values. `createPurchaseGateway()` returns a concrete `DisabledPurchaseGateway` for samsung — a real class (Task 3), not a stub-with-holes.

**Type consistency:** `currentStore` returns `Store` (Task 2), consumed in Task 5 as `currentStore.name`. `createPurchaseGateway()` returns `PurchaseGateway` (Task 2), assigned to `_gateway` in Task 4. `DisabledPurchaseGateway` implements every `PurchaseGateway` member with the F0 signatures — `buy()` returns `Future<bool>` (matches the F0 ruling), `finish(...,{required bool consume})`, `queryProducts(Set<String>)`. Consistent.
