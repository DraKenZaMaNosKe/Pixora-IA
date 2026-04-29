import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Subscription state for the current user. Sourced from the Supabase
/// `subscription_status` RPC which is the server-side source of truth.
///
/// - `unknown`: service not yet initialized or status fetch not attempted.
/// - `notAuthenticated`: user is signed out — subscriptions require auth.
/// - `free`: signed in, no active subscription. May still have `free_gens_remaining`.
/// - `trial`: in 7-day free trial (card registered via Google Play but no charge yet).
/// - `active`: paid and current.
/// - `grace`: payment failed, Google is retrying. User keeps access.
/// - `onHold`: grace period expired. Access cut until user updates payment.
/// - `paused`: user paused the subscription via Play Store.
/// - `cancelled`: user cancelled but still has access until `expires_at`.
/// - `expired`: subscription ended.
enum SubscriptionStatus {
  unknown,
  notAuthenticated,
  free,
  trial,
  active,
  grace,
  onHold,
  paused,
  cancelled,
  expired,
}

extension SubscriptionStatusX on SubscriptionStatus {
  /// True if the user currently has access to subscription benefits.
  bool get hasAccess =>
      this == SubscriptionStatus.trial ||
      this == SubscriptionStatus.active ||
      this == SubscriptionStatus.grace ||
      this ==
          SubscriptionStatus
              .cancelled; // cancelled = still active until expires_at
}

/// Central service for Google Play subscriptions + Pixora's subscription logic.
///
/// Flow:
/// 1. `init()` — wire up IAP listeners, restore past purchases.
/// 2. `loadProducts()` — fetch SKU details from Play Store.
/// 3. `buy(product)` — launch Google Play purchase sheet.
/// 4. On purchase success, `_handlePurchaseUpdate` receives the event and
///    calls `_verifyWithServer(purchaseToken)` which proxies to a Supabase
///    Edge Function. The Edge Function verifies the token with Google Play
///    Developer API and upserts `user_subscriptions`.
/// 5. UI listens via `ChangeNotifier` and re-reads `status`, `expiresAt`, etc.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final instance = SubscriptionService._();

  // ── Play Store product IDs (must match Play Console SKUs) ────────────
  static const productMonthly = 'pixora_monthly';
  static const _allProductIds = <String>{productMonthly};

  // ── State ────────────────────────────────────────────────────────────
  SubscriptionStatus _status = SubscriptionStatus.unknown;
  String? _tier;
  // ignore: unused_field
  String? _productId; // surfaced in UI phase + for receipt verification
  DateTime? _trialEndsAt;
  DateTime? _expiresAt;
  bool _autoRenew = true;
  int _generationsUsed = 0;
  int _generationsLimit = 0;
  int _freeGensRemaining = 0;
  ProductDetails? _monthlyProduct;
  bool _storeAvailable = false;
  bool _purchaseInFlight = false;

  SubscriptionStatus get status => _status;
  String? get tier => _tier;
  DateTime? get trialEndsAt => _trialEndsAt;
  DateTime? get expiresAt => _expiresAt;
  bool get autoRenew => _autoRenew;
  int get generationsUsed => _generationsUsed;
  int get generationsLimit => _generationsLimit;
  int get generationsRemaining =>
      (_generationsLimit - _generationsUsed).clamp(0, 999999);
  int get freeGensRemaining => _freeGensRemaining;
  bool get hasAccess => _status.hasAccess;
  bool get canGenerate =>
      hasAccess && generationsRemaining > 0 || _freeGensRemaining > 0;
  ProductDetails? get monthlyProduct => _monthlyProduct;
  bool get storeAvailable => _storeAvailable;
  bool get purchaseInFlight => _purchaseInFlight;

  SupabaseClient get _sb => Supabase.instance.client;
  bool get _isLoggedIn => _sb.auth.currentUser != null;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  RealtimeChannel? _realtimeChannel;

  // ── Init / dispose ──────────────────────────────────────────────────

  Future<void> init() async {
    try {
      _storeAvailable = await InAppPurchase.instance.isAvailable();
      if (!_storeAvailable) {
        debugPrint('[Subs] Play Store billing not available on this device');
        return;
      }
      _purchaseSub = InAppPurchase.instance.purchaseStream.listen(
        _handlePurchaseUpdate,
        onError: (Object e) => debugPrint('[Subs] purchaseStream error: $e'),
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

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  // ── Product catalog ─────────────────────────────────────────────────

  Future<void> _loadProducts() async {
    try {
      final response =
          await InAppPurchase.instance.queryProductDetails(_allProductIds);
      if (response.error != null) {
        debugPrint('[Subs] queryProductDetails error: ${response.error}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
            '[Subs] SKUs not found on Play Store: ${response.notFoundIDs}. '
            'Likely not yet published or propagating — can take up to 24h after '
            'creation in Play Console.');
      }
      for (final p in response.productDetails) {
        if (p.id == productMonthly) _monthlyProduct = p;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Subs] _loadProducts failed: $e');
    }
  }

  /// Re-fetch product catalog. Useful if the user just authenticated or
  /// the app was opened right after a Play Console change.
  Future<void> refreshProducts() => _loadProducts();

  // ── Server status ───────────────────────────────────────────────────

  /// Fetch the canonical subscription status from Supabase.
  Future<void> refreshStatus() async {
    if (!_isLoggedIn) {
      _setFromJson(null);
      return;
    }
    try {
      final raw = await _sb.rpc('subscription_status');
      if (raw is Map) {
        _setFromJson(Map<String, dynamic>.from(raw));
      }
    } catch (e) {
      debugPrint('[Subs] refreshStatus failed: $e');
    }
  }

  void _setFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      _status = SubscriptionStatus.notAuthenticated;
    } else if (json['authenticated'] != true) {
      _status = SubscriptionStatus.notAuthenticated;
    } else if (json['has_subscription'] != true) {
      _status = SubscriptionStatus.free;
      _tier = null;
      _productId = null;
      _trialEndsAt = null;
      _expiresAt = null;
      _generationsUsed = 0;
      _generationsLimit = 0;
      _freeGensRemaining = (json['free_gens_remaining'] as int?) ?? 0;
    } else {
      _status = _parseStatus(json['status'] as String?);
      _tier = json['tier'] as String?;
      _productId = json['product_id'] as String?;
      _trialEndsAt = _parseDate(json['trial_ends_at']);
      _expiresAt = _parseDate(json['expires_at']);
      _autoRenew = json['auto_renew'] == true;
      _generationsUsed = (json['generations_used'] as int?) ?? 0;
      _generationsLimit = (json['generations_limit'] as int?) ?? 0;
      _freeGensRemaining = (json['free_gens_remaining'] as int?) ?? 0;
    }
    notifyListeners();
  }

  SubscriptionStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'trial':
        return SubscriptionStatus.trial;
      case 'active':
        return SubscriptionStatus.active;
      case 'in_grace_period':
        return SubscriptionStatus.grace;
      case 'on_hold':
        return SubscriptionStatus.onHold;
      case 'paused':
        return SubscriptionStatus.paused;
      case 'cancelled':
        return SubscriptionStatus.cancelled;
      case 'expired':
      case 'refunded':
        return SubscriptionStatus.expired;
      default:
        return SubscriptionStatus.unknown;
    }
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  // ── Purchasing ──────────────────────────────────────────────────────

  /// Launches the Play Store purchase sheet for the monthly subscription.
  /// Returns `true` if the sheet was shown; the actual purchase completion
  /// arrives asynchronously via the `purchaseStream`.
  Future<bool> buyMonthly() async {
    if (!_storeAvailable) {
      debugPrint('[Subs] Store not available');
      return false;
    }
    if (_monthlyProduct == null) {
      await _loadProducts();
      if (_monthlyProduct == null) {
        debugPrint('[Subs] Monthly SKU not loaded — is it published?');
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
      final param = PurchaseParam(productDetails: _monthlyProduct!);
      // For subscriptions, `buyNonConsumable` is correct per the
      // in_app_purchase docs. Consumables are only for one-time goods
      // that can be re-bought (coins, gems).
      final shown =
          await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      if (!shown) {
        debugPrint('[Subs] buyNonConsumable returned false');
      }
      return shown;
    } catch (e) {
      debugPrint('[Subs] buyMonthly failed: $e');
      return false;
    } finally {
      _purchaseInFlight = false;
      notifyListeners();
    }
  }

  /// Restore past purchases. Should be called on app start (we do this in
  /// `init`) and also when the user explicitly taps "Restore purchases".
  /// Returns the number of purchases seen during the restore window.
  Future<int> restorePurchases() async {
    if (!_storeAvailable) return 0;
    _restoredCountSinceCall = 0;
    try {
      debugPrint('[Subs] restorePurchases → calling IAP');
      await InAppPurchase.instance.restorePurchases();
      // Give the stream a moment to deliver restore events.
      await Future.delayed(const Duration(seconds: 2));
      debugPrint(
          '[Subs] restorePurchases done — saw $_restoredCountSinceCall purchases');
      return _restoredCountSinceCall;
    } catch (e, st) {
      debugPrint('[Subs] restorePurchases failed: $e');
      debugPrint('[Subs] stack: $st');
      return 0;
    }
  }

  /// Internal counter incremented every time a purchase is observed during a
  /// `restorePurchases()` call. Reset at the start of the call.
  int _restoredCountSinceCall = 0;

  /// User-triggered retry: calls restorePurchases + explicitly re-verifies
  /// every active purchase via the Edge Function. Used from the Settings
  /// "Re-verify subscription" button when the purchase stream didn't fire
  /// correctly on initial purchase.
  Future<String> retryVerification() async {
    if (!_isLoggedIn) return 'not_authenticated';
    debugPrint('[Subs] retryVerification → starting');
    final seen = await restorePurchases();
    await refreshStatus();
    if (seen == 0) {
      return 'no_active_purchase_found';
    }
    return 'ok_seen_$seen';
  }

  void _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    debugPrint('[Subs] _handlePurchaseUpdate: ${purchases.length} purchase(s)');
    for (final p in purchases) {
      debugPrint('[Subs]   -> productID=${p.productID} status=${p.status} '
          'pendingComplete=${p.pendingCompletePurchase}');
      switch (p.status) {
        case PurchaseStatus.pending:
          debugPrint('[Subs] Purchase pending: ${p.productID}');
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (p.status == PurchaseStatus.restored) _restoredCountSinceCall++;
          await _verifyWithServer(p);
          break;
        case PurchaseStatus.error:
          debugPrint('[Subs] Purchase error: ${p.error?.message} '
              'code=${p.error?.code}');
          break;
        case PurchaseStatus.canceled:
          debugPrint('[Subs] Purchase canceled by user');
          break;
      }
      // Always complete pending purchases once handled — removes from queue.
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
          debugPrint('[Subs] completePurchase OK for ${p.productID}');
        } catch (e) {
          debugPrint('[Subs] completePurchase failed: $e');
        }
      }
    }
  }

  Future<void> _verifyWithServer(PurchaseDetails p) async {
    // Use `print` instead of `debugPrint` to bypass Flutter's internal
    // throttling — we need every line of this path in logcat, even under load.
    debugPrint('[Subs] _verifyWithServer START for ${p.productID}');

    if (!_isLoggedIn) {
      debugPrint('[Subs] verification deferred — user not logged in');
      return;
    }
    final purchaseToken = p.verificationData.serverVerificationData;
    final productId = p.productID;
    final source = p.verificationData.source;
    debugPrint('[Subs] token source=$source tokenLen=${purchaseToken.length}');
    if (purchaseToken.isEmpty) {
      debugPrint('[Subs] ABORT: empty purchase_token');
      return;
    }

    // 1) Sanity check the auth session is still alive RIGHT NOW (the client
    //    could have logged out between the purchase start and completion).
    final session = _sb.auth.currentSession;
    debugPrint('[Subs] current session: hasUser=${session?.user != null} '
        'accessTokenLen=${session?.accessToken.length ?? 0} '
        'expiresAt=${session?.expiresAt}');
    if (session == null) {
      debugPrint('[Subs] ABORT: no Supabase session at verify time');
      return;
    }

    // 2) Call the Edge Function with up to 3 attempts (network flakes etc.).
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        debugPrint('[Subs] invoke attempt $attempt → verify_google_purchase');
        final response = await _sb.functions.invoke(
          'verify_google_purchase',
          body: {
            'purchase_token': purchaseToken,
            'product_id': productId,
          },
        );
        final status = response.status;
        final data = response.data;
        debugPrint('[Subs] invoke returned: status=$status data=$data');
        if (status == 200) {
          debugPrint('[Subs] verify SUCCESS on attempt $attempt');
          await refreshStatus();
          debugPrint('[Subs] status refreshed post-verify');
          return;
        }
        // Non-2xx but didn't throw — still report and break (retrying won't help
        // for 4xx).
        if (status >= 400 && status < 500) {
          debugPrint('[Subs] verify got client error $status — not retrying');
          return;
        }
        lastError = 'status=$status data=$data';
      } catch (e, st) {
        debugPrint('[Subs] invoke attempt $attempt threw: ${e.runtimeType}: $e');
        debugPrint('[Subs] stack: $st');
        lastError = e;
      }
      if (attempt < 3) {
        final backoff = Duration(milliseconds: 500 * attempt);
        debugPrint('[Subs] retrying after ${backoff.inMilliseconds}ms');
        await Future.delayed(backoff);
      }
    }
    debugPrint('[Subs] _verifyWithServer GAVE UP after 3 attempts. '
        'last=$lastError');
    // Still try to refresh in case a prior attempt wrote the row.
    try {
      await refreshStatus();
    } catch (_) {}
  }

  // ── Realtime ────────────────────────────────────────────────────────

  /// Subscribe to `user_subscriptions` updates so a change on another device
  /// (or an RTDN event received on the server) reflects here within ~1s.
  void _subscribeToRealtime() {
    if (!_isLoggedIn || _realtimeChannel != null) return;
    final uid = _sb.auth.currentUser!.id;
    _realtimeChannel = _sb
        .channel('user_subs_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_subscriptions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) {
            debugPrint('[Subs] Realtime change detected — refreshing');
            unawaited(refreshStatus());
          },
        )
        .subscribe();
  }

  /// Called by AuthService on sign-in success.
  Future<void> onSignIn() async {
    await refreshStatus();
    _subscribeToRealtime();
    await restorePurchases();
  }

  /// Called by AuthService on sign-out. Clears local state.
  Future<void> onSignOut() async {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _status = SubscriptionStatus.notAuthenticated;
    _tier = null;
    _productId = null;
    _trialEndsAt = null;
    _expiresAt = null;
    _generationsUsed = 0;
    _generationsLimit = 0;
    _freeGensRemaining = 0;
    notifyListeners();
  }
}
