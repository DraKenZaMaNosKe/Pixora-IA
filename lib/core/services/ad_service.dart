import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'credit_service.dart';
import 'grace_pass_service.dart';
import 'subscription_service.dart';

/// Centralised interstitial ad service with revenue analytics.
///
/// Every ad attempt (success OR failure) is logged to `ad_events` via
/// the `wp_log_ad_event` RPC. The admin dashboard reads from this table
/// to compute USD revenue estimates and per-user/per-placement breakdowns.
class AdService {
  AdService._();
  static final instance = AdService._();

  static const _interstitialAdUnitId = 'ca-app-pub-6734758230109098/6687118537';

  // App version is read lazily from PackageInfo (was hardcoded to '1.6.3').
  String? _appVersion;
  Future<String> _getAppVersion() async {
    if (_appVersion != null) return _appVersion!;
    try {
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = pkg.version;
    } catch (_) {
      _appVersion = 'unknown';
    }
    return _appVersion!;
  }

  /// DEBUG flag — bypass ads in debug builds only.
  /// Release AABs ship with kDebugMode=false, so revenue is never accidentally
  /// disabled in production (lesson from v1.7.2: a hardcoded `true` left over
  /// from local dev cost us 100% of ad revenue for several days).
  ///
  /// TEMPORAL 2026-05-05: forzado a false para que el usuario pueda probar el
  /// flujo de ads reales en debug build mientras prueba el welcome grace.
  /// REGRESAR a `kDebugMode` antes del próximo release v1.7.5 para mantener
  /// la salvaguarda original.
  static bool get _debugDisableAds => false;

  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;
  bool _isAdLoading = false;

  /// Alternating counter: ad shows on odd counts (1st, 3rd, 5th…),
  /// skips on even counts (2nd, 4th, 6th…).
  int _actionCount = 0;

  bool get isAdLoaded => _isAdLoaded;

  /// Whether the NEXT action will be ad-free.
  /// 2026-05-05: alternating disabled, every action shows ad → always false.
  /// Original logic (kept commented for easy restoration):
  ///   return _actionCount.isOdd;
  bool get isNextActionFree => false;

  /// Current flag value for debugging.
  int get debugFlag => _actionCount;

  /// Initialize Mobile Ads SDK. Call once at app startup.
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    loadInterstitialAd();
  }

  /// Pre-load an interstitial ad so it's ready when needed.
  void loadInterstitialAd() {
    if (_isAdLoading || _isAdLoaded) return;
    _isAdLoading = true;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdLoaded = true;
          _isAdLoading = false;
          debugPrint('[Pixora] Interstitial ad loaded');
        },
        onAdFailedToLoad: (error) {
          _isAdLoaded = false;
          _isAdLoading = false;
          debugPrint('[Pixora] Interstitial ad failed: ${error.message}');
          Future.delayed(
              const Duration(seconds: 10), () => loadInterstitialAd());
        },
      ),
    );
  }

  /// Show interstitial ad on alternating actions (1st yes, 2nd no, 3rd yes…).
  /// Awards credits when an ad is actually shown and watched.
  ///
  /// [placement]   — where in the app this ad was triggered
  ///                 (e.g. 'wallpaper_apply','aura_play','ringtones').
  /// [wallpaperId] — optional wallpaper context for per-wallpaper revenue attribution.
  void showInterstitialAd({
    required VoidCallback onAdDismissed,
    String? placement,
    String? wallpaperId,
  }) {
    _actionCount++;
    // alternating decision removed 2026-05-05; counter kept for analytics

    // ─── Subscription gate ──────────────────────────────────────────────────
    // Premium subscribers (active/trial/grace/cancelled-but-not-expired) see
    // NO ads — the value prop of the subscription is "no ads + extras".
    // Logged so the dashboard shows what we're skipping for premium users.
    if (SubscriptionService.instance.hasAccess) {
      _logAd(
        adKind: 'interstitial',
        placement: placement,
        wallpaperId: wallpaperId,
        shown: false,
        metadata: {'reason': 'subscriber_skip'},
      );
      onAdDismissed();
      return;
    }

    // ─── Welcome gift (one-time grace pass) ─────────────────────────────────
    // First wallpaper install after onboarding goes ad-free as the "regalo
    // de bienvenida" advertised at the end of the guided tour. Consume the
    // pass so subsequent installs follow normal alternating-skip rules.
    if (GracePassService.instance.hasGrace) {
      unawaited(GracePassService.instance.consume());
      _logAd(
        adKind: 'interstitial',
        placement: placement,
        wallpaperId: wallpaperId,
        shown: false,
        metadata: {'reason': 'welcome_grace'},
      );
      onAdDismissed();
      return;
    }

    // ─── Debug bypass ────────────────────────────────────────────────────────
    if (_debugDisableAds) {
      _logAd(
        adKind: 'interstitial',
        placement: placement,
        wallpaperId: wallpaperId,
        shown: false,
        metadata: {'debug_mode': true, 'reason': 'debug_disabled'},
      );
      onAdDismissed();
      return;
    }

    // ─── Alternating skip — DESHABILITADA 2026-05-05 ────────────────────────
    // Antes: 1 sí, 2 no (impar muestra, par salta) para suavizar UX.
    // Cambio: usuario quiere SIEMPRE mostrar ad. Más revenue, más simple,
    // y evita el bug de "cerrar/abrir burla el counter" (el contador vivía
    // en RAM y se reseteaba al matar la app). Cada decisión sigue logueada
    // server-side en `ad_events` para auditoría.
    // Para rehabilitar: regresar el bloque `if (!shouldShow) { ... }` y
    // mover el `_actionCount++` antes de los return paths.
    //
    // _actionCount sigue incrementando para que el log mantenga el contador
    // por sesión (analytics), pero no afecta la decisión de mostrar.

    // ─── Ad not preloaded → skip ─────────────────────────────────────────────
    if (_interstitialAd == null || !_isAdLoaded) {
      _logAd(
        adKind: 'interstitial',
        placement: placement,
        wallpaperId: wallpaperId,
        shown: false,
        metadata: {'reason': 'not_loaded'},
      );
      onAdDismissed();
      loadInterstitialAd();
      return;
    }

    // ─── Show the ad ─────────────────────────────────────────────────────────
    // Plain AdMob flow — let the SDK handle its own lifecycle. Previous
    // safety-timeout (60s then 25s) reverted 2026-05-05 because user
    // perceived the wait as "ad broken / paused" when it was actually
    // AdMob's own internal countdown before the close button became
    // tappable. AdMob ads always show their X eventually; trust the SDK.
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _isAdLoaded = false;
        loadInterstitialAd();
        // Log SHOWN: this is the revenue event.
        _logAd(
          adKind: 'interstitial',
          placement: placement,
          wallpaperId: wallpaperId,
          shown: true,
        );
        CreditService.instance.earnFromAd();
        onAdDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _isAdLoaded = false;
        loadInterstitialAd();
        _logAd(
          adKind: 'interstitial',
          placement: placement,
          wallpaperId: wallpaperId,
          shown: false,
          metadata: {'reason': 'show_failed', 'error': error.message},
        );
        onAdDismissed();
      },
    );

    _interstitialAd!.show();
  }

  /// Log a single ad event via the wp_log_ad_event RPC.
  /// Fire-and-forget — failures don't block the user flow.
  Future<void> _logAd({
    required String adKind,
    String? placement,
    String? wallpaperId,
    required bool shown,
    bool rewarded = false,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final box = Hive.isBoxOpen('wallpaper_likes')
          ? Hive.box('wallpaper_likes')
          : await Hive.openBox('wallpaper_likes');
      final deviceId = box.get('device_id') as String? ?? 'unknown';
      await Supabase.instance.client.rpc('wp_log_ad_event', params: {
        'p_device_id': deviceId,
        'p_ad_kind': adKind,
        'p_placement': placement,
        'p_unit_id': _interstitialAdUnitId,
        'p_wallpaper_id': wallpaperId,
        'p_shown': shown,
        'p_rewarded': rewarded,
        'p_app_version': await _getAppVersion(),
        if (metadata != null) 'p_metadata': metadata,
      });
    } catch (e) {
      debugPrint('[Pixora] wp_log_ad_event failed: $e');
    }
  }
}
