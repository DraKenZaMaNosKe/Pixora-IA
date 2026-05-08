import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart' show adShowingNotifier;
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
  /// 2026-05-08 madrugada: ads RE-HABILITADOS en debug porque el Navigator
  /// overlay (push de _AdOverlayScaffold antes del show) elimina la
  /// contención de memoria entre Flutter UI y AdMob. Ya NO matamos el
  /// :wallpaper process (causaba ANR) — el overlay sidesteps lifecycle
  /// completamente, removiendo widgets pesados del tree mientras el ad
  /// está visible.
  static bool get _debugDisableAds => false;

  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;
  bool _isAdLoading = false;

  /// Watchdog for broken ad creatives. AdMob legitimate countdowns max out
  /// around 30s before the X is tappable; if we hit 3 minutes with no
  /// dismiss/fail callback, the creative is broken and the user is stuck.
  /// We force-dispatch onAdDismissed to rescue the user. NOT a "perceived
  /// timeout" like the 25s/60s ones reverted in v1.7.6 — those interrupted
  /// legitimate ad lifecycles. 3 min is far outside any legitimate range.
  ///
  /// History: introduced 2026-05-07 in v1.7.10 after Eduardo got stuck for
  /// 2.5 hours with an ad creative that never emitted onAdDismissed.
  Timer? _adWatchdog;
  static const Duration _adWatchdogTimeout = Duration(minutes: 3);

  /// Alternating counter: ad shows on odd counts (1st, 3rd, 5th…),
  /// skips on even counts (2nd, 4th, 6th…).
  int _actionCount = 0;

  bool get isAdLoaded => _isAdLoaded;

  /// Whether the NEXT action will be ad-free (alternating skip kicks in).
  /// Returns true when [_actionCount] is even, meaning the next increment
  /// will land on an odd value (=> shows ad). Restored 2026-05-08 after
  /// v1.7.5's "always show" change made playable AdMob ads stutter on
  /// memory-pressed Samsung devices because users hit them every other
  /// wallpaper apply.
  bool get isNextActionFree => _actionCount.isEven;

  /// Current flag value for debugging.
  int get debugFlag => _actionCount;

  /// Initialize Mobile Ads SDK. Call once at app startup.
  Future<void> initialize() async {
    await MobileAds.instance.initialize();

    // Filter ad content via SDK (no AdMob console change required).
    // 2026-05-08: setting maxAdContentRating = G excludes game playables
    // and other heavy interactive creatives that AdMob's v8 SDK started
    // serving aggressively after the v5→v8 upgrade in commit 2361771
    // (April 2026). Those playables (Hill Climb Racing, Royal Match,
    // Royal Kingdom, etc.) need 200-400 MB GPU memory to render their
    // mini-game and stutter / freeze on Samsung mid-range devices.
    //
    // Content rating tiers (Google's SDK enum):
    //   G  → General audiences (retail, lifestyle, finance — usually static)
    //   PG → Parental guidance
    //   T  → Teen (includes most game playables with mild action)
    //   MA → Mature
    //
    // Trade-off: ~10-15% revenue drop because game playables pay highest
    // eCPM. Worth it because hung ads = abandoned app = no revenue at all
    // from those users + 1-star reviews.
    try {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.g),
      );
      debugPrint(
          '[Pixora] AdMob content rating capped at G (excludes heavy playables)');
    } catch (e) {
      debugPrint('[Pixora] updateRequestConfiguration error: $e');
    }

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
  Future<void> showInterstitialAd({
    required VoidCallback onAdDismissed,
    String? placement,
    String? wallpaperId,
  }) async {
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

    // ─── Alternating skip — RESTAURADO 2026-05-08 ─────────────────────────
    // 1 sí, 1 no (impar muestra, par salta). Esta es la cadencia que el
    // usuario llama "antes funcionaba bien". La quitamos en v1.7.5 (commit
    // d44ad04) buscando más revenue, pero los ads playable de AdMob (Hill
    // Climb, Royal Match, Royal Kingdom, etc.) son muy pesados en cels gama
    // media — al mostrar 100% de ads, Eduardo se topaba con playables
    // frecuentemente y se le trababa la app cada otro wallpaper. Volver
    // al alternating reduce a la mitad la exposición a creatives pesados
    // sin sacrificar revenue completo, y mantiene la sensación pulida de
    // las versiones < v1.7.5.
    //
    // Counter en RAM (no Hive): si el user mata y reabre la app, el
    // contador resetea a 0 → próxima acción muestra ad. Mismo
    // comportamiento que tenía antes; la "burla del counter" no es real
    // porque cuando matas la app, AdMob también pierde el ad pre-cargado,
    // así que efectivamente no hay ventaja en hacerlo.
    final shouldShow = _actionCount.isOdd;
    if (!shouldShow) {
      _logAd(
        adKind: 'interstitial',
        placement: placement,
        wallpaperId: wallpaperId,
        shown: false,
        metadata: {'reason': 'alternating_skip', 'count': _actionCount},
      );
      onAdDismissed();
      return;
    }

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
    //
    // EXCEPT: we now keep a 3-minute watchdog as last-resort rescue from
    // creatives that never emit any callback. 3 min is far outside any
    // legitimate AdMob countdown so won't interrupt real ads — only frees
    // the user when something is genuinely broken (v1.7.10 fix).
    // Saved limits restored after the ad closes. Declared up here so the
    // resumeFlutter closure below can capture them as upvalues.
    int? savedMaxBytes;
    int? savedMaxCount;

    bool callbackFired = false;
    bool overlayPushed = false;
    void cancelWatchdog() {
      _adWatchdog?.cancel();
      _adWatchdog = null;
    }

    Future<void> resumeFlutter() async {
      // Restore Flutter image cache to normal limits.
      try {
        final cache = PaintingBinding.instance.imageCache;
        final saveBytes = savedMaxBytes;
        final saveCount = savedMaxCount;
        if (saveBytes != null) cache.maximumSizeBytes = saveBytes;
        if (saveCount != null) cache.maximumSize = saveCount;
      } catch (_) {}
      // Restore the heavy catalog UI by flipping the notifier back to
      // false. PixoraApp's ValueListenableBuilder rebuilds with the
      // SplashPage child, widgets re-mount, user sees their app again.
      // This is the counterpart of the `adShowingNotifier.value = true`
      // we set before show(). The previous Navigator.push approach
      // didn't work because pushing doesn't unmount the route below.
      try {
        adShowingNotifier.value = false;
      } catch (_) {}
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        if (callbackFired) return;
        callbackFired = true;
        cancelWatchdog();
        unawaited(resumeFlutter());
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
        if (callbackFired) return;
        callbackFired = true;
        cancelWatchdog();
        unawaited(resumeFlutter());
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

    // Memory pressure mitigation BEFORE show(). AdMob's AdActivity is
    // translucent (styleTranslucent=true) so MainActivity stays alive
    // behind the ad and Flutter keeps rendering. Combined with the
    // `:wallpaper` process rendering 4192×1024 panoramics + canvas
    // scenes, total Pixora memory hits ~1 GB (522 MB in Graphics alone,
    // most of it Flutter's NetworkImage cache loaded across the catalog).
    // Playable ads stutter visibly and the screen stops responding to
    // touch as the OS thrashes through GC.
    //
    // Aggressive 5-layer fix:
    //   1. Clamp imageCache to ZERO (forces Skia to drop GPU bitmap buffers)
    //   2. Clear imageCache (logical) + live images
    //   3. Kill :wallpaper process (frees ~400-500 MB GPU)
    //   4. Pause FlutterEngine (stops AnimationControllers, Timers, frame loop)
    //   5. Brief delay so Skia/Android actually reclaim memory before show()
    //
    // History: 2026-05-07 ad stuck 2.5h, 2026-05-08 ads pausing/lagging
    // on Eduardo's Samsung. dumpsys meminfo showed Pixora at 1 GB PSS,
    // 522 MB Graphics — root cause.
    try {
      final cache = PaintingBinding.instance.imageCache;
      savedMaxBytes = cache.maximumSizeBytes;
      savedMaxCount = cache.maximumSize;
      cache.maximumSizeBytes = 0;
      cache.maximumSize = 0;
      cache.clear();
      cache.clearLiveImages();
    } catch (_) {}

    // ─── Root-swap overlay: THE fix ────────────────────────────────────────
    // Set the global adShowingNotifier so PixoraApp's ValueListenableBuilder
    // swaps its child from the live SplashPage tree to a single ColoredBox.
    // The heavy catalog UI (50+ widgets, NetworkImages, animations) is
    // UNMOUNTED — not just hidden. GPU memory drops, Flutter's frame loop
    // idles on a single static widget, AdMob can run smoothly.
    //
    // Earlier attempts:
    //   - kill :wallpaper process: caused ANR when OS tried to respawn
    //   - appIsPaused on FlutterEngine: lifecycle stayed "resumed" because
    //     AdActivity is translucent (MainActivity technically visible)
    //   - Navigator.push of overlay route: route below stays mounted in
    //     the Navigator's element tree, frame loop kept rendering at 13 fps
    //
    // Root swap via ValueNotifier sidesteps all of those problems. The
    // tradeoff: when ad ends, navigation state is lost (the user lands on
    // SplashPage rather than the screen they were on). Acceptable because
    // the typical flow after watching an ad for "Apply Wallpaper" is the
    // wallpaper IS applied — the user no longer needs to return to the
    // detail page anyway.
    try {
      adShowingNotifier.value = true;
      overlayPushed = true; // reused flag, just means "we flipped notifier"
    } catch (_) {}

    // Brief delay so the swap actually replaces the catalog UI before
    // AdMob loads its creative. Without this, the show() can race ahead
    // of Flutter's frame swap and the heavy tree is still in memory when
    // the playable starts loading.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Arm watchdog BEFORE show(). If the creative is broken and never emits
    // dismiss/fail, this rescues the user after 3 min instead of locking
    // them out forever (Eduardo got stuck 2.5 hours, 2026-05-07).
    _adWatchdog = Timer(_adWatchdogTimeout, () {
      if (callbackFired) return;
      callbackFired = true;
      debugPrint(
          '[Pixora] Ad watchdog fired after 3 min — creative broken, force-dismissing');
      unawaited(resumeFlutter());
      _interstitialAd?.dispose();
      _interstitialAd = null;
      _isAdLoaded = false;
      loadInterstitialAd();
      _logAd(
        adKind: 'interstitial',
        placement: placement,
        wallpaperId: wallpaperId,
        shown: false,
        metadata: {'reason': 'watchdog_timeout', 'timeout_seconds': 180},
      );
      onAdDismissed();
    });

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
