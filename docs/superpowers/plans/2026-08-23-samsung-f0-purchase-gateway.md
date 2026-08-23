# Samsung F0 — PurchaseGateway Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a store-agnostic `PurchaseGateway` (interface + `PlayPurchaseGateway` implementation) out from under the existing `SubscriptionService`, with zero visible behavior change, and ship to Play to validate the refactor with one variable in play.

**Architecture:** `SubscriptionService` keeps its entitlement role (Supabase RPC, Realtime, `hasAccess`) but stops talking to `InAppPurchase.instance` directly. All store I/O moves behind a `PurchaseGateway` interface; `PlayPurchaseGateway` wraps `in_app_purchase`. `SubscriptionService` listens to `gateway.purchases` and delegates buy/restore/finish. No flavors, no Samsung, no server changes yet.

**Tech Stack:** Flutter, `in_app_purchase ^3.3.0`, Supabase (`supabase_flutter`), `ChangeNotifier`.

**Spec:** `docs/superpowers/specs/2026-08-23-samsung-galaxy-store-design.md` (Sections 1–2)

## Global Constraints

- Package stays `com.orbix.pixora`. No flavors, no Samsung, no server/Edge Function changes in F0.
- **Zero visible behavior change**: same purchase flow, same restore flow, same price string shown to the user.
- Pixora has **NO automated test suite**. Verification per task = `flutter analyze` (static). Functional verification = manual on device (Samsung `RF8X903KZ3K`) via `orbix-dev-guardian` at the end.
- `SubscriptionService` stays the **single owner** of entitlement state — the gateway never reads/writes entitlement.
- `SubscriptionService` public API stays stable EXCEPT `ProductDetails? get monthlyProduct` becomes `String? get monthlyPrice` (the only leaked Play type). All other getters/methods (`status`, `hasAccess`, `expiresAt`, `buyMonthly()`, `restorePurchases()`, `retryVerification()`, `purchaseInFlight`, `storeAvailable`, `onSignIn/onSignOut`, `debugGrantAccess`) keep their exact signatures.
- No `dart-define`, no `appFlavor` in F0 (that is F1). `SubscriptionService` instantiates `PlayPurchaseGateway()` directly.

---

## File Structure

- **Create** `lib/core/services/billing/purchase_gateway.dart` — enums (`Store`, `ProductKind`, `PurchaseState`), value types (`StoreProduct`, `StorePurchase`), abstract `PurchaseGateway`.
- **Create** `lib/core/services/billing/product_catalog.dart` — logicalId ↔ storeSku map (Play only for now).
- **Create** `lib/core/services/billing/play_purchase_gateway.dart` — `PlayPurchaseGateway implements PurchaseGateway`, wraps `in_app_purchase`. Owns the only `import 'package:in_app_purchase/...'` outside legacy.
- **Modify** `lib/core/services/subscription_service.dart` — use the gateway; drop direct `InAppPurchase` calls; `monthlyProduct`→`monthlyPrice`.
- **Modify** UI call sites of `monthlyProduct?.price` (3): `lib/features/perfil/presentation/perfil_page.dart:93` and `:395`, `lib/features/subscription/presentation/subscription_pitch_page.dart:79`.

---

## Task 1: Gateway types + interface

**Files:**
- Create: `lib/core/services/billing/purchase_gateway.dart`

**Interfaces:**
- Produces: `Store`, `ProductKind`, `PurchaseState` enums; `StoreProduct`, `StorePurchase` classes; abstract `PurchaseGateway` with `store`, `isAvailable()`, `queryProducts(Set<String>)`, `purchases` (Stream), `buy(StoreProduct)`, `finish(StorePurchase,{bool consume})`, `restore()`, `manageSubscriptionUri(String)`, `dispose()`.

- [ ] **Step 1: Create the file with types and interface**

```dart
// lib/core/services/billing/purchase_gateway.dart
//
// Store-agnostic purchase abstraction. No Play/Samsung SDK types leak across
// this boundary — the opaque `verificationBlob` is the deliberate exception,
// interpreted only server-side. See the F0 plan / Samsung Galaxy Store spec.

enum Store { play, samsung }

enum ProductKind { consumable, nonConsumable, subscription }

enum PurchaseState { pending, purchased, canceled, failed }

class StoreProduct {
  const StoreProduct({
    required this.logicalId,
    required this.storeSku,
    required this.kind,
    required this.title,
    required this.formattedPrice,
    required this.currencyCode,
    this.subscriptionPeriod,
  });

  final String logicalId; // Pixora-internal ID, e.g. 'pixora_monthly'
  final String storeSku; // real ID registered in that store
  final ProductKind kind;
  final String title;
  final String formattedPrice; // store-localized; NEVER parse
  final String currencyCode;
  final String? subscriptionPeriod; // ISO-8601, e.g. 'P1M'
}

class StorePurchase {
  const StorePurchase({
    required this.store,
    required this.logicalId,
    required this.transactionId,
    required this.state,
    required this.verificationBlob,
    this.isRestored = false,
    this.errorMessage,
  });

  final Store store;
  final String logicalId;
  final String transactionId; // purchaseToken (Play) | purchaseId (Samsung)
  final PurchaseState state;
  final Map<String, dynamic> verificationBlob; // opaque; server-only
  final bool isRestored;
  final String? errorMessage;
}

abstract class PurchaseGateway {
  Store get store;

  Future<bool> isAvailable();

  /// Fetch store details for the given Pixora logical IDs.
  Future<List<StoreProduct>> queryProducts(Set<String> logicalIds);

  /// The ONLY channel for purchase results: new buys, resolved pendings,
  /// and restores (isRestored=true).
  Stream<StorePurchase> get purchases;

  /// Launch the store purchase flow. Returns nothing — the result arrives
  /// asynchronously via [purchases].
  Future<void> buy(StoreProduct product);

  /// Unifies acknowledge/consume/completePurchase. Call only AFTER the
  /// server has verified the purchase.
  Future<void> finish(StorePurchase purchase, {required bool consume});

  /// Re-emits owned products via [purchases] with isRestored=true.
  Future<void> restore();

  /// Deep link to the store's "manage subscription" screen, or null.
  Uri? manageSubscriptionUri(String logicalId);

  void dispose();
}
```

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/core/services/billing/purchase_gateway.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/billing/purchase_gateway.dart
git commit -m "feat(billing): add store-agnostic PurchaseGateway interface + types"
```

---

## Task 2: Product catalog (logicalId ↔ SKU)

**Files:**
- Create: `lib/core/services/billing/product_catalog.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `ProductCatalog` with `static const monthly = 'pixora_monthly'`, `static Set<String> get allLogicalIds`, `static String skuFor(Store store, String logicalId)`, `static ProductKind kindFor(String logicalId)`.

- [ ] **Step 1: Create the catalog**

```dart
// lib/core/services/billing/product_catalog.dart
import 'purchase_gateway.dart';

/// Maps Pixora-internal logical product IDs to the real SKU registered in
/// each store. In F0 only Play exists and the SKU equals the logical ID.
/// When Samsung is added (F1+), its SKU column is filled here — nothing else
/// in the app needs to change.
class ProductCatalog {
  ProductCatalog._();

  static const String monthly = 'pixora_monthly';

  static Set<String> get allLogicalIds => const {monthly};

  static ProductKind kindFor(String logicalId) {
    switch (logicalId) {
      case monthly:
        return ProductKind.subscription;
      default:
        return ProductKind.subscription;
    }
  }

  /// Real store SKU for a logical ID. Play currently uses the logical ID
  /// verbatim. Samsung SKUs get added to this switch at F1.
  static String skuFor(Store store, String logicalId) {
    switch (store) {
      case Store.play:
        return logicalId; // Play Console SKU == logical ID today
      case Store.samsung:
        return logicalId; // placeholder until Samsung Seller Portal SKUs exist (F1)
    }
  }
}
```

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/core/services/billing/product_catalog.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/billing/product_catalog.dart
git commit -m "feat(billing): add ProductCatalog (logicalId <-> store SKU map)"
```

---

## Task 3: PlayPurchaseGateway (wraps in_app_purchase)

**Files:**
- Create: `lib/core/services/billing/play_purchase_gateway.dart`

**Interfaces:**
- Consumes: `PurchaseGateway`, `StoreProduct`, `StorePurchase`, `Store`, `ProductKind`, `PurchaseState` (Task 1); `ProductCatalog` (Task 2).
- Produces: `PlayPurchaseGateway implements PurchaseGateway` with a default constructor. Emits `StorePurchase` on `purchases`. Maps `PurchaseDetails` → `StorePurchase` with `verificationBlob = {'purchaseToken': serverVerificationData, 'productId': productID, 'source': source}`.

This is where ALL `in_app_purchase` code from `SubscriptionService` moves. Behavior must match the current `_handlePurchaseUpdate` / `buyMonthly` / `restorePurchases` logic exactly.

- [ ] **Step 1: Create the gateway**

```dart
// lib/core/services/billing/play_purchase_gateway.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'product_catalog.dart';
import 'purchase_gateway.dart';

/// Google Play implementation of [PurchaseGateway]. Owns the only
/// `in_app_purchase` usage in the app. Translates Play's `PurchaseDetails`
/// into store-agnostic `StorePurchase` events.
class PlayPurchaseGateway implements PurchaseGateway {
  PlayPurchaseGateway();

  @override
  Store get store => Store.play;

  final _iap = InAppPurchase.instance;
  final _controller = StreamController<StorePurchase>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  // Cache ProductDetails by logicalId (from queryProducts) so buy() can find
  // the object Play needs, and PurchaseDetails by transactionId so finish()
  // can complete the right one — without leaking Play types across the API.
  final Map<String, ProductDetails> _detailsByLogicalId = {};
  final Map<String, PurchaseDetails> _pendingByTxn = {};

  bool _listening = false;

  @override
  Stream<StorePurchase> get purchases => _controller.stream;

  @override
  Future<bool> isAvailable() async {
    final ok = await _iap.isAvailable();
    if (ok && !_listening) {
      _sub = _iap.purchaseStream.listen(
        _onPlayUpdate,
        onError: (Object e) => debugPrint('[PlayGW] purchaseStream error: $e'),
      );
      _listening = true;
    }
    return ok;
  }

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> logicalIds) async {
    final skus =
        logicalIds.map((id) => ProductCatalog.skuFor(Store.play, id)).toSet();
    final resp = await _iap.queryProductDetails(skus);
    if (resp.error != null) {
      debugPrint('[PlayGW] queryProductDetails error: ${resp.error}');
    }
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint('[PlayGW] SKUs not found on Play: ${resp.notFoundIDs} '
          '(unpublished or still propagating, up to 24h)');
    }
    final out = <StoreProduct>[];
    for (final p in resp.productDetails) {
      // In F0 the Play SKU equals the logical ID.
      final logicalId = p.id;
      _detailsByLogicalId[logicalId] = p;
      out.add(StoreProduct(
        logicalId: logicalId,
        storeSku: p.id,
        kind: ProductCatalog.kindFor(logicalId),
        title: p.title,
        formattedPrice: p.price,
        currencyCode: p.currencyCode,
        subscriptionPeriod: null,
      ));
    }
    return out;
  }

  @override
  Future<void> buy(StoreProduct product) async {
    final details = _detailsByLogicalId[product.logicalId];
    if (details == null) {
      debugPrint('[PlayGW] buy: no ProductDetails cached for '
          '${product.logicalId} — call queryProducts first');
      return;
    }
    final param = PurchaseParam(productDetails: details);
    // Subscriptions use buyNonConsumable per in_app_purchase docs.
    final shown = await _iap.buyNonConsumable(purchaseParam: param);
    if (!shown) debugPrint('[PlayGW] buyNonConsumable returned false');
  }

  @override
  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  @override
  Future<void> finish(StorePurchase purchase, {required bool consume}) async {
    final details = _pendingByTxn.remove(purchase.transactionId);
    if (details == null) return;
    if (details.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(details);
      } catch (e) {
        debugPrint('[PlayGW] completePurchase failed: $e');
      }
    }
  }

  @override
  Uri? manageSubscriptionUri(String logicalId) {
    final sku = ProductCatalog.skuFor(Store.play, logicalId);
    return Uri.parse(
        'https://play.google.com/store/account/subscriptions?sku=$sku&package=com.orbix.pixora');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }

  void _onPlayUpdate(List<PurchaseDetails> list) {
    for (final p in list) {
      _pendingByTxn[p.verificationData.serverVerificationData] = p;
      final state = switch (p.status) {
        PurchaseStatus.pending => PurchaseState.pending,
        PurchaseStatus.purchased => PurchaseState.purchased,
        PurchaseStatus.restored => PurchaseState.purchased,
        PurchaseStatus.canceled => PurchaseState.canceled,
        PurchaseStatus.error => PurchaseState.failed,
      };
      _controller.add(StorePurchase(
        store: Store.play,
        logicalId: p.productID, // Play SKU == logical ID in F0
        transactionId: p.verificationData.serverVerificationData,
        state: state,
        isRestored: p.status == PurchaseStatus.restored,
        errorMessage: p.error?.message,
        verificationBlob: {
          'purchaseToken': p.verificationData.serverVerificationData,
          'productId': p.productID,
          'source': p.verificationData.source,
        },
      ));
    }
  }
}
```

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/core/services/billing/play_purchase_gateway.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/billing/play_purchase_gateway.dart
git commit -m "feat(billing): add PlayPurchaseGateway wrapping in_app_purchase"
```

---

## Task 4: Refactor SubscriptionService to use the gateway

**Files:**
- Modify: `lib/core/services/subscription_service.dart`

**Interfaces:**
- Consumes: `PlayPurchaseGateway` (Task 3), `PurchaseGateway`, `StorePurchase`, `PurchaseState`, `StoreProduct` (Task 1), `ProductCatalog` (Task 2).
- Produces: unchanged public API EXCEPT `String? get monthlyPrice` replaces `ProductDetails? get monthlyProduct`.

The goal: remove every `InAppPurchase.instance` / `PurchaseDetails` / `PurchaseParam` reference from this file; route everything through `_gateway`. Keep all entitlement code (`refreshStatus`, `_setFromJson`, `_verifyWithServer`, Realtime, `onSignIn/onSignOut`) untouched.

- [ ] **Step 1: Swap imports and fields**

Replace the `in_app_purchase` import:
```dart
// REMOVE: import 'package:in_app_purchase/in_app_purchase.dart';
import 'billing/purchase_gateway.dart';
import 'billing/play_purchase_gateway.dart';
import 'billing/product_catalog.dart';
```

Replace the store-facing fields (around lines 74–76, 115):
```dart
// REMOVE: ProductDetails? _monthlyProduct;
StoreProduct? _monthlyProductInfo;
bool _storeAvailable = false;
bool _purchaseInFlight = false;

final PurchaseGateway _gateway = PlayPurchaseGateway();
// REMOVE: StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
StreamSubscription<StorePurchase>? _purchaseSub;
```

- [ ] **Step 2: Replace the `monthlyProduct` getter with `monthlyPrice`**

```dart
// REMOVE: ProductDetails? get monthlyProduct => _monthlyProduct;
String? get monthlyPrice => _monthlyProductInfo?.formattedPrice;
bool get storeAvailable => _storeAvailable;
bool get purchaseInFlight => _purchaseInFlight;
```

- [ ] **Step 3: Rewrite `init()` to listen to the gateway**

```dart
Future<void> init() async {
  try {
    _storeAvailable = await _gateway.isAvailable();
    if (!_storeAvailable) {
      debugPrint('[Subs] store billing not available on this device');
      return;
    }
    _purchaseSub = _gateway.purchases.listen(
      _onPurchase,
      onError: (Object e) => debugPrint('[Subs] purchases stream error: $e'),
    );
    await _loadProducts();
    if (_isLoggedIn) {
      unawaited(refreshStatus());
      _subscribeToRealtime();
    }
  } catch (e) {
    debugPrint('[Subs] init failed: $e');
  }
}
```

- [ ] **Step 4: Rewrite `_loadProducts()` via the gateway**

```dart
Future<void> _loadProducts() async {
  try {
    final products = await _gateway.queryProducts(ProductCatalog.allLogicalIds);
    for (final p in products) {
      if (p.logicalId == ProductCatalog.monthly) _monthlyProductInfo = p;
    }
    notifyListeners();
  } catch (e) {
    debugPrint('[Subs] _loadProducts failed: $e');
  }
}
```

- [ ] **Step 5: Rewrite `buyMonthly()` to delegate to the gateway**

```dart
Future<bool> buyMonthly() async {
  if (!_storeAvailable) {
    debugPrint('[Subs] Store not available');
    return false;
  }
  if (_monthlyProductInfo == null) {
    await _loadProducts();
    if (_monthlyProductInfo == null) {
      debugPrint('[Subs] Monthly product not loaded — is it published?');
      return false;
    }
  }
  if (!_isLoggedIn) {
    debugPrint('[Subs] Cannot buy — user not authenticated');
    return false;
  }
  _purchaseInFlight = true;
  notifyListeners();
  try {
    await _gateway.buy(_monthlyProductInfo!);
    return true; // sheet launched; result arrives via _onPurchase
  } catch (e) {
    debugPrint('[Subs] buyMonthly failed: $e');
    return false;
  } finally {
    _purchaseInFlight = false;
    notifyListeners();
  }
}
```

- [ ] **Step 6: Rewrite `restorePurchases()` to delegate**

```dart
Future<int> restorePurchases() async {
  if (!_storeAvailable) return 0;
  _restoredCountSinceCall = 0;
  try {
    debugPrint('[Subs] restorePurchases → gateway.restore');
    await _gateway.restore();
    await Future.delayed(const Duration(seconds: 2));
    debugPrint('[Subs] restore done — saw $_restoredCountSinceCall purchases');
    return _restoredCountSinceCall;
  } catch (e) {
    debugPrint('[Subs] restorePurchases failed: $e');
    return 0;
  }
}
```

- [ ] **Step 7: Replace `_handlePurchaseUpdate` with `_onPurchase(StorePurchase)`**

Delete the old `_handlePurchaseUpdate(List<PurchaseDetails>)` method entirely and add:

```dart
void _onPurchase(StorePurchase p) async {
  debugPrint('[Subs] _onPurchase: logicalId=${p.logicalId} state=${p.state} '
      'restored=${p.isRestored}');
  switch (p.state) {
    case PurchaseState.pending:
      debugPrint('[Subs] purchase pending: ${p.logicalId}');
      break;
    case PurchaseState.purchased:
      if (p.isRestored) _restoredCountSinceCall++;
      await _verifyPurchase(p);
      break;
    case PurchaseState.failed:
      debugPrint('[Subs] purchase error: ${p.errorMessage}');
      break;
    case PurchaseState.canceled:
      debugPrint('[Subs] purchase canceled by user');
      break;
  }
  // Always finish so the item leaves the store queue.
  await _gateway.finish(p, consume: false);
}
```

- [ ] **Step 8: Adapt `_verifyWithServer` into `_verifyPurchase(StorePurchase)`**

Keep the existing 3-attempt retry + session check logic; only change how the token/product come in — now from `StorePurchase.verificationBlob` instead of `PurchaseDetails`:

```dart
Future<void> _verifyPurchase(StorePurchase p) async {
  debugPrint('[Subs] _verifyPurchase START for ${p.logicalId}');
  if (!_isLoggedIn) {
    debugPrint('[Subs] verification deferred — user not logged in');
    return;
  }
  final purchaseToken = p.verificationBlob['purchaseToken'] as String? ?? '';
  final productId = p.verificationBlob['productId'] as String? ?? p.logicalId;
  if (purchaseToken.isEmpty) {
    debugPrint('[Subs] ABORT: empty purchase_token');
    return;
  }
  final session = _sb.auth.currentSession;
  if (session == null) {
    debugPrint('[Subs] ABORT: no Supabase session at verify time');
    return;
  }
  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      final response = await _sb.functions.invoke(
        'verify_google_purchase',
        body: {'purchase_token': purchaseToken, 'product_id': productId},
      );
      final status = response.status;
      if (status == 200) {
        await refreshStatus();
        return;
      }
      if (status >= 400 && status < 500) {
        debugPrint('[Subs] verify client error $status — not retrying');
        return;
      }
      lastError = 'status=$status';
    } catch (e) {
      lastError = e;
    }
    if (attempt < 3) {
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    }
  }
  debugPrint('[Subs] _verifyPurchase gave up after 3 attempts. last=$lastError');
  try {
    await refreshStatus();
  } catch (_) {}
}
```

- [ ] **Step 9: Update `dispose()`**

```dart
@override
void dispose() {
  _purchaseSub?.cancel();
  _gateway.dispose();
  _realtimeChannel?.unsubscribe();
  super.dispose();
}
```

- [ ] **Step 10: Verify the whole app analyzes clean**

Run: `flutter analyze lib/core/services/subscription_service.dart lib/core/services/billing/`
Expected: `No issues found!` (fix any leftover `InAppPurchase`/`ProductDetails`/`PurchaseParam` references — there should be none)

- [ ] **Step 11: Commit**

```bash
git add lib/core/services/subscription_service.dart
git commit -m "refactor(billing): route SubscriptionService through PurchaseGateway"
```

---

## Task 5: Update UI call sites of `monthlyProduct`

**Files:**
- Modify: `lib/features/perfil/presentation/perfil_page.dart:93` and `:395`
- Modify: `lib/features/subscription/presentation/subscription_pitch_page.dart:79`

**Interfaces:**
- Consumes: `SubscriptionService.instance.monthlyPrice` (String?, Task 4).

The old `monthlyProduct?.price` returned a `String?` (Play's localized price). `monthlyPrice` returns the same `String?`. Behavior identical.

- [ ] **Step 1: Update `perfil_page.dart`**

Both occurrences change from:
```dart
SubscriptionService.instance.monthlyProduct?.price ?? '...'
```
to:
```dart
SubscriptionService.instance.monthlyPrice ?? '...'
```
Keep each existing fallback string exactly as-is (`:93` and `:395` — the `:395` fallback is `'\$199 MXN'`).

- [ ] **Step 2: Update `subscription_pitch_page.dart:79`**

Change from:
```dart
final p = SubscriptionService.instance.monthlyProduct?.price;
```
to:
```dart
final p = SubscriptionService.instance.monthlyPrice;
```

- [ ] **Step 3: Verify the app analyzes clean**

Run: `flutter analyze lib`
Expected: `No issues found!` (no remaining references to `monthlyProduct`)

- [ ] **Step 4: Grep to confirm no stragglers**

Run: `grep -rn "monthlyProduct" lib`
Expected: no output (all migrated to `monthlyPrice`)

- [ ] **Step 5: Commit**

```bash
git add lib/features/perfil/presentation/perfil_page.dart lib/features/subscription/presentation/subscription_pitch_page.dart
git commit -m "refactor(billing): UI reads monthlyPrice instead of monthlyProduct"
```

---

## Task 6: Device validation (the F0 gate)

**Files:** none (verification only)

This replaces the unit-test cycle Pixora doesn't have. Dispatch `orbix-dev-guardian` to validate on the physical Samsung.

- [ ] **Step 1: Full analyze**

Run: `flutter analyze lib`
Expected: `No issues found!`

- [ ] **Step 2: Debug build**

Run: `flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 3: Install + smoke test on Samsung via orbix-dev-guardian**

Dispatch `orbix-dev-guardian` with this scope:
- Install `app-debug.apk` on Samsung `RF8X903KZ3K` (uninstall first if `INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
- Launch, read logcat filtering `flutter|Pixora|Subs|PlayGW|AndroidRuntime|FATAL`. Confirm no crash at startup.
- Open the subscription pitch page; confirm the **monthly price string still renders** (proves `queryProducts` → `monthlyPrice` path works end to end).
- Open Perfil; confirm the price shows there too.
- Tap **Restore purchases** in Perfil; confirm logcat shows `[Subs] restorePurchases → gateway.restore` and `[PlayGW]`/restore events flow, and `refreshStatus` runs without error.
- ⚠️ SECURITY: screencap (read-only) BEFORE any input event; never tap blind (banking-incident rule). Enter Pixora via `am start -n com.orbix.pixora/.MainActivity`, use `uiautomator dump` for exact bounds before taps.
- Report PASS/FAIL: analyze result, build result, no-crash, price renders (pitch + perfil), restore path fires.

- [ ] **Step 4: Commit any fixes surfaced by validation**

If the guardian finds an issue, fix it, re-run analyze + build, and commit with a `fix(billing):` message describing the fix. Re-dispatch the guardian until PASS.

---

## Release note (out of code scope)

Shipping F0 to Play (bump version, `flutter build appbundle`, upload) is a **release action** handled via the `pixora-release-prep` skill AFTER this plan's tasks pass on device. It is intentionally not a code task here — F0's code deliverable ends at a green device validation.

---

## Self-Review

**Spec coverage (Sections 1–2):** ✅ Interface (Task 1), catalog/logicalId↔SKU (Task 2), PlayPurchaseGateway wrapping in_app_purchase + opaque verificationBlob + buy()→void + restore-to-stream + finish(consume:) (Task 3), extraction map with SubscriptionService keeping entitlement role (Task 4), single owner of state via `_onPurchase` glue (Task 4). Flavors/Samsung/server explicitly deferred to F1–F3 per scope.

**Placeholder scan:** No TBD/TODO. `skuFor(Store.samsung, ...)` returns a documented interim value (logical ID) labeled as filled at F1 — an explicit forward note, not a gap, since Samsung is out of F0 scope.

**Type consistency:** `monthlyPrice` (String?) used consistently in Tasks 4–5. `StorePurchase.transactionId` used as both the emit key and the `finish()` lookup key (`_pendingByTxn`) in Task 3. `verificationBlob` keys (`purchaseToken`, `productId`) written in Task 3 and read in Task 4 Step 8 — matched.
