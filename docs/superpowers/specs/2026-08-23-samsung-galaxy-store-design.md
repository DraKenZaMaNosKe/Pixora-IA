# Samsung Galaxy Store Variant — Design Spec

**Date:** 2026-08-23
**Status:** Approved (design). Next: implementation plan (writing-plans).
**Goal:** Ship Pixora on the Samsung Galaxy Store with working monetization — Samsung In-App Purchase (subscriptions) + AdMob ads — from a single code base, without duplicating maintenance.

---

## Global Constraints

- Package stays `com.orbix.pixora` on BOTH stores (no `applicationIdSuffix`).
- NDK `28.2.13676358`, Java 17, minSdk 24, target = `flutter.targetSdkVersion` (36).
- One server-side entitlement (Supabase) is the single source of truth for access; Play RTDN and Samsung ISN both feed it.
- No secrets in the repo. Samsung Seller Portal service account + ISN keys live in `orbixprivate`/`KEYS_LOCAL.md` only. GitHub Push Protection does NOT know Samsung secret formats — do not rely on it.
- AdMob: single AdMob app (deduped by package). Per-flavor ad units, never a second AdMob account (prior 29-day suspension history).
- Samsung IAP sandbox testing runs on the physical Samsung (RF8X903KZ3K). Remote Test Lab does NOT support purchases.

---

## Architecture

Single Flutter code base → two Gradle product flavors (`play`, `samsung`) → a `PurchaseGateway` interface extracted BELOW the existing `SubscriptionService` → one Supabase entitlement fed by both stores.

```
UI (subscription_pitch_page, AdService) ── unchanged
        │
SubscriptionService (entitlement, Supabase RPC, Realtime) ── role unchanged
        │
PurchaseGateway  ◄── new interface
   ╱                ╲
PlayPurchaseGateway   SamsungPurchaseGateway
(in_app_purchase)     (MethodChannel → IapHelper, Kotlin, src/samsung/)
        │                    │
Google Play Billing    Samsung IAP SDK
        └──────── Supabase ──────────┘
   verify_google_purchase (exists) · verify_samsung_purchase (new)
   samsung-isn-webhook (new) → user_subscriptions + subscription_status RPC
```

Key decisions:
- **`appFlavor`** (Flutter const, auto-filled by `--flavor samsung`) selects which gateway is instantiated. No `--dart-define` (desyncs from `--flavor`).
- `in_app_purchase` (Dart plugin) compiles in BOTH flavors, but the samsung flavor NEVER calls `InAppPurchase.instance` — gated in `init()`.
- Samsung IAP AAR + its MethodChannel registration live ONLY in `android/app/src/samsung/` → the Play binary contains no alternate-billing code (Google is strict about this).
- `SubscriptionService` keeps its role (entitlement/Realtime/UI). Only the store-facing slice is extracted.

---

## Section 1 — Flavors & wiring

`android/app/build.gradle`:
```gradle
android {
  flavorDimensions "store"
  productFlavors {
    play    { dimension "store" }
    samsung { dimension "store" }   // same applicationId, NO suffix
  }
}
dependencies {
  // Samsung IAP AAR only for the samsung flavor:
  samsungImplementation files('src/samsung/libs/iap6-x.x.x.aar')
}
```

Dart flavor switch:
```dart
import 'package:flutter/services.dart' show appFlavor;
final Store store = switch (appFlavor) { 'samsung' => Store.samsung, _ => Store.play };
```

Build commands:
```bash
flutter build appbundle --flavor play
flutter build appbundle --flavor samsung   # or --release APK for Galaxy Store upload
```

`SubscriptionService.init()` gates by store so the samsung flavor never touches `InAppPurchase.instance` (avoids "billing unavailable" noise + zombie listeners). iOS/debug: `appFlavor` is null → default `Store.play` so `flutter run` and iOS builds don't crash on init.

---

## Section 2 — PurchaseGateway interface

```dart
enum Store { play, samsung }
enum ProductKind { consumable, nonConsumable, subscription }
enum PurchaseState { pending, purchased, canceled, failed }

class StoreProduct {
  final String logicalId;      // 'pixora_monthly' — Pixora-internal ID
  final String storeSku;       // real ID registered in THAT store
  final ProductKind kind;
  final String title;
  final String formattedPrice; // store-localized; NEVER parse
  final String currencyCode;
  final String? subscriptionPeriod; // ISO-8601 'P1M'
}

class StorePurchase {
  final Store store;
  final String logicalId;
  final String transactionId;                  // purchaseToken (Play) | purchaseId (Samsung)
  final PurchaseState state;
  final Map<String, dynamic> verificationBlob; // opaque; ONLY the server interprets it
  final bool isRestored;
  final String? errorMessage;
}

abstract class PurchaseGateway {
  Store get store;
  Future<bool> isAvailable();
  Future<List<StoreProduct>> queryProducts(Set<String> logicalIds);
  Stream<StorePurchase> get purchases;      // ONLY channel for results
  Future<bool> buy(StoreProduct product);   // true = flow launched (NOT completed); result via [purchases]
  Future<void> finish(StorePurchase p, {required bool consume});
  Future<void> restore();                   // re-emits owned products via [purchases]
  Uri? manageSubscriptionUri(String logicalId);
  void dispose();
}
```

Anti-leak rules:
- `buy()` → `Future<bool>` meaning "purchase flow launched" (NOT "purchase completed"); the real purchase result (pending, parental approval, slow card) still arrives async via the stream. The bool only reports whether the store showed the sheet — which `buyMonthly()` and the pitch UI depend on. (F0 ruling 2026-08-23: original spec said `void`, but that discarded the "sheet not shown" signal and caused a false "welcome" UX.)
- `restore()` normalizes to the stream (Samsung's synchronous `getOwnedProducts` list is pushed into the same stream).
- `verificationBlob` opaque = deliberate leak. Play needs `{purchaseToken, packageName, productId}`, Samsung needs `{purchaseId,...}`. They travel as-is to the server, which branches on `store`. Client never interprets them.
- `logicalId` vs `storeSku`: a per-flavor `ProductCatalog` translates. IDs registered separately per console WILL diverge.
- `finish(consume:)` from day one — supports future consumable credit packs without breaking the interface.

Extraction map:
| Extracted to `PlayPurchaseGateway` | Stays in `SubscriptionService` |
|---|---|
| Everything touching `InAppPurchase.instance`: stream listeners, `_loadProducts`, `buyMonthly`→`buy`, `restorePurchases`, `_handlePurchaseUpdate`, `completePurchase` | Entitlement: `refreshStatus`, `_setFromJson`, Realtime, `hasAccess`, `onSignIn/onSignOut` |

Glue: `SubscriptionService.init()` does `_gateway.purchases.listen(_onPurchase)`. `_onPurchase(StorePurchase p)` calls the right Edge Function by `p.store` (`verify_google_purchase` | `verify_samsung_purchase`), then `refreshStatus()`, then `gateway.finish(p)`. Single owner of entitlement state — never two.

---

## Section 3 — Server-side entitlement (multi-origin)

Schema changes:
```sql
-- Raw events (append-only, idempotent)
create table billing_events (
  id bigint generated always as identity primary key,
  store text not null check (store in ('play','samsung')),
  event_id text not null,            -- Pub/Sub messageId | ISN JWT jti/notificationId
  raw jsonb not null,
  processed_at timestamptz,
  received_at timestamptz not null default now(),
  unique (store, event_id)           -- webhook replay = no-op
);

alter table user_subscriptions add column store text not null default 'play';
alter table user_subscriptions add column store_transaction_id text;
create unique index on user_subscriptions (store, store_transaction_id); -- double client verify = no-op

-- FIX existing partial unique: it assumes ONE store per user and would explode.
-- Was effectively unique(user_id) where active; must become:
--   unique (user_id, store) where <active predicate>
```

Three ISN rules (apply to BOTH origins):
1. **Webhook is the doorbell, the API is the truth.** Never write entitlement from the webhook payload. Flow: notification arrives → verify signature (Samsung JWT vs public key; Pub/Sub for RTDN) → store raw event → call server-to-server API (Play Developer API / Samsung Subscription/Orders API) for authoritative state → write entitlement from THAT response.
2. **Idempotency** by `(store, event_id)` and `(store, transaction_id)`.
3. **Reconciliation by cron** — reuse existing `pg_cron`/`pg_net` (24/7 alerts): daily job sweeps active subs near expiry, queries the store API. Webhooks (Samsung included) get lost.

RPC `subscription_status` becomes an aggregation: `has_subscription` = any active row in any store; `expires_at` = max; new `active_stores` array. Additive change — old app versions parsing the current shape keep working.

Same user in both stores: server accepts (OR of access, max expiry, never reject an already-charged payment). Client prevents in `subscription_pitch_page`: if `active_stores` contains the OTHER store → banner "Ya tienes Pixora Premium vía <store>; adminístrala allá" + disable purchase.

Common state machine: map both stores' lifecycles to one internal vocabulary (`active`, `canceled_still_entitled`, `grace`, `on_hold`, `expired`, `revoked`). Don't let native store states leak into the table.

New Edge Functions: `verify_samsung_purchase` (on-purchase verify via Samsung Orders/Subscription API) + `samsung-isn-webhook`. Strict JWT validation (signature vs Samsung public key, `iss`, timestamp window) — public endpoint that grants premium.

---

## Section 4 — Package, signing, AdMob

- **Package:** same `com.orbix.pixora` both stores, no suffix. Rationale: OAuth/Google Sign-In, Firebase/FCM/Crashlytics, deep links, and device_id all key off package; a suffix doubles all of it and risks two Pixoras fighting on one device (the device_id unification pain, v1.7.72).
- **Signing:** Play App Signing CONFIRMED active. Play binary runs with Google's app signing key; Samsung binary signed with `release-key.jks` (upload key, SHA-1 `ff0f46d4...`). Signatures differ → no clean cross-store migration (acceptable; a device installs from one store). The upload-key SHA-1 is already registered in `google-services.json` → Google Sign-In works in the samsung flavor.
- **AdMob:** same AdMob app (deduped by package). New per-flavor ad units (`samsung_app_open`, `samsung_interstitial`, ...); flavor chooses which IDs load (extend `docs/admob_ad_units.md`). Register the Samsung device in `_testDeviceIds` for the samsung flavor. Do NOT open a second AdMob app/account.
- **Analytics split:** `appFlavor` → user property `store=samsung` in Firebase Analytics and Supabase `wallpaper_events`.

---

## Section 5 — Implementation phases

- **F0 — Extraction (Play only, no visible change).** Extract `PurchaseGateway` + `PlayPurchaseGateway` from `SubscriptionService`. No new features. Normal Play release. Validate the refactor with ONE variable in play. (Play App Signing already confirmed.)
- **F1 — Flavors + wiring.** `play`/`samsung` flavors, no suffix; `appFlavor`→`Store`; gate `init()`; samsung ad units in AdMob; user property `store`. Samsung flavor compiles + runs with purchases DISABLED (kill switch OFF). In parallel: register app + IAP items in Seller Portal (item review takes time).
- **F2 — Server first.** Migration (`store`/`store_transaction_id` columns, partial-unique fix, `billing_events`, aggregated RPC). `verify_samsung_purchase` + `samsung-isn-webhook` Edge Functions. Testable with curl + sample JWTs, no app needed.
- **F3 — Samsung client.** `IapHelper` in Kotlin under `src/samsung/`, MethodChannel `com.orbix.pixora/iap`, `SamsungPurchaseGateway`. Sandbox via Test Guide on the physical Samsung: purchase, pending, cancel, restore, refund.
- **F4 — E2E + reconciliation.** pg_cron reconciliation job. Test the double-store scenario (active Play sub trying to buy in samsung → banner). Real end-to-end ISN with a tester purchase.
- **F5 — Beta launch on Galaxy Store**, kill switch ready, monitor `billing_events` for a week, then production. Developer API upload automation deferred until the channel proves revenue.

---

## Testing

- Samsung IAP sandbox: physical Samsung + Samsung Account tester. RTL does NOT support purchases.
- **Restore purchases button is a Galaxy Store review requirement**, not optional — must call `gateway.restore()` → server re-verify. Preserve the existing `restorePurchases()` behavior through the refactor.
- ISN Edge Function tested with curl + sample signed JWTs before the client exists.
- No automated test suite in this repo; validation is manual on device + curl for server.

---

## Gotchas (do not re-learn)

1. **Error 106** = IAP item not connected in Seller Portal (must be "For Sale") OR wrong binary state / production IAP mode before publish. Budget an afternoon for test-mode setup with Samsung-registered testers.
2. **Remote Test Lab can't test purchases** (payment restriction on remote devices). Physical Samsung only.
3. **Restore is a review requirement** in Galaxy Store.
4. **Samsung subscriptions are less capable than Play** (upgrade/downgrade, intro offers, grace periods differ, configured in Seller Portal). Don't promise in the samsung UI anything only Play supports — hence per-store product catalog.
5. **Release cadence doubles** — two binaries, two reviews, different approval times. Extend `pixora-release-prep`. Watch the documented `local.properties` stale versionCode pitfall — now bites in two builds.
6. **Remote kill switch** (Text CMS / remote catalog) to disable samsung purchase without a release, for when ISN/verify break in production.
7. **iOS/debug `appFlavor` is null** → default `Store.play` so `flutter run` and iOS builds don't crash. Subscription page already gated off iOS.
8. **ISN Edge Function is a public endpoint that grants premium** → strict JWT validation (signature vs Samsung public key, `iss`, timestamp window) or someone fabricates subs with curl. Seller Portal service account → `orbixprivate`/`KEYS_LOCAL.md`, never the repo.
9. **Galaxy Store is an incremental channel**, not a second Play — most Samsung users still install from Play (that flavor buys via Google). Set revenue/maintenance expectations accordingly.

---

10. **Flavor builds must be isolated (F1 lesson, 2026-08-23).** Compiling `play` and `samsung` back-to-back without `flutter clean` between them can embed the WRONG flavor's Dart code in the APK (stale snapshot cache) — a samsung APK came out with `PlayPurchaseGateway` instead of `DisabledPurchaseGateway`. The source was correct; a clean rebuild fixed it. `pixora-release-prep` must `flutter clean` between per-flavor builds. A samsung AAB with Play Billing embedded violates Galaxy Store policy and doesn't work. Also: `android:allowBackup` defaults true → SharedPreferences restore across reinstalls (play/samsung share package + debug key) can leak first-run state in QA.

## Open questions

None blocking. Play App Signing confirmed active (2026-08-23). Product catalog: samsung reuses `pixora_monthly` logical ID with its own Seller Portal SKU (confirm exact SKU string at F1).
