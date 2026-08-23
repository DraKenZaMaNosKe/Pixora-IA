import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing/purchase_gateway.dart';
import 'billing/play_purchase_gateway.dart';
import 'billing/product_catalog.dart';

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
/// 4. On purchase success, `_onPurchase` receives the event and calls
///    `_verifyPurchase(purchase)` which proxies to a Supabase Edge Function.
///    The Edge Function verifies the token with Google Play Developer API
///    and upserts `user_subscriptions`.
/// 5. UI listens via `ChangeNotifier` and re-reads `status`, `expiresAt`, etc.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final instance = SubscriptionService._();

  // ── Play Store product IDs (must match Play Console SKUs) ────────────

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
  StoreProduct? _monthlyProductInfo;
  bool _storeAvailable = false;
  bool _purchaseInFlight = false;

  final PurchaseGateway _gateway = PlayPurchaseGateway();

  /// Debug-only: lets the simulated purchase (which can't reach Play Billing
  /// on a sideloaded build) actually flip the app into the subscribed state,
  /// so the ad-free / mystery-free experience can be tested end to end. Never
  /// set outside debug — guarded by [debugGrantAccess].
  bool _debugForceAccess = false;

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
  bool get hasAccess => _debugForceAccess || _status.hasAccess;

  /// Debug-only entry point for the simulated purchase. No-op in release.
  void debugGrantAccess() {
    if (!kDebugMode) return;
    _debugForceAccess = true;
    notifyListeners();
  }

  /// True si el user puede generar IA. Dos caminos:
  ///   1. Suscriptor activo Y le quedan generations del plan
  ///   2. Tiene gens gratis disponibles (acumuladas por trial / promo)
  bool get canGenerate =>
      (hasAccess && generationsRemaining > 0) || _freeGensRemaining > 0;
  String? get monthlyPrice => _monthlyProductInfo?.formattedPrice;
  bool get storeAvailable => _storeAvailable;
  bool get purchaseInFlight => _purchaseInFlight;

  SupabaseClient get _sb => Supabase.instance.client;
  bool get _isLoggedIn => _sb.auth.currentUser != null;

  StreamSubscription<StorePurchase>? _purchaseSub;
  RealtimeChannel? _realtimeChannel;

  // ── Init / dispose ──────────────────────────────────────────────────

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

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _gateway.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  // ── Product catalog ─────────────────────────────────────────────────

  Future<void> _loadProducts() async {
    try {
      final products =
          await _gateway.queryProducts(ProductCatalog.allLogicalIds);
      for (final p in products) {
        if (p.logicalId == ProductCatalog.monthly) _monthlyProductInfo = p;
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

  /// Launches the store purchase sheet for the monthly subscription.
  /// Returns `true` if the sheet was launched; the actual purchase completion
  /// arrives asynchronously via the gateway's purchases stream. Returns
  /// `false` if the store could not show the sheet.
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
      final shown = await _gateway.buy(_monthlyProductInfo!);
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
      debugPrint('[Subs] restorePurchases → gateway.restore');
      await _gateway.restore();
      // Give the stream a moment to deliver restore events.
      await Future.delayed(const Duration(seconds: 2));
      debugPrint(
          '[Subs] restore done — saw $_restoredCountSinceCall purchases');
      return _restoredCountSinceCall;
    } catch (e) {
      debugPrint('[Subs] restorePurchases failed: $e');
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
    debugPrint(
        '[Subs] _verifyPurchase gave up after 3 attempts. last=$lastError');
    try {
      await refreshStatus();
    } catch (_) {}
  }

  // ── Realtime ────────────────────────────────────────────────────────

  /// Subscribe to `user_subscriptions` updates so a change on another device
  /// (or an RTDN event received on the server) reflects here within ~1s.
  void _subscribeToRealtime() {
    if (_realtimeChannel != null) return;
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
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
