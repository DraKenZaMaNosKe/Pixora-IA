import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'credit_service.dart';
import 'free_hour_service.dart';
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

  /// ── MASTER AD SWITCH ──────────────────────────────────────────────────
  /// The single flag that flips ALL three ad formats (interstitial, banner,
  /// native) between Google TEST units and Pixora PRODUCTION units.
  ///
  /// Keep this `false` while the app is in closed/internal testing so testers
  /// only ever see test creatives — zero risk of an invalid-activity strike
  /// before we're officially in production. Flip to `true` the day Google
  /// approves production access, then rebuild. Banner + native read this same
  /// flag (see wallpaper_viewer_hud_page.dart and native_ad_service.dart).
  static const useProductionAds = false;

  // Interstitial unit IDs. Prod = Pixora_Interstitial_ApplyWallpaper.
  static const _prodInterstitialId = 'ca-app-pub-6734758230109098/6687118537';
  static const _testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static String get _interstitialAdUnitId =>
      useProductionAds ? _prodInterstitialId : _testInterstitialId;

  /// Channel to invoke native handlers — currently used to broadcast
  /// ad-visibility to the `:wallpaper` process so it drops to idle (1 fps)
  /// while AdMob is showing, freeing GPU/CPU for the ad. Same channel as
  /// the wallpaper handlers in MainActivity.
  static const _wallpaperChannel = MethodChannel('com.orbix.pixora/wallpaper');

  /// Tells the `:wallpaper` process to enter or leave idle mode (1 fps
  /// vs ~30 fps). Called before/after AdMob shows so the wallpaper
  /// doesn't fight the ad for GPU. Failure is non-critical — worst case
  /// the wallpaper keeps rendering and the ad stutters as before.
  static Future<void> _setWallpaperAdMode(bool adVisible) async {
    if (!Platform.isAndroid) return;
    try {
      await _wallpaperChannel.invokeMethod<bool>(
        'setWallpaperAdMode',
        {'visible': adVisible},
      );
    } catch (_) {
      // ignore — wallpaper service may not be running, that's fine
    }
  }

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

  /// Master switch: TRUE = ads completamente desactivados (cero AdMob calls,
  /// cero UI de ad, onAdDismissed se llama al toque y el usuario recibe
  /// credits inmediatamente). FALSE = ads se cargan y muestran normal.
  ///
  /// Estado actual (2026-05-14): TRUE durante toda la fase pre-Production.
  /// Razón: AdMob suspendió la cuenta 29 días por self-clicks de Eduardo
  /// durante testing. Para evitar segunda ofensa (ban permanente + retención
  /// 60d ingresos), apagamos AdMob completamente mientras la app sigue en
  /// Closed Testing y antes de tener tráfico real masivo. Pixora no genera
  /// revenue significativo aún (~$0-3/mes con 5 testers), no vale el riesgo.
  ///
  /// PARA REACTIVAR cuando lleguemos a Production con DAU real (~1000+):
  ///   1. Cambiar este getter a `false`
  ///   2. Cambiar `_interstitialAdUnitId` (línea ~30) del TEST ID al
  ///      production: 'ca-app-pub-6734758230109098/6687118537'
  ///   3. Verificar que `_testDeviceIds` tenga registrados todos los devices
  ///      donde Eduardo prueba la app
  ///   4. Build appbundle + subir a Play Console
  ///
  /// El flag se lee en showInterstitialAd() Y en initialize() — cuando está
  /// TRUE no se inicializa MobileAds SDK ni se hace loadInterstitialAd(),
  /// quedando AdMob completamente dormant del lado del cliente.
  ///
  /// History: v1.7.2 tuvo el bug opuesto (true left over) que costó revenue
  /// real. 2026-06-03: re-enabled — Samsung RF8X903KZ3K is in _testDeviceIds
  /// so this device gets TEST ads only (safe, no suspension risk). Real users
  /// get real ads and we restore revenue. Keep ALL test devices in
  /// _testDeviceIds before flipping this back on a new dev machine.
  // Eduardo 2026-07-20: sin ads en builds DEBUG para que él pruebe en su
  // Samsung sin interrupciones. Release (kDebugMode=false) NO se afecta —
  // producción sigue mostrando ads reales/test normalmente.
  static bool get _debugDisableAds => kDebugMode;

  /// True when ads should be globally suppressed for this user — either the
  /// debug flag is on or they have an active subscription. Both interstitial
  /// and native ad surfaces should consult this so the sub bypass + dev kill
  /// switch behave identically everywhere.
  static bool get adsDisabledForUser =>
      _debugDisableAds ||
      SubscriptionService.instance.hasAccess ||
      FreeHourService.instance.isActive;

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

  /// Whether the most recent [showInterstitialAd] call actually put an ad on
  /// screen. Every early return sets this false, so a caller that runs after
  /// the flow — RateService, deciding whether the moment is clean enough to
  /// ask for a review — can tell an ad-free apply from one that just
  /// interrupted the user.
  ///
  /// A field rather than parity arithmetic on [_actionCount]: reading the
  /// counter backwards is what left [isNextActionFree] inverted for two
  /// months. State that says what it means has no such failure mode.
  bool _lastActionShowedAd = false;
  bool get lastActionShowedAd => _lastActionShowedAd;

  bool get isAdLoaded => _isAdLoaded;

  /// Whether the NEXT action will be ad-free. Drives the "SIN AD"/"CON AD"
  /// badge and the diamonds line, so it has to answer the same question
  /// [showInterstitialAd] is about to answer — every gate included, not just
  /// the alternating cadence.
  ///
  /// Mirrors [showInterstitialAd] in order: the gates below return before the
  /// counter is touched, so they make an action ad-free whatever its parity.
  /// The cadence increments FIRST and shows on odd, so the next action is
  /// ad-free exactly when the counter is currently ODD (it lands on even =>
  /// skip).
  ///
  /// Was `_actionCount.isEven` until 2026-07-15, which inverted it: the badge
  /// promised "SIN AD" and then showed one, and offered "+N por ver" on the
  /// action that skips the ad (so nothing was earned). Subscribers, who never
  /// see an ad at all, got "CON AD" half the time.
  bool get isNextActionFree {
    if (SubscriptionService.instance.hasAccess) return true;
    if (FreeHourService.instance.isActive) return true;
    if (GracePassService.instance.hasGrace) return true;
    if (_debugDisableAds) return true;
    return _actionCount.isOdd;
  }

  /// Current flag value for debugging.
  int get debugFlag => _actionCount;

  /// Test device IDs registrados PERMANENTEMENTE en TODA build (debug y
  /// release). Cualquier ad servido a estos devices queda marcado como
  /// "test impression" — los clicks NO cuentan como tráfico real, no
  /// generan ingresos, y NUNCA disparan el detector de actividad inválida
  /// de AdMob. Esto blinda el AdMob account contra suspensiones por
  /// publisher self-clicks.
  ///
  /// Origen: 2026-05-14 — AdMob suspendió la cuenta 29 días por self-clicks
  /// detectados durante testing en el Samsung principal. Lección aprendida:
  /// SIEMPRE registrar test devices, aún en release builds, mientras la
  /// app no esté en Production con tráfico real masivo.
  ///
  /// Cómo obtener un nuevo Test Device ID: instala la app, conecta vía adb,
  /// `adb logcat | grep "setTestDeviceIds"` — la primera vez que el SDK
  /// inicializa, loguea el hint con el ID exacto. Agrégalo aquí.
  static const _testDeviceIds = <String>[
    '5B655AE2367833A19C9FD6920E3788F8', // Samsung RF8X903KZ3K (Eduardo principal)
    '6A586AD63419A924C043A270C880C788', // Huawei VNS-L53 G2R4C17516000149 (Eduardo)
  ];

  /// Initialize Mobile Ads SDK. Call once at app startup.
  /// Cuando _debugDisableAds está TRUE, NO inicializa el SDK ni hace
  /// requests — AdMob queda completamente dormant del lado del cliente.
  Future<void> initialize() async {
    if (_debugDisableAds) {
      debugPrint('[AdService] Ads disabled — skipping MobileAds init entirely');
      return;
    }
    // Registrar test devices ANTES de initialize() para que la primera
    // request los respete. El RequestConfiguration es global y persiste
    // todo el lifecycle del app.
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        testDeviceIds: _testDeviceIds,
        // v1.7.10 mitigation — G rating excludes heavy playable game ads that
        // OOM mid-range Samsungs. Was lost from the global init at some
        // refactor; only _BannerAdHost re-applied it (and only if the user
        // opened the HUD), so interstitials — the heavy format — were being
        // requested with no filter. This is the direct cause of "real ads
        // crash, test ads don't".
        maxAdContentRating: MaxAdContentRating.g,
      ),
    );
    await MobileAds.instance.initialize();
    loadInterstitialAd();
  }

  /// Pre-load an interstitial ad so it's ready when needed.
  void loadInterstitialAd() {
    // Defense in depth: si ads están desactivados, NO cargar. Importante
    // porque el callback Future.delayed(10s, () => loadInterstitialAd())
    // del onAdFailedToLoad puede ejecutarse después de que toggleamos el
    // _debugDisableAds (futuro: settings) — sin este guard, se queda en
    // un loop de retry con SDK no disponible.
    if (_debugDisableAds) return;
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
    // NOTE: _actionCount++ se MUEVE hasta después de los early-returns
    // (sub/grace/debug) para que la cadencia alternating solo cuente acciones
    // que realmente intentan mostrar ad. Antes contaba TODAS, dejando el
    // counter en estado random cuando el user perdía premium — el primer ad
    // post-downgrade podía ser "skip" o "show" según paridad histórica.

    // ─── Subscription gate ──────────────────────────────────────────────────
    // Premium subscribers (active/trial/grace/cancelled-but-not-expired) see
    // NO ads — the value prop of the subscription is "no ads + extras".
    // Logged so the dashboard shows what we're skipping for premium users.
    if (SubscriptionService.instance.hasAccess) {
      _lastActionShowedAd = false;
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

    // ─── Free Hour gate ─────────────────────────────────────────────────────
    // During the daily 30-min ad-free "happy hour", skip interstitials. Placed
    // BEFORE the welcome grace pass so a new user doesn't burn their one-time
    // ad-free gift during a Free Hour (they'd get nothing for it). Early-return
    // before _actionCount++ so the alternating cadence isn't contaminated.
    if (FreeHourService.instance.isActive) {
      _lastActionShowedAd = false;
      _logAd(
        adKind: 'interstitial',
        placement: placement,
        wallpaperId: wallpaperId,
        shown: false,
        metadata: {'reason': 'free_hour'},
      );
      onAdDismissed();
      return;
    }

    // ─── Welcome gift (one-time grace pass) ─────────────────────────────────
    // First wallpaper install after onboarding goes ad-free as the "regalo
    // de bienvenida" advertised at the end of the guided tour. Consume the
    // pass so subsequent installs follow normal alternating-skip rules.
    if (GracePassService.instance.hasGrace) {
      _lastActionShowedAd = false;
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
      _lastActionShowedAd = false;
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
    _actionCount++;
    final shouldShow = _actionCount.isOdd;
    if (!shouldShow) {
      _lastActionShowedAd = false;
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
      _lastActionShowedAd = false;
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

    // Past every gate: an ad is going on screen.
    _lastActionShowedAd = true;

    // ─── Show the ad ─────────────────────────────────────────────────────────
    // Minimal AdMob flow — trust the SDK. The 3-minute watchdog stays as a
    // last-resort rescue from creatives that never emit dismiss/fail
    // callback. Earlier "memory mitigation" attempts (imageCache clamp to
    // 0, root-swap to ColoredBox via ValueNotifier, kill :wallpaper, Flutter
    // pause via lifecycle, Navigator.push overlay) all CAUSED MORE BUGS
    // than they solved on Eduardo's Samsung 2026-05-08:
    //   - imageCache=0 + clearLiveImages right before show seems to
    //     interfere with the AdActivity's bitmap rendering (creatives
    //     loaded "by parts" / stuttered visibly).
    //   - Root-swap to ColoredBox didn't actually free GPU resources
    //     (Skia keeps allocations regardless of widget tree).
    //   - kill :wallpaper caused Android Not Responding when the OS
    //     tried to respawn.
    //   - appIsPaused() didn't work because Android lifecycle stays
    //     "resumed" through translucent AdActivity.
    //
    // The actual fixes that DID work and are kept elsewhere:
    //   - Impeller disabled in AndroidManifest (440 MB → 130 MB GL mtrack)
    //   - alternating skip restored (1 yes, 1 no)
    //   - MaxAdContentRating.g via SDK
    //   - Skia GPU cache cap 64 MB in main.dart postFrameCallback
    //   - Lazy loading of category rows + dispose offscreen carousels
    bool callbackFired = false;
    void cancelWatchdog() {
      _adWatchdog?.cancel();
      _adWatchdog = null;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        if (callbackFired) return;
        callbackFired = true;
        cancelWatchdog();
        unawaited(_setWallpaperAdMode(false)); // wallpaper back to normal
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
        unawaited(_setWallpaperAdMode(false));
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

    // Tell the :wallpaper process to drop to idle (1 fps) while the ad
    // is visible. This frees GPU/CPU so the AdActivity (which renders
    // translucent OVER our wallpaper) doesn't have to fight for resources.
    // History 2026-05-08 night: ANR "Wallpaper PixoraIA no responde"
    // happened repeatedly during ads because the canvas-scene wallpapers
    // (Goku, Mictlan, etc.) kept rendering parallax + particles at 30 fps
    // behind the ad. Idle mode was already implemented in the service
    // for other reasons; we just expose a broadcast switch for it.
    unawaited(_setWallpaperAdMode(true));

    // Arm watchdog BEFORE show(). If the creative is broken and never emits
    // dismiss/fail, this rescues the user after 3 min instead of locking
    // them out forever (Eduardo got stuck 2.5 hours, 2026-05-07).
    _adWatchdog = Timer(_adWatchdogTimeout, () {
      if (callbackFired) return;
      callbackFired = true;
      debugPrint(
          '[Pixora] Ad watchdog fired after 3 min — creative broken, force-dismissing');
      unawaited(_setWallpaperAdMode(false));
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
