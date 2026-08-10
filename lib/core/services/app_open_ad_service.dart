import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_service.dart';

/// App Open ad manager (2026-08-10).
///
/// Shows a SINGLE full-screen App Open ad when the user re-opens / returns to
/// the app — the compliant Google format for "entrada" monetization. Built to
/// protect the AdMob account (Eduardo's had a prior suspension):
///
///  - **Skips the very first launch** ever (good first impression + policy).
///  - **Frequency cap** ([_minGap]) so rapid app switching never nags.
///  - **Never stacks** on our own interstitial (checks
///    [AdService.lastFullScreenAdAt] — showing two full-screen ads back to
///    back is a policy violation).
///  - **Routed through [AdService.adsDisabledForUser]** → subscribers, Free
///    Hour and debug builds never see it.
///  - Respects the App Open ad's ~4h expiry ([_adTtl]).
///
/// Currently loads the Google TEST App Open unit (zero self-click risk). Swap
/// [_prodAppOpenId] for the real AdMob unit once created, and it activates for
/// production automatically (gated by [AdService.useProductionAds]).
class AppOpenAdService {
  AppOpenAdService._();
  static final instance = AppOpenAdService._();

  // Google TEST App Open unit — used in debug / when prod id is empty.
  static const String _testAppOpenId = 'ca-app-pub-3940256099942544/9257395921';
  // Pixora production App Open unit (AdMob "Pixora_AppOpen", created 2026-08-10).
  static const String _prodAppOpenId = 'ca-app-pub-6734758230109098/4300023419';
  static String get _adUnitId =>
      (AdService.useProductionAds && _prodAppOpenId.isNotEmpty)
          ? _prodAppOpenId
          : _testAppOpenId;

  static const String _kFirstLaunchDone = 'app_open_first_launch_done';
  static const Duration _minGap = Duration(minutes: 4); // frequency cap
  static const Duration _adTtl = Duration(hours: 4); // App Open ads expire ~4h
  static const Duration _afterInterstitial = Duration(seconds: 15);

  AppOpenAd? _ad;
  bool _isLoading = false;
  bool _isShowing = false;
  DateTime? _loadedAt;
  DateTime? _lastShown;
  bool _firstLaunchDone = false;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _firstLaunchDone = prefs.getBool(_kFirstLaunchDone) ?? false;
    } catch (_) {}
    _loadAd();
  }

  void _loadAd() {
    if (_isLoading || _ad != null) return;
    if (AdService.adsDisabledForUser) return; // don't even fetch for subs/debug
    _isLoading = true;
    AppOpenAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loadedAt = DateTime.now();
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          debugPrint('[AppOpenAd] load failed: $error');
        },
      ),
    );
  }

  bool get _isExpired =>
      _loadedAt == null || DateTime.now().difference(_loadedAt!) > _adTtl;

  /// Call when the app comes to the foreground (AppLifecycleState.resumed).
  /// All the gating lives here so callers just fire-and-forget.
  Future<void> showIfAvailable() async {
    if (_isShowing) return;
    // Subscribers / Free Hour / debug → never.
    if (AdService.adsDisabledForUser) return;

    // Don't stack on our own interstitial (returning from it fires `resumed`).
    final lastFs = AdService.lastFullScreenAdAt;
    if (lastFs != null &&
        DateTime.now().difference(lastFs) < _afterInterstitial) {
      return;
    }

    // Skip the very first launch — mark it and prime one for next time.
    if (!_firstLaunchDone) {
      _firstLaunchDone = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kFirstLaunchDone, true);
      } catch (_) {}
      _loadAd();
      return;
    }

    // Frequency cap.
    if (_lastShown != null &&
        DateTime.now().difference(_lastShown!) < _minGap) {
      return;
    }

    // Nothing ready (or stale) → drop it and load a fresh one for next time.
    if (_ad == null || _isExpired) {
      _ad?.dispose();
      _ad = null;
      _loadAd();
      return;
    }

    _ad!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _isShowing = true,
      onAdDismissedFullScreenContent: (ad) {
        _isShowing = false;
        _lastShown = DateTime.now();
        ad.dispose();
        _ad = null;
        _loadAd(); // preload the next one
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowing = false;
        debugPrint('[AppOpenAd] show failed: $error');
        ad.dispose();
        _ad = null;
        _loadAd();
      },
    );
    _ad!.show();
  }
}
